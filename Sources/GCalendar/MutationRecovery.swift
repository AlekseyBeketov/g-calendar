import Foundation

// Private app-local draft/identity, never a queue and never a log payload.
struct PendingMutation: Codable, Equatable, Identifiable {
    let id: UUID
    let operation: GWSOperation
    let arguments: [String]
    let startedAt: Date
    var resourceID: String?

    init(invocation: ProcessInvocation) {
        id = UUID()
        operation = invocation.operation
        arguments = invocation.arguments
        startedAt = Date()
        let params = Self.object("--params", arguments: arguments)
        switch operation {
        case .eventPatch, .eventDelete: resourceID = params["eventId"] as? String
        case .taskPatch, .taskDelete: resourceID = params["task"] as? String
        case .taskListPatch, .taskListDelete: resourceID = params["tasklist"] as? String
        default: resourceID = nil
        }
    }

    var body: [String: Any] { Self.object("--json", arguments: arguments) }
    var draftTitle: String { body["title"] as? String ?? body["summary"] as? String ?? "" }
    var draftNotes: String { body["notes"] as? String ?? "" }

    mutating func capture(_ response: Data) {
        guard resourceID == nil, let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let value = object["id"] as? String, !value.isEmpty else { return }
        resourceID = value
    }

    func invocation(executableURL: URL) -> ProcessInvocation {
        ProcessInvocation(executableURL: executableURL, arguments: arguments, operation: operation, timeout: 20, outputLimit: 2 * 1_024 * 1_024)
    }

    private static func object(_ flag: String, arguments: [String]) -> [String: Any] {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
}

enum MutationRecoveryFailure: Error, LocalizedError {
    case pendingVerification
    case unknownIdentity
    case corruptJournal

    var errorDescription: String? {
        switch self {
        case .pendingVerification: return "Результат изменения ещё не подтверждён. Проверьте сохранение; повторная запись заблокирована."
        case .unknownIdentity: return "Запрос мог быть принят, но его ID не получен. Сверьте результат в Google перед новой записью. Черновик сохранён на этом Mac."
        case .corruptJournal: return "Не удалось прочитать журнал проверки. Изменения заблокированы, чтобы избежать повторной записи. Существующий файл сохранён."
        }
    }
}

final class MutationJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL?
    private var record: PendingMutation?
    private var invalid = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do { record = try JSONDecoder().decode(PendingMutation.self, from: Data(contentsOf: fileURL)) }
            catch { invalid = true }
        }
    }

    var pending: PendingMutation? { lock.lock(); defer { lock.unlock() }; return record }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return invalid || record != nil }

    func begin(_ invocation: ProcessInvocation) throws {
        lock.lock(); defer { lock.unlock() }
        guard !invalid else { throw MutationRecoveryFailure.corruptJournal }
        guard record == nil else { throw MutationRecoveryFailure.pendingVerification }
        let value = PendingMutation(invocation: invocation)
        try persist(value)
        record = value
    }

    func capture(_ response: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard var value = record else { throw MutationRecoveryFailure.pendingVerification }
        value.capture(response)
        // Retain the ID in memory even if updating the on-disk journal fails.
        record = value
        try persist(value)
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        guard !invalid else { throw MutationRecoveryFailure.corruptJournal }
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        record = nil
    }

    /// Only called after the user explicitly confirms external reconciliation.
    func releaseAfterManualReview() throws {
        lock.lock(); defer { lock.unlock() }
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("reviewed-attempt-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: fileURL, to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        invalid = false
        record = nil
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

    func perform(_ invocation: ProcessInvocation, reader: GWSReadClient) throws -> GWSMutationResult {
        try journal.begin(invocation)
        let result: ProcessResult
        do { result = try runner.run(invocation) }
        catch {
            if let failure = error as? GWSFailure, failure == .executableUnavailable || failure == .invalidExecutablePath || failure == .forbiddenOperation {
                try journal.clear() // The process was never started.
                throw error
            }
            throw MutationRecoveryFailure.pendingVerification
        }
        try journal.capture(result.stdout)
        if result.exitCode != 0 {
            // A DELETE may have reached Google even when the CLI exits unsuccessfully.
            // Check the already-known exact ID once; never repeat the write.
            guard [.eventDelete, .taskDelete, .taskListDelete].contains(invocation.operation) else {
                throw MutationRecoveryFailure.pendingVerification
            }
            return try recheck(reader: reader)
        }
        if let pending = journal.pending { try onAccepted?(pending) }
        let verified = try GWSMutationService(runner: runner).verifyAccepted(invocation, response: result.stdout, reader: reader)
        guard verified.isReadBackVerified else { throw MutationRecoveryFailure.pendingVerification }
        try journal.clear()
        return verified
    }

    func recheck(reader: GWSReadClient) throws -> GWSMutationResult {
        guard let record = journal.pending else { throw MutationRecoveryFailure.pendingVerification }
        guard let id = record.resourceID else { throw MutationRecoveryFailure.unknownIdentity }
        let response = try JSONSerialization.data(withJSONObject: ["id": id])
        let result = try GWSMutationService(runner: runner).verifyAccepted(record.invocation(executableURL: reader.factory.executableURL),
                                                                         response: response, reader: reader)
        guard result.isReadBackVerified else { throw MutationRecoveryFailure.pendingVerification }
        try journal.clear()
        return result
    }
}
