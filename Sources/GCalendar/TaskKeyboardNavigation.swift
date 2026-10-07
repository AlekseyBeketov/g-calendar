import Foundation

/// Google's task IDs belong to a list; selection and scroll anchors use both IDs.
struct TaskSelectionIdentity: Hashable {
    let taskListID: String
    let taskID: String

    init(_ task: GoogleTask) {
        taskListID = task.taskListID
        taskID = task.id
    }
}

enum TaskKeyboardCommand: Equatable {
    case previous, next, edit, toggleCompletion
}

enum TaskKeyboardNavigation {
    static func command(keyCode: UInt16, hasModifiers: Bool, isRepeat: Bool) -> TaskKeyboardCommand? {
        guard !hasModifiers else { return nil }
        switch keyCode {
        case 126: return .previous
        case 125: return .next
        case 36, 76: return isRepeat ? nil : .edit
        case 49: return isRepeat ? nil : .toggleCompletion
        default: return nil
        }
    }

    static func visibleTasks(filteredTasks: [GoogleTask], groups: [(String, [GoogleTask])],
                             usesGroups: Bool, usesColumns: Bool, collapsedGroups: Set<String>) -> [GoogleTask] {
        guard usesGroups else { return filteredTasks }
        return groups.filter { usesColumns || !collapsedGroups.contains($0.0) }.flatMap(\.1)
    }

    static func movedSelection(_ selected: TaskSelectionIdentity?, in visible: [TaskSelectionIdentity],
                               command: TaskKeyboardCommand) -> TaskSelectionIdentity? {
        guard !visible.isEmpty else { return nil }
        guard let selected, let index = visible.firstIndex(of: selected) else {
            return command == .previous ? visible.last : visible.first
        }
        switch command {
        case .previous: return visible[max(0, index - 1)]
        case .next: return visible[min(visible.count - 1, index + 1)]
        case .edit, .toggleCompletion: return selected
        }
    }

    static func reconciledSelection(_ selected: TaskSelectionIdentity?, previous: [TaskSelectionIdentity],
                                    visible: [TaskSelectionIdentity]) -> TaskSelectionIdentity? {
        guard let selected else { return nil }
        if visible.contains(selected) { return selected }
        guard !visible.isEmpty else { return nil }
        let index = previous.firstIndex(of: selected) ?? 0
        return visible[min(index, visible.count - 1)]
    }
}

extension GoogleTask {
    var selectionIdentity: TaskSelectionIdentity { TaskSelectionIdentity(self) }
}
