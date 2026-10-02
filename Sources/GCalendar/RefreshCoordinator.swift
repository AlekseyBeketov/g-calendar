import Foundation

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
}

struct WorkspaceRefreshQuery: Equatable {
    let range: DateRange
    let scope: WorkspaceRefreshScope
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
