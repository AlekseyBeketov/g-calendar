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

    init(range: DateRange, scope: WorkspaceRefreshScope, requestID: Int? = nil) {
        self.range = range
        self.scope = scope
        self.requestID = requestID
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
