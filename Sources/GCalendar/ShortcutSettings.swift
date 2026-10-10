import Foundation

enum WorkspaceShortcutAction: String, Codable, CaseIterable, Identifiable {
    case search, today, newItem, refresh, calendar, tasks, previousPeriod, nextPeriod, toggleSidebar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .search: return "Поиск"
        case .today: return "Сегодня"
        case .newItem: return "Новое событие или задача"
        case .refresh: return "Синхронизировать"
        case .calendar: return "Календарь"
        case .tasks: return "Задачи"
        case .previousPeriod: return "Предыдущий период"
        case .nextPeriod: return "Следующий период"
        case .toggleSidebar: return "Свернуть / развернуть боковое меню"
        }
    }
    var defaultBinding: WorkspaceShortcutBinding {
        let key: String
        switch self {
        case .search: key = "f"
        case .today: key = "t"
        case .newItem: key = "n"
        case .refresh: key = "r"
        case .calendar: key = "1"
        case .tasks: key = "2"
        case .previousPeriod: key = "["
        case .nextPeriod: key = "]"
        case .toggleSidebar: key = "b"
        }
        return WorkspaceShortcutBinding(key: key)
    }
}

struct WorkspaceShortcutBinding: Codable, Equatable, Hashable {
    var key: String
    var command = true
    var option = false
    var control = false
    var shift = false

    var normalized: Self {
        var value = self
        value.key = key.lowercased()
        return value
    }
}

struct WorkspaceShortcutSettings: Equatable {
    static let storageKey = "workspaceShortcuts.v1"
    private var bindings: [WorkspaceShortcutAction: WorkspaceShortcutBinding] = [:]

    static func == (lhs: Self, rhs: Self) -> Bool {
        WorkspaceShortcutAction.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }

    subscript(action: WorkspaceShortcutAction) -> WorkspaceShortcutBinding {
        bindings[action] ?? action.defaultBinding
    }

    func validationMessage(_ proposed: WorkspaceShortcutBinding, for action: WorkspaceShortcutAction) -> String? {
        let value = proposed.normalized
        guard value.key.utf8.count == 1, let byte = value.key.utf8.first,
              (33...126).contains(byte) else { return "Введите одну латинскую букву, цифру или знак." }
        guard value.command || value.option || value.control else { return "Добавьте ⌘, ⌥ или ⌃, чтобы сочетание не мешало вводу текста." }
        // Native application and text-editing commands remain available.
        if value.command && !value.option && !value.control &&
            (["q", "h", "m", "w", ",", "a", "c", "v", "x", "z"].contains(value.key)) {
            return "Это сочетание занято стандартной командой macOS."
        }
        if let conflict = WorkspaceShortcutAction.allCases.first(where: { $0 != action && self[$0] == value }) {
            return "Сочетание уже используется: \(conflict.title)."
        }
        return nil
    }

    @discardableResult
    mutating func update(_ value: WorkspaceShortcutBinding, for action: WorkspaceShortcutAction) -> String? {
        if let problem = validationMessage(value, for: action) { return problem }
        bindings[action] = value.normalized
        return nil
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: WorkspaceShortcutBinding].self, from: data) else { return Self() }
        var result = Self()
        // Validate the complete map, including swaps, rather than introducing order-dependent conflicts.
        result.bindings = Dictionary(uniqueKeysWithValues: WorkspaceShortcutAction.allCases.map {
            ($0, (stored[$0.rawValue] ?? $0.defaultBinding).normalized)
        })
        guard WorkspaceShortcutAction.allCases.allSatisfy({ result.validationMessage(result[$0], for: $0) == nil }) else { return Self() }
        return result
    }

    func save(to defaults: UserDefaults) {
        let values = Dictionary(uniqueKeysWithValues: WorkspaceShortcutAction.allCases.map { ($0.rawValue, self[$0]) })
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: Self.storageKey) }
    }
}
