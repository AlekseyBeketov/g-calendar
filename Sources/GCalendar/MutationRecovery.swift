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
    var contextIdentity: String?
    // One durable lease covers a bounded group of independent completed deletes.
    var relatedCompletedDeletes: [PendingMutation]?

    init(invocation: ProcessInvocation) {
        id = UUID()
        operation = invocation.operation
        arguments = invocation.arguments
        contextIdentity = invocation.contextIdentity
        expectedTask = invocation.expectedTask
        taskDestinationListID = invocation.taskDestinationListID
        startedAt = Date()
        let params = Self.object("--params", arguments: arguments)
        switch operation {
        case .eventPatch, .eventDelete: resourceID = params["eventId"] as? String
        case .taskPatch, .taskMove, .taskReorder, .taskDelete: resourceID = params["task"] as? String
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
                          expectedTask: expectedTask, taskDestinationListID: taskDestinationListID, contextIdentity: contextIdentity)
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
    func begin(_ invocation: ProcessInvocation, relatedCompletedDeletes: [ProcessInvocation] = []) throws -> UUID {
        try withExclusiveAccess {
            try reload()
            guard !invalid else { throw MutationRecoveryFailure.corruptJournal }
            guard record == nil else { throw MutationRecoveryFailure.pendingVerification }
            var value = PendingMutation(invocation: invocation)
            if !relatedCompletedDeletes.isEmpty {
                guard ([invocation] + relatedCompletedDeletes).allSatisfy({ $0.operation == .taskDelete && $0.expectedTask?.completed == true && $0.contextIdentity == invocation.contextIdentity }) else {
                    throw GWSFailure.forbiddenOperation
                }
                value.relatedCompletedDeletes = relatedCompletedDeletes.map { PendingMutation(invocation: $0) }
            }
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

    func retainCompletedDeletes(_ unresolved: Set<TaskSelectionIdentity>, expectedID: UUID) throws {
        try withExclusiveAccess {
            try reload()
            guard !invalid, let value = record, value.id == expectedID else { throw MutationRecoveryFailure.pendingVerification }
            var remaining = ([value] + (value.relatedCompletedDeletes ?? [])).filter {
                $0.expectedTask.map { unresolved.contains($0.selectionIdentity) } ?? false
            }
            guard !remaining.isEmpty else { try clear(expectedID: expectedID); return }
            var first = remaining.removeFirst()
            first.relatedCompletedDeletes = remaining.isEmpty ? nil : remaining.map { item in
                var item = item; item.relatedCompletedDeletes = nil; return item
            }
            try persist(first)
            record = first
            reviewState = .pending(first.id)
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

struct CompletedTaskDeletionResult {
    var verified: [ProcessInvocation] = []
    var skipped = 0
    var failure: Error?
}

private final class CompletedDeleteResults<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: Result<Value, Error>] = [:]

    func set(_ value: Result<Value, Error>, at index: Int) {
        lock.lock(); defer { lock.unlock() }
        values[index] = value
    }

    static func map(_ invocations: [ProcessInvocation], action: @escaping (ProcessInvocation) throws -> Value) -> [Result<Value, Error>] {
        let results = CompletedDeleteResults<Value>()
        DispatchQueue.concurrentPerform(iterations: invocations.count) { index in
            results.set(Result { try action(invocations[index]) }, at: index)
        }
        return invocations.indices.map { results.values[$0]! }
    }
}

private struct CompletedDeleteUnsubmittedFailure: Error {
    let cause: Error
}

struct RecoverableMutationService {
    let runner: GWSProcessRunning
    let journal: MutationJournal
    var onAccepted: ((PendingMutation) throws -> Void)? = nil
    var beforeCompletion: ((GWSMutationResult, PendingMutation) throws -> Void)? = nil

    func performCompletedDeletes(_ invocations: [ProcessInvocation], reader: GWSReadClient) -> CompletedTaskDeletionResult {
        var outcome = CompletedTaskDeletionResult()
        do {
            var identities = Set<TaskSelectionIdentity>()
            for invocation in invocations {
                guard invocation.operation == .taskDelete, let task = invocation.expectedTask, task.completed, !task.deleted,
                      invocation.contextIdentity == reader.factory.contextIdentity,
                      invocation.executableURL == reader.factory.executableURL,
                      (reader.factory.executableURL == GWSCommandFactory.restMarker) == (invocation.contextIdentity != nil),
                      WorkspaceSnapshotReducer.parameters(invocation)["task"] == task.id,
                      WorkspaceSnapshotReducer.parameters(invocation)["tasklist"] == task.taskListID,
                      !invocation.arguments.contains("--json"), identities.insert(task.selectionIdentity).inserted else {
                    throw GWSFailure.forbiddenOperation
                }
            }
            let tasksByList = Dictionary(grouping: invocations.compactMap(\.expectedTask), by: \.taskListID).mapValues {
                Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) })
            }
            func isAncestor(_ ancestor: GoogleTask, of task: GoogleTask) -> Bool {
                guard ancestor.taskListID == task.taskListID else { return false }
                var parent = task.parent, visited = Set<String>()
                while let id = parent, visited.insert(id).inserted {
                    if id == ancestor.id { return true }
                    parent = tasksByList[task.taskListID]?[id]?.parent
                }
                return false
            }
            try journal.withExclusiveAccess {
                guard !journal.isBlocked else { throw journal.blockingFailure ?? MutationRecoveryFailure.pendingVerification }
                var remaining = invocations
                while !remaining.isEmpty {
                    var window: [ProcessInvocation] = [], selected = Set<Int>()
                    for (index, invocation) in remaining.enumerated() {
                        let task = invocation.expectedTask!
                        // A task and its confirmed ancestors never share a concurrent window.
                        let dependent = window.contains { other in
                            let otherTask = other.expectedTask!
                            return isAncestor(task, of: otherTask) || isAncestor(otherTask, of: task)
                        }
                        if !dependent { window.append(invocation); selected.insert(index) }
                        if window.count == 4 { break }
                    }
                    remaining = remaining.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
                    let preflight = CompletedDeleteResults<Bool>.map(window) { invocation in
                        let expected = invocation.expectedTask!
                        guard let current = try reader.task(taskListID: expected.taskListID, taskID: expected.id) else { return false }
                        return current.id == expected.id && current.taskListID == expected.taskListID && current.completed && !current.deleted && current.parent == expected.parent
                    }
                    var ready: [ProcessInvocation] = []
                    for (invocation, result) in zip(window, preflight) {
                        if try result.get() { ready.append(invocation) } else { outcome.skipped += 1 }
                    }
                    guard let first = ready.first else { continue }
                    let attemptID = try journal.begin(first, relatedCompletedDeletes: Array(ready.dropFirst()))
                    let writes = CompletedDeleteResults<GWSMutationResult>.map(ready) { invocation in
                        let response: ProcessResult
                        do { response = try runner.run(invocation) }
                        catch {
                            let unsubmitted = invocation.executableURL == GWSCommandFactory.restMarker && error is GoogleRESTUnsubmittedFailure
                            let processNotStarted = (error as? GWSFailure).map { [.executableUnavailable, .invalidExecutablePath, .forbiddenOperation].contains($0) } ?? false
                            if unsubmitted || processNotStarted { throw CompletedDeleteUnsubmittedFailure(cause: error) }
                            throw error
                        }
                        // Even a failed DELETE response can follow a successful remote deletion.
                        let verified = try GWSMutationService(runner: runner).verifyAccepted(invocation, response: response.stdout, reader: reader)
                        guard verified == .resourceDeleted else { throw MutationRecoveryFailure.pendingVerification }
                        return verified
                    }
                    var unresolved = Set<TaskSelectionIdentity>()
                    for (invocation, result) in zip(ready, writes) {
                        switch result {
                        case .success:
                            outcome.verified.append(invocation)
                        case .failure(let error):
                            if let unsubmitted = error as? CompletedDeleteUnsubmittedFailure {
                                outcome.failure = unsubmitted.cause
                            } else {
                                unresolved.insert(invocation.expectedTask!.selectionIdentity)
                                outcome.failure = error
                            }
                        }
                    }
                    try journal.retainCompletedDeletes(unresolved, expectedID: attemptID)
                    if outcome.failure != nil { break }
                }
            }
        } catch {
            outcome.failure = error
        }
        return outcome
    }

    func perform(_ invocation: ProcessInvocation, reader: GWSReadClient) throws -> GWSMutationResult {
        guard invocation.contextIdentity == reader.factory.contextIdentity,
              (reader.factory.executableURL == GWSCommandFactory.restMarker) == (invocation.contextIdentity != nil) else { throw GWSFailure.forbiddenOperation }
        return try journal.withExclusiveAccess {
            if invocation.operation == .taskReorder {
                guard let expected = invocation.expectedTask, !expected.completed, !expected.deleted,
                      let paramsIndex = invocation.arguments.firstIndex(of: "--params"),
                      invocation.arguments.indices.contains(paramsIndex + 1),
                      let data = invocation.arguments[paramsIndex + 1].data(using: .utf8),
                      let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      params["task"] as? String == expected.id, params["tasklist"] as? String == expected.taskListID,
                      params["parent"] as? String == expected.parent, params["destinationTasklist"] == nil,
                      !invocation.arguments.contains("--json"),
                      let current = try reader.task(taskListID: expected.taskListID, taskID: expected.id),
                      !current.deleted, !current.completed, current.parent == expected.parent,
                      current.title == expected.title, (current.notes ?? "") == (expected.notes ?? ""), current.due == expected.due else {
                    throw GWSFailure.mutationNotVerified
                }
                if let previousID = params["previous"] as? String {
                    guard previousID != expected.id,
                          let previous = try reader.task(taskListID: expected.taskListID, taskID: previousID),
                          !previous.completed, !previous.deleted, previous.parent == expected.parent else {
                        throw GWSFailure.mutationNotVerified
                    }
                }
            }
            if invocation.operation == .taskDelete, let expected = invocation.expectedTask {
                guard let paramsIndex = invocation.arguments.firstIndex(of: "--params"),
                      invocation.arguments.indices.contains(paramsIndex + 1),
                      let data = invocation.arguments[paramsIndex + 1].data(using: .utf8),
                      let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      params["task"] as? String == expected.id, params["tasklist"] as? String == expected.taskListID else {
                    throw GWSFailure.forbiddenOperation
                }
                guard expected.completed, !expected.deleted,
                      let current = try reader.task(taskListID: expected.taskListID, taskID: expected.id),
                      current.id == expected.id, current.taskListID == expected.taskListID,
                      current.completed, !current.deleted, current.parent == expected.parent else {
                    throw GWSFailure.mutationNotVerified
                }
            }
            let attemptID = try journal.begin(invocation)
            let result: ProcessResult
            do { result = try runner.run(invocation) }
            catch {
                if error is GoogleRESTUnsubmittedFailure, invocation.executableURL == GWSCommandFactory.restMarker {
                    try journal.clear(expectedID: attemptID)
                    throw error
                }
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
            guard record.contextIdentity == reader.factory.contextIdentity,
                  (reader.factory.executableURL == GWSCommandFactory.restMarker) == (record.contextIdentity != nil) else { throw GWSFailure.forbiddenOperation }
            guard let id = record.resourceID else { throw MutationRecoveryFailure.unknownIdentity }
            if let related = record.relatedCompletedDeletes {
                for item in related {
                    guard item.operation == .taskDelete, item.expectedTask?.completed == true,
                          item.contextIdentity == record.contextIdentity, let resourceID = item.resourceID else { throw GWSFailure.forbiddenOperation }
                    let response = try JSONSerialization.data(withJSONObject: ["id": resourceID])
                    let verified = try GWSMutationService(runner: runner).verifyAccepted(item.invocation(executableURL: reader.factory.executableURL), response: response, reader: reader)
                    guard verified == .resourceDeleted else { throw MutationRecoveryFailure.pendingVerification }
                    try beforeCompletion?(verified, item)
                }
            }
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
