import Foundation
import Darwin

// Private app-local draft/identity, never a queue and never a log payload.
struct PendingMutation: Codable, Equatable, Identifiable {
    let id: UUID
    let operation: GWSOperation
    let arguments: [String]
    let startedAt: Date
    var resourceID: String?
    var expectedTask: GoogleTask?
    var taskDestinationListID: String?

    init(invocation: ProcessInvocation) {
        id = UUID()
        operation = invocation.operation
        arguments = invocation.arguments
        expectedTask = invocation.expectedTask
        taskDestinationListID = invocation.taskDestinationListID
        startedAt = Date()
        let params = Self.object("--params", arguments: arguments)
        switch operation {
        case .eventPatch, .eventDelete: resourceID = params["eventId"] as? String
        case .taskPatch, .taskMove, .taskDelete: resourceID = params["task"] as? String
        case .taskListPatch, .taskListDelete: resourceID = params["tasklist"] as? String
        default: resourceID = nil
        }
    }

    var body: [String: Any] { Self.object("--json", arguments: arguments) }
    var draftTitle: String { body["title"] as? String ?? body["summary"] as? String ?? expectedTask?.title ?? "" }
    var draftNotes: String { body["notes"] as? String ?? expectedTask?.notes ?? "" }
    var sourceTaskID: String? { Self.object("--params", arguments: arguments)["task"] as? String }
    var destinationTaskListID: String? { Self.object("--params", arguments: arguments)["destinationTasklist"] as? String ?? taskDestinationListID }

    mutating func capture(_ response: Data) {
        guard resourceID == nil || operation == .taskMove, let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let value = object["id"] as? String, !value.isEmpty else { return }
        resourceID = value
    }

    func invocation(executableURL: URL) -> ProcessInvocation {
        ProcessInvocation(executableURL: executableURL, arguments: arguments, operation: operation, timeout: 20, outputLimit: 2 * 1_024 * 1_024,
                          expectedTask: expectedTask, taskDestinationListID: taskDestinationListID)
    }

    private static func object(_ flag: String, arguments: [String]) -> [String: Any] {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
}

enum MutationRecoveryFailure: Error, Equatable, LocalizedError {
    case pendingVerification
    case unknownIdentity
    case corruptJournal
    case journalBusy

    var errorDescription: String? {
        switch self {
        case .pendingVerification: return "Результат изменения ещё не подтверждён. Проверьте сохранение; повторная запись заблокирована."
        case .unknownIdentity: return "Запрос мог быть принят, но его ID не получен. Сверьте результат в Google перед новой записью. Черновик сохранён на этом Mac."
        case .corruptJournal: return "Не удалось прочитать журнал проверки. Изменения заблокированы, чтобы избежать повторной записи. Существующий файл сохранён."
        case .journalBusy: return "В другой копии приложения выполняется изменение. Дождитесь завершения и повторите проверку. Новая запись пока заблокирована."
        }
    }
}

final class MutationJournal: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let fileURL: URL?
    private var record: PendingMutation?
    private var invalid = false
    private var corruptBytes: Data?
    private var leaseDepth = 0
    private var reviewState: ObservedState = .absent

    private enum ObservedState: Equatable {
        case absent
        case pending(UUID)
        case corrupt(Data?)
    }

    private var observedState: ObservedState {
        if invalid { return .corrupt(corruptBytes) }
        return record.map { .pending($0.id) } ?? .absent
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        do { try withExclusiveAccess { try reload(); reviewState = observedState } }
        catch { invalid = (error as? MutationRecoveryFailure) != .journalBusy }
    }

    var pending: PendingMutation? {
        review().pending
    }

    /// Read identity and failure under one lease; the UI must not combine two
    /// observations separated by another process changing the journal.
    func review() -> (pending: PendingMutation?, failure: MutationRecoveryFailure?) {
        do {
            return try withExclusiveAccess {
                try reload()
                reviewState = observedState
                return (record, invalid ? .corruptJournal : (record == nil ? nil : .pendingVerification))
            }
        } catch { return (nil, (error as? MutationRecoveryFailure) ?? .corruptJournal) }
    }
    var isBlocked: Bool {
        do { return try withExclusiveAccess { try reload(); return invalid || record != nil } }
        catch { return true }
    }

    var blockingFailure: MutationRecoveryFailure? {
        do {
            return try withExclusiveAccess {
                try reload()
                if invalid { return .corruptJournal }
                return record == nil ? nil : .pendingVerification
            }
        } catch {
            return (error as? MutationRecoveryFailure) ?? .corruptJournal
        }
    }

    @discardableResult
    func begin(_ invocation: ProcessInvocation) throws -> UUID {
        try withExclusiveAccess {
            try reload()
            guard !invalid else { throw MutationRecoveryFailure.corruptJournal }
            guard record == nil else { throw MutationRecoveryFailure.pendingVerification }
            let value = PendingMutation(invocation: invocation)
            try persist(value)
            record = value
            reviewState = .pending(value.id)
            return value.id
        }
    }

    func capture(_ response: Data, expectedID: UUID) throws {
        try withExclusiveAccess {
            try reload()
            guard !invalid, var value = record, value.id == expectedID else { throw MutationRecoveryFailure.pendingVerification }
            value.capture(response)
            // Retain the ID in memory even if updating the on-disk journal fails.
            record = value
            try persist(value)
        }
    }

