import Foundation

extension InvariantTests {
    static func testStartupPreferences() throws {
        let suite = "g-calendar.startup.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = StartupPreferences(defaults: defaults)
        try check(!preferences.completed && preferences.automaticUpdates, "initial setup offers updates without completing consent")
        try check(!StartupPreferences.shouldStartUpdater(mode: .normal, completed: preferences.completed), "updater cannot start before the final setup step")
        preferences.saveAutomaticUpdates(false)
        preferences.complete()
        let restored = StartupPreferences(defaults: defaults)
        try check(restored.completed && !restored.automaticUpdates, "completed setup and declined updates survive relaunch")
        try check(StartupPreferences.shouldStartUpdater(mode: .normal, completed: restored.completed), "manual updater is available after completed setup even when automatic updates are declined")
        for mode in [AppLaunchMode.demo, .notificationTest, .notificationStatus, .syntheticAcceptance] {
            try check(!StartupPreferences.shouldStartUpdater(mode: mode, completed: true), "synthetic modes cannot start Sparkle")
        }
        restored.saveAutomaticUpdates(true)
        try check(StartupPreferences(defaults: defaults).automaticUpdates, "the user can enable updates later from Settings")
    }
}
