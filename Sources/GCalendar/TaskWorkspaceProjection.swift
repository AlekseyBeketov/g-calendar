import Foundation

enum TaskBoardItem: Identifiable {
    enum ID: Hashable {
        case task(TaskSelectionIdentity)
        case dateHeading(String)
        case completedHeading
    }

    case task(GoogleTask)
    case dateHeading(TaskDateGroup, isFirst: Bool)
    case completedHeading

    var id: ID {
        switch self {
        case .task(let task): return .task(task.selectionIdentity)
        case .dateHeading(let group, _): return .dateHeading(group.id)
        case .completedHeading: return .completedHeading
        }
    }
}

struct TaskBoardRowsContent {
    let tasks: [GoogleTask]
    let identities: [TaskSelectionIdentity]
    let items: [TaskBoardItem]
    let sortMode: TaskSortMode

    init(sortedTasks: [GoogleTask], sortMode: TaskSortMode, today: DateOnly) {
        tasks = sortedTasks
        identities = sortedTasks.map(\.selectionIdentity)
        self.sortMode = sortMode

        var items: [TaskBoardItem] = []
        items.reserveCapacity(sortedTasks.count + 1)
        if sortMode == .date {
            for (index, group) in TaskOrdering.dateGroups(fromSortedTasks: sortedTasks, today: today).enumerated() {
                items.append(.dateHeading(group, isFirst: index == 0))
                items.append(contentsOf: group.tasks.lazy.map(TaskBoardItem.task))
            }
        } else {
            var addedCompletedHeading = false
            for task in sortedTasks {
                if task.completed && !addedCompletedHeading {
                    items.append(.completedHeading)
                    addedCompletedHeading = true
                }
                items.append(.task(task))
            }
        }
        self.items = items
    }
}

// Owned by WorkspaceViewModel. Row and keyboard data are shared across body updates.
final class TaskWorkspaceProjection {
    let orderedLists: [TaskList]
    let boardGroups: [TaskBoardGroup]
    let taskCount: Int
    private let preferences: TaskWorkspacePreferences
    private let today: DateOnly
    private var rowsByBoard: [String: TaskBoardRowsContent] = [:]

    private(set) lazy var unifiedRows = TaskBoardRowsContent(
        sortedTasks: TaskOrdering.sorted(boardGroups.flatMap(\.tasks), mode: preferences.unifiedSortMode),
        sortMode: preferences.unifiedSortMode, today: today
    )
    private(set) lazy var columnTasks = boardGroups.flatMap(\.tasks)
    private(set) lazy var columnIdentities = columnTasks.map(\.selectionIdentity)

    init(snapshot: WorkspaceSnapshot, preferences: TaskWorkspacePreferences, selectedListID: String?,
         filter: TaskWorkspaceFilter, searchText: String, today: DateOnly) {
        self.preferences = preferences
        self.today = today
        orderedLists = preferences.orderedBoards(snapshot.taskLists)
        let lists = orderedLists.filter { selectedListID == nil || $0.id == selectedListID }
        let scopedTasks = snapshot.tasks.filter { !$0.deleted && (selectedListID == nil || $0.taskListID == selectedListID) }
        taskCount = scopedTasks.count
        let visible = TaskWorkspaceLayout.filteredTasks(scopedTasks, filter: filter, selectedTaskListID: nil,
                                                       searchText: searchText, today: today)
        boardGroups = TaskWorkspaceLayout.boardGroups(visible, lists: lists).map { group in
            TaskBoardGroup(board: group.board, tasks: TaskOrdering.sorted(group.tasks, mode: preferences.sortMode(for: group.id)))
        }
    }

    func rows(for board: TaskBoardGroup) -> TaskBoardRowsContent {
        if let rows = rowsByBoard[board.id] { return rows }
        let rows = TaskBoardRowsContent(sortedTasks: board.tasks, sortMode: preferences.sortMode(for: board.id), today: today)
        rowsByBoard[board.id] = rows
        return rows
    }
}