    func clear(expectedID: UUID) throws {
        try withExclusiveAccess {
            try reload()
            guard !invalid else { throw MutationRecoveryFailure.corruptJournal }
            guard record?.id == expectedID else { throw MutationRecoveryFailure.pendingVerification }
            if let fileURL { try FileManager.default.removeItem(at: fileURL) }
            record = nil
            reviewState = .absent
        }
    }

    /// Only called after the user explicitly confirms external reconciliation.
    func releaseAfterManualReview(expectedID: UUID? = nil) throws {
        guard lock.try() else { throw MutationRecoveryFailure.journalBusy }
        defer { lock.unlock() }
        let expected = expectedID.map { ObservedState.pending($0) } ?? reviewState
        try withExclusiveAccess {
            try reload()
            guard expected == observedState, expected != .absent else { throw MutationRecoveryFailure.pendingVerification }
            if let fileURL {
                let backup = fileURL.deletingLastPathComponent().appendingPathComponent("reviewed-attempt-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: fileURL, to: backup)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            invalid = false
            corruptBytes = nil
            record = nil
            reviewState = .absent
        }
    }

    var reviewedAttemptID: UUID? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        if case .pending(let id) = reviewState { return id }
        return nil
    }

    // Stable sidecar inode: the JSON itself is atomically replaced. Hold this lease
    // through submission AND exact GET so another process cannot acknowledge it.
    // Nonblocking acquisition keeps a second app's UI responsive during network I/O.
    func withExclusiveAccess<T>(_ action: () throws -> T) throws -> T {
        guard lock.try() else { throw MutationRecoveryFailure.journalBusy }
        defer { lock.unlock() }
        if leaseDepth > 0 { return try action() }
        var descriptor: Int32 = -1
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            descriptor = Darwin.open(fileURL.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard descriptor >= 0 else { throw MutationRecoveryFailure.corruptJournal }
            guard fchmod(descriptor, mode_t(0o600)) == 0 else {
                Darwin.close(descriptor)
                throw MutationRecoveryFailure.corruptJournal
            }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let lockError = errno
                Darwin.close(descriptor)
                throw lockError == EWOULDBLOCK || lockError == EAGAIN ? MutationRecoveryFailure.journalBusy : .corruptJournal
            }
        }
        leaseDepth = 1
        defer {
            leaseDepth = 0
            if descriptor >= 0 { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        }
        return try action()
    }

    private func reload() throws {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            record = nil; invalid = false; corruptBytes = nil
            return
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { record = nil; invalid = true; corruptBytes = nil; throw MutationRecoveryFailure.corruptJournal }
        do {
            var saved = try JSONDecoder().decode(PendingMutation.self, from: data)
            if saved.id == record?.id, saved.resourceID == nil { saved.resourceID = record?.resourceID }
            record = saved; invalid = false; corruptBytes = nil
        } catch {
            record = nil; invalid = true; corruptBytes = data
        }
    }

    private func persist(_ value: PendingMutation) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

struct RecoverableMutationService {
    let runner: GWSProcessRunning
    let journal: MutationJournal
    var onAccepted: ((PendingMutation) throws -> Void)? = nil
    var beforeCompletion: ((GWSMutationResult, PendingMutation) throws -> Void)? = nil

    func perform(_ invocation: ProcessInvocation, reader: GWSReadClient) throws -> GWSMutationResult {
        try journal.withExclusiveAccess {
            let attemptID = try journal.begin(invocation)
            let result: ProcessResult
            do { result = try runner.run(invocation) }
            catch {
                if let failure = error as? GWSFailure, failure == .executableUnavailable || failure == .invalidExecutablePath || failure == .forbiddenOperation {
                    try journal.clear(expectedID: attemptID) // The process was never started.
                    throw error
                }
                throw MutationRecoveryFailure.pendingVerification
            }
            try journal.capture(result.stdout, expectedID: attemptID)
            if result.exitCode != 0 {
                // A DELETE may have reached Google even when the CLI exits unsuccessfully.
                // Check the already-known exact ID once; never repeat the write.
                guard [.eventDelete, .taskDelete, .taskListDelete].contains(invocation.operation) else {
                    throw MutationRecoveryFailure.pendingVerification
                }
                return try recheck(reader: reader, expectedID: attemptID)
            }
            if let pending = journal.pending { try onAccepted?(pending) }
            let verified = try GWSMutationService(runner: runner).verifyAccepted(invocation, response: result.stdout, reader: reader)
            guard verified.isReadBackVerified else { throw MutationRecoveryFailure.pendingVerification }
            guard let pending = journal.pending else { throw MutationRecoveryFailure.pendingVerification }
            try beforeCompletion?(verified, pending)
            try journal.clear(expectedID: attemptID)
            return verified
        }
    }

    func recheck(reader: GWSReadClient, expectedID: UUID? = nil) throws -> GWSMutationResult {
        let attemptID = expectedID ?? journal.reviewedAttemptID
        return try journal.withExclusiveAccess {
            guard let record = journal.pending, record.id == attemptID else { throw MutationRecoveryFailure.pendingVerification }
            guard let id = record.resourceID else { throw MutationRecoveryFailure.unknownIdentity }
            let response = try JSONSerialization.data(withJSONObject: ["id": id])
            let result = try GWSMutationService(runner: runner).verifyAccepted(record.invocation(executableURL: reader.factory.executableURL),
                                                                             response: response, reader: reader)
            guard result.isReadBackVerified else { throw MutationRecoveryFailure.pendingVerification }
            try beforeCompletion?(result, record)
            try journal.clear(expectedID: record.id)
            return result
        }
    }
}
