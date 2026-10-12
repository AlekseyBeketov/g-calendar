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
        case .taskListInsert, .taskListPatch, .taskListDelete, .taskInsert, .taskPatch, .taskMove, .taskReorder, .taskDelete: return .tasks
        default: return nil
        }
    }
}

enum WorkspaceRefreshPurpose: Equatable { case foreground, revalidation, prefetch }

struct WorkspaceRefreshQuery: Equatable {
    let range: DateRange
    let scope: WorkspaceRefreshScope
    let requestID: Int?
    let taskListIDs: Set<String>
    let calendarIDs: Set<String>
    let refreshTaskLists: Bool
    let purpose: WorkspaceRefreshPurpose

    init(range: DateRange, scope: WorkspaceRefreshScope, requestID: Int? = nil, taskListIDs: Set<String> = [], calendarIDs: Set<String> = [], refreshTaskLists: Bool = false, purpose: WorkspaceRefreshPurpose = .foreground) {
        self.range = range
        self.scope = scope
        self.requestID = requestID
        self.taskListIDs = taskListIDs
        self.calendarIDs = calendarIDs
        self.refreshTaskLists = refreshTaskLists
        self.purpose = purpose
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
        if query.purpose != .foreground { return nil }
        if active.key == query, pending == nil { return nil }
        pending = pending.map { merge($0, query) } ?? query
        return nil
    }

    mutating func finish(_ ticket: RefreshTicket<WorkspaceRefreshQuery>, completed read: GWSWorkspaceReadResult? = nil, discardActive: Bool = false) -> RefreshFinish<WorkspaceRefreshQuery> {
        guard active == ticket else { return .ignored }
        let requested = pending
        pending = nil
        active = nil
        guard let requested else { return .accepted }
        if let read {
            guard let residual = remaining(requested, after: read, ticket: ticket) else { return .accepted }
            return .superseded(start(residual))
        }
        // Failed/stale foreground work remains required. Obsolete speculative
        // reads have no mandatory scope and are dropped for foreground work.
        let retry = ticket.key.purpose == .foreground && !discardActive ? merge(ticket.key, requested) : requested
        return .superseded(start(retry))
    }

    private mutating func start(_ query: WorkspaceRefreshQuery) -> RefreshTicket<WorkspaceRefreshQuery> {
        nextGeneration += 1
        let ticket = RefreshTicket(generation: nextGeneration, key: query)
        active = ticket
        return ticket
    }

    private func remaining(_ query: WorkspaceRefreshQuery, after read: GWSWorkspaceReadResult,
                           ticket: RefreshTicket<WorkspaceRefreshQuery>) -> WorkspaceRefreshQuery? {
        // A later explicit refresh is not satisfied by an older request.
        if let requestID = query.requestID, requestID != ticket.key.requestID { return query }
        let covered = CalendarRangeCoverage(range: read.range).covers(query.range)
        let needsCalendar = (query.scope == .full || query.scope == .calendarRange) && !(read.completeCalendar && covered)
        let needsTasks = (query.scope == .full || query.scope == .tasks) && !read.completeTasks
        let calendarIDs = covered ? query.calendarIDs.subtracting(read.calendarIDs) : query.calendarIDs
        let taskListIDs = read.completeTasks ? [] : query.taskListIDs.subtracting(read.taskListIDs)
        let structure = query.refreshTaskLists && read.taskLists == nil
        guard needsCalendar || needsTasks || !calendarIDs.isEmpty || !taskListIDs.isEmpty || structure else { return nil }
        let scope: WorkspaceRefreshScope = needsCalendar && needsTasks ? .full : needsCalendar ? .calendarRange : needsTasks ? .tasks : .targeted
        return WorkspaceRefreshQuery(range: query.range, scope: scope, requestID: query.requestID,
                                     taskListIDs: taskListIDs, calendarIDs: calendarIDs, refreshTaskLists: structure, purpose: query.purpose)
    }

    private func merge(_ previous: WorkspaceRefreshQuery, _ latest: WorkspaceRefreshQuery) -> WorkspaceRefreshQuery {
        let scopes = [previous.scope, latest.scope]
        let calendar = scopes.contains(.calendarRange)
        let tasks = scopes.contains(.tasks)
        let scope: WorkspaceRefreshScope = scopes.contains(.full) || (calendar && tasks) ? .full
            : calendar ? .calendarRange : tasks ? .tasks : .targeted
        return WorkspaceRefreshQuery(range: latest.range, scope: scope, requestID: latest.requestID ?? previous.requestID,
                                     taskListIDs: previous.taskListIDs.union(latest.taskListIDs),
                                     calendarIDs: previous.calendarIDs.union(latest.calendarIDs),
                                     refreshTaskLists: previous.refreshTaskLists || latest.refreshTaskLists, purpose: .foreground)
    }
}
