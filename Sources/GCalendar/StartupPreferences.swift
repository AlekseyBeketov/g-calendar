import Foundation

struct StartupPreferences {
    static let completionKey = "initialPreferencesCompleted.v1"
    static let updatesKey = "automaticAppUpdatesEnabled"
    let defaults: UserDefaults

    var completed: Bool { defaults.bool(forKey: Self.completionKey) }
    var automaticUpdates: Bool { defaults.object(forKey: Self.updatesKey) as? Bool ?? true }

    func saveAutomaticUpdates(_ enabled: Bool) { defaults.set(enabled, forKey: Self.updatesKey) }
    func complete() { defaults.set(true, forKey: Self.completionKey) }

    static func shouldStartUpdater(mode: AppLaunchMode, completed: Bool) -> Bool {
        mode == .normal && completed
    }
}
