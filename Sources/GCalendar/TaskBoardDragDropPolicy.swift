import Foundation

enum TaskBoardDragDropPolicy {
    static func canStartMovingBetweenBoards(_ task: GoogleTask, mutationsBlocked: Bool) -> Bool {
        !mutationsBlocked && !task.completed && !task.deleted
    }

    static func canStartDragging(_ task: GoogleTask, sourceSortMode: TaskSortMode, mutationsBlocked: Bool) -> Bool {
        sourceSortMode == .manual && canStartMovingBetweenBoards(task, mutationsBlocked: mutationsBlocked)
    }

    static func canMove(_ task: GoogleTask, to destinationTaskListID: String,
                        mutationsBlocked: Bool) -> Bool {
        canStartMovingBetweenBoards(task, mutationsBlocked: mutationsBlocked)
            && !destinationTaskListID.isEmpty
            && destinationTaskListID != task.taskListID
    }
}
