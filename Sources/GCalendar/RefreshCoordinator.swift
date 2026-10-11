import Foundation

enum WorkspaceSyncState: Equatable {
    case idle, syncing, updated, stale, setupRequired, offline, failed

    static func afterFailure(_ failure: GWSFailure?) -> WorkspaceSyncState {
        switch failure {
        case .executableUnavailable, .invalidExecutablePath: return .setupRequired
        case .processFailed(_, _, "auth_or_permission"): return .setupRequired
        case .processFailed(_, _, "network"): return .offline
        default: return .failed
        }
    }
}

struct RefreshTicket<Key: Equatable>: Equatable {
    let generation: Int
    let key: Key
}

enum RefreshFinish<Key: Equatable> {
    case accepted
    case superseded(RefreshTicket<Key>)
    case ignored
}

enum WorkspaceRefreshScope: Equatable {
    case full
    case calendarRange
    case tasks
    case targeted

    static func afterVerifiedMutation(_ operation: GWSOperation) -> WorkspaceRefreshScope? {
        switch operation {
        case .eventInsert, .eventPatch, .eventDelete: return .calendarRange
        case .taskListInsert, .taskListPatch, .taskListDelete, .taskInsert, .taskPatch, .taskMove, .taskDelete: return .tasks
        default: return nil
        }
    }
}

struct WorkspaceRefreshQuery: Equatable {
    let range: DateRange
    let scope: WorkspaceRefreshScope
    let requestID: Int?
    let taskListIDs: Set<String>
    let calendarIDs: Set<String>
    let refreshTaskLists: Bool

    init(range: DateRange, scope: WorkspaceRefreshScope, requestID: Int? = nil, taskListIDs: Set<String> = [], calendarIDs: Set<String> = [], refreshTaskLists: Bool = false) {
        self.range = range
        self.scope = scope
        self.requestID = requestID
        self.taskListIDs = taskListIDs
        self.calendarIDs = calendarIDs
        self.refreshTaskLists = refreshTaskLists
    }

    static func targeted(range: DateRange, coverage: CalendarRangeCoverage?, taskListIDs: Set<String>,
                         calendarIDs: Set<String>, requestID: Int) -> WorkspaceRefreshQuery {
        if !calendarIDs.isEmpty {
            if let coverage, coverage.covers(range), let zone = TimeZone(identifier: coverage.timeZoneID),
               let coveredRange = try? DateRange(start: coverage.start, endExclusive: coverage.endExclusive, timeZone: zone) {
                return WorkspaceRefreshQuery(range: coveredRange, scope: .targeted, requestID: requestID,
                                             taskListIDs: taskListIDs, calendarIDs: calendarIDs)
            }
            return WorkspaceRefreshQuery(range: range, scope: .calendarRange, requestID: requestID,
                                         taskListIDs: taskListIDs, calendarIDs: calendarIDs)
        }
        return WorkspaceRefreshQuery(range: range, scope: .targeted, requestID: requestID, taskListIDs: taskListIDs)
    }

}

struct LatestWinsRefreshCoordinator<Key: Equatable> {
    private(set) var active: RefreshTicket<Key>?
    private var pending: Key?
    private var nextGeneration = 0

    mutating func request(_ key: Key) -> RefreshTicket<Key>? {
        if let active {
            pending = active.key == key ? nil : key
            return nil
        }
        return start(key)
    }

    mutating func finish(_ ticket: RefreshTicket<Key>) -> RefreshFinish<Key> {
        guard active == ticket else { return .ignored }
        guard let pending else {
            active = nil
            return .accepted
        }
        self.pending = nil
        return .superseded(start(pending))
    }

    private mutating func start(_ key: Key) -> RefreshTicket<Key> {
        nextGeneration += 1
        let ticket = RefreshTicket(generation: nextGeneration, key: key)
        active = ticket
        return ticket
    }
}

// Latest navigation range wins; required domain reads are accumulated until
// accepted. Superseding a ticket cannot forget a mutation reconciliation.
struct WorkspaceRefreshCoordinator {
    private(set) var active: RefreshTicket<WorkspaceRefreshQuery>?
    private var pending: WorkspaceRefreshQuery?
    private var nextGeneration = 0

    mutating func request(_ query: WorkspaceRefreshQuery) -> RefreshTicket<WorkspaceRefreshQuery>? {
        guard let active else { return start(query) }
        if active.key == query, pending == nil { return nil }
        pending = merge(pending ?? active.key, query)
        return nil
    }

    mutating func finish(_ ticket: RefreshTicket<WorkspaceRefreshQuery>) -> RefreshFinish<WorkspaceRefreshQuery> {
        guard active == ticket else { return .ignored }
        guard let pending else { active = nil; return .accepted }
        self.pending = nil
        return .superseded(start(pending))
    }

    private mutating func start(_ query: WorkspaceRefreshQuery) -> RefreshTicket<WorkspaceRefreshQuery> {
        nextGeneration += 1
        let ticket = RefreshTicket(generation: nextGeneration, key: query)
        active = ticket
        return ticket
    }

    private func merge(_ previous: WorkspaceRefreshQuery, _ latest: WorkspaceRefreshQuery) -> WorkspaceRefreshQuery {
        let scopes = [previous.scope, latest.scope]
        let calendar = scopes.contains(.calendarRange)
        let tasks = scopes.contains(.tasks)
        let scope: WorkspaceRefreshScope = scopes.contains(.full) || (calendar && tasks) ? .full
            : calendar ? .calendarRange : tasks ? .tasks : .targeted
        return WorkspaceRefreshQuery(range: latest.range, scope: scope, requestID: latest.requestID,
                                     taskListIDs: previous.taskListIDs.union(latest.taskListIDs),
                                     calendarIDs: previous.calendarIDs.union(latest.calendarIDs),
                                     refreshTaskLists: previous.refreshTaskLists || latest.refreshTaskLists)
    }
}
