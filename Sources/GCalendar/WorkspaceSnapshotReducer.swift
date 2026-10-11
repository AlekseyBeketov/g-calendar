import Foundation

// Only exact, verified Google results enter the local snapshot.
enum WorkspaceSnapshotReducer {
    static func applying(invocation: ProcessInvocation, result: GWSMutationResult, to snapshot: WorkspaceSnapshot) throws -> WorkspaceSnapshot {
        var updated = snapshot
        let params = parameters(invocation)
        switch result {
        case .taskVerified(let task):
            if invocation.operation == .taskMove {
                guard let source = params["tasklist"], let id = params["task"] else { throw GWSFailure.mutationNotVerified }
                updated.tasks.removeAll { $0.taskListID == source && $0.id == id }
            }
            if task.deleted { updated.tasks.removeAll { $0.taskListID == task.taskListID && $0.id == task.id } }
            else if let index = updated.tasks.firstIndex(where: { $0.taskListID == task.taskListID && $0.id == task.id }) { updated.tasks[index] = task }
            else { updated.tasks.append(task) }
        case .eventVerified(let event):
            updated = CalendarRangeCache.applying(event: event, identity: CalendarEventIdentity(calendarID: event.calendarID, eventID: event.id), to: updated)
            if let index = updated.events.firstIndex(where: { $0.calendarID == event.calendarID && $0.id == event.id }) { updated.events[index] = event }
            else { updated.events.append(event) }
        case .taskListVerified(let list):
            if let index = updated.taskLists.firstIndex(where: { $0.id == list.id }) { updated.taskLists[index] = list }
            else { updated.taskLists.append(list) }
        case .resourceDeleted:
            switch invocation.operation {
            case .taskDelete:
                guard let list = params["tasklist"], let id = params["task"] else { throw GWSFailure.mutationNotVerified }
                updated.tasks.removeAll { $0.taskListID == list && $0.id == id }
            case .eventDelete:
                guard let calendar = params["calendarId"], let id = params["eventId"] else { throw GWSFailure.mutationNotVerified }
                updated = CalendarRangeCache.applying(event: nil, identity: CalendarEventIdentity(calendarID: calendar, eventID: id), to: updated)
                updated.events.removeAll { $0.calendarID == calendar && $0.id == id }
            case .taskListDelete:
                guard let list = params["tasklist"] else { throw GWSFailure.mutationNotVerified }
                updated.taskLists.removeAll { $0.id == list }
                updated.tasks.removeAll { $0.taskListID == list }
            default: throw GWSFailure.mutationNotVerified
            }
        case .requestAccepted: throw GWSFailure.mutationNotVerified
        }
        return updated
    }

    static func affectedTaskListIDs(invocation: ProcessInvocation, result: GWSMutationResult) -> Set<String> {
        guard case .taskVerified(let task) = result else { return [] }
        var ids: Set<String> = [task.taskListID]
        if let source = parameters(invocation)["tasklist"] { ids.insert(source) }
        return ids
    }

    static func parameters(_ invocation: ProcessInvocation) -> [String: String] {
        guard let index = invocation.arguments.firstIndex(of: "--params"), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { $0 as? String }
    }
}

// Main-actor caller owns this value. Readers never write the cache. A mutation
// invalidates every read started before it, including complete-sync prune proofs.
struct WorkspaceSnapshotAcceptance {
    private(set) var revision = 0
    private let freshness = WorkspaceSnapshotFreshness()

    mutating func verifiedMutation() { revision += 1; freshness.invalidate() }

    func currentGuard() -> () -> Bool { freshness.currentGuard() }

    mutating func accept(_ read: GWSWorkspaceReadResult, startedAt revision: Int, current: WorkspaceSnapshot,
                cache: SnapshotStoring, displayRange: DateRange? = nil) throws -> WorkspaceSnapshot? {
        guard revision == self.revision else { return nil }
        let merged = try read.merging(into: current, displayRange: displayRange)
        try cache.commit(merged)
        self.revision += 1
        freshness.invalidate()
        return merged
    }
}

// Reminder reconciliation resumes on arbitrary executors after scheduler awaits.
// This guard never reads actor-isolated UI state from those continuations.
private final class WorkspaceSnapshotFreshness: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func invalidate() { lock.lock(); generation += 1; lock.unlock() }

    func currentGuard() -> () -> Bool {
        lock.lock(); let captured = generation; lock.unlock()
        return { [self] in
            lock.lock(); defer { lock.unlock() }
            return captured == generation
        }
    }
}
