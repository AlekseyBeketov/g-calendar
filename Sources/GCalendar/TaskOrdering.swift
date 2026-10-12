import Foundation

enum TaskSortMode: String, Codable, CaseIterable {
    case manual, date, title

    var title: String {
        switch self {
        case .manual: return "Свой порядок"
        case .date: return "Дата"
        case .title: return "Название"
        }
    }
}

enum TaskOrdering {
    static func sorted(_ tasks: [GoogleTask], mode: TaskSortMode) -> [GoogleTask] {
        let active = tasks.filter { !$0.completed }
        let completed = tasks.filter(\.completed)
        return ordered(active, mode: mode) + ordered(completed, mode: mode)
    }

    static func siblings(_ task: GoogleTask, in tasks: [GoogleTask]) -> [GoogleTask] {
        siblingOrder(tasks.filter {
            $0.taskListID == task.taskListID && $0.parent == task.parent && !$0.completed && !$0.deleted
        })
    }

    static func previousForMove(_ task: GoogleTask, before target: GoogleTask, in tasks: [GoogleTask]) -> GoogleTask? {
        guard task.id != target.id, task.taskListID == target.taskListID, task.parent == target.parent,
              !task.completed, !target.completed, !task.deleted, !target.deleted else { return nil }
        let candidates = siblings(task, in: tasks).filter { $0.id != task.id }
        guard let index = candidates.firstIndex(where: { $0.id == target.id }), index > 0 else { return nil }
        return candidates[index - 1]
    }

    private static func siblingOrder(_ tasks: [GoogleTask]) -> [GoogleTask] {
        // Legacy caches have no positions: preserve their order rather than inventing one.
        guard tasks.allSatisfy({ !($0.position ?? "").isEmpty }) else { return tasks }
        return tasks.enumerated().sorted {
            if $0.element.position != $1.element.position { return $0.element.position! < $1.element.position! }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    private static func ordered(_ tasks: [GoogleTask], mode: TaskSortMode) -> [GoogleTask] {
        if mode == .manual { return treeOrder(tasks) }
        return tasks.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if mode == .date, a.due != b.due {
                if a.due == nil { return false }
                if b.due == nil { return true }
                return a.due! < b.due!
            }
            if mode == .title {
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedAscending }
            }
            if a.id != b.id { return a.id < b.id }
            if a.taskListID != b.taskListID { return a.taskListID < b.taskListID }
            return left.offset < right.offset
        }.map(\.element)
    }

    private static func treeOrder(_ tasks: [GoogleTask]) -> [GoogleTask] {
        var listIDs: [String] = []
        var seenLists = Set<String>()
        for task in tasks where seenLists.insert(task.taskListID).inserted { listIDs.append(task.taskListID) }
        let boards = Dictionary(grouping: tasks, by: \.taskListID)
        var result: [GoogleTask] = []
        for listID in listIDs {
            let board = boards[listID] ?? []
            let ids = Set(board.map(\.id))
            let children = Dictionary(grouping: board, by: \.parent).mapValues(siblingOrder)
            var visited = Set<String>()
            func walk(_ seeds: [GoogleTask]) {
                var stack = Array(seeds.reversed())
                while let task = stack.popLast() {
                    guard visited.insert(task.id).inserted else { continue }
                    result.append(task)
                    stack.append(contentsOf: (children[task.id] ?? []).reversed())
                }
            }
            walk(siblingOrder(board.filter { $0.parent == nil || !ids.contains($0.parent!) }))
            // Malformed/cyclic cached trees remain visible and terminate deterministically.
            walk(siblingOrder(board))
        }
        return result
    }
}

struct TaskWorkspacePreferences: Codable, Equatable {
    var sortModes: [String: TaskSortMode] = [:]
    var boardOrder: [String] = []

    init(sortModes: [String: TaskSortMode] = [:], boardOrder: [String] = []) {
        self.sortModes = sortModes
        self.boardOrder = boardOrder
    }
    private enum CodingKeys: String, CodingKey { case sortModes, boardOrder }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortModes = try container.decodeIfPresent([String: TaskSortMode].self, forKey: .sortModes) ?? [:]
        boardOrder = try container.decodeIfPresent([String].self, forKey: .boardOrder) ?? []
    }

    func sortMode(for boardID: String) -> TaskSortMode { sortModes[boardID] ?? .manual }
    mutating func setSortMode(_ mode: TaskSortMode, for boardID: String) { sortModes[boardID] = mode }

    func orderedBoards(_ lists: [TaskList]) -> [TaskList] {
        var byID: [String: TaskList] = [:]
        for list in lists { byID[list.id] = list }
        var seen = Set<String>()
        let saved = boardOrder.compactMap { id -> TaskList? in
            guard let list = byID[id], seen.insert(id).inserted else { return nil }
            return list
        }
        return saved + lists.filter { seen.insert($0.id).inserted }
    }

    @discardableResult
    mutating func moveBoard(_ boardID: String, toward targetID: String, in lists: [TaskList]) -> Bool {
        var ids = orderedBoards(lists).map(\.id)
        guard boardID != targetID, let source = ids.firstIndex(of: boardID), let target = ids.firstIndex(of: targetID) else { return false }
        ids.remove(at: source)
        ids.insert(boardID, at: target)
        boardOrder = ids
        return true
    }

    static func load(from defaults: UserDefaults = .standard, key: String) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(to defaults: UserDefaults = .standard, key: String) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}

struct TaskDateGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let tasks: [GoogleTask]
    var isOverdue = false
    var isToday = false
}

extension TaskOrdering {
    static func dateGroups(_ tasks: [GoogleTask], today: DateOnly) -> [TaskDateGroup] {
        let ordered = sorted(tasks.filter { !$0.deleted }, mode: .date)
        let active = ordered.filter { !$0.completed }
        var groups: [TaskDateGroup] = []
        let overdue = active.filter { $0.due.map { $0 < today } ?? false }
        if !overdue.isEmpty { groups.append(TaskDateGroup(id: "overdue", title: "Просроченные", tasks: overdue, isOverdue: true)) }
        let dated = active.filter { $0.due.map { $0 >= today } ?? false }
        let byDate = Dictionary(grouping: dated, by: { $0.due! })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMMM yyyy"
        for day in byDate.keys.sorted() {
            let title: String
            if day == today { title = "Сегодня" }
            else if day == today.adding(days: 1) { title = "Завтра" }
            else { title = day.startOfDay(in: formatter.timeZone).map(formatter.string(from:)) ?? day.description }
            groups.append(TaskDateGroup(id: "date:" + day.description, title: title, tasks: byDate[day] ?? [], isToday: day == today))
        }
        let undated = active.filter { $0.due == nil }
        if !undated.isEmpty { groups.append(TaskDateGroup(id: "undated", title: "Без срока", tasks: undated)) }
        let completed = ordered.filter(\.completed)
        if !completed.isEmpty { groups.append(TaskDateGroup(id: "completed", title: "Готово", tasks: completed)) }
        return groups
    }
}
