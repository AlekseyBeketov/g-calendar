import AppKit
import Combine
import Sparkle

@MainActor
final class ApplicationUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var automaticUpdatesEnabled: Bool
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var errorMessage: String?
    let isAvailable: Bool
    var canInstallUpdate: () -> Bool = { false }
    private let preferences: StartupPreferences
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var preferenceObservation: AnyCancellable?
    private var started = false
    private var postponedInstall: (() -> Void)?
    private var postponeTimer: Timer?

    init(mode: AppLaunchMode, defaults: UserDefaults) {
        preferences = StartupPreferences(defaults: defaults)
        automaticUpdatesEnabled = preferences.automaticUpdates
        isAvailable = mode == .normal
        super.init()
        // Synthetic sessions never instantiate Sparkle or start its helpers/network.
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.sendsSystemProfile = false
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
        preferenceObservation = controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .combineLatest(controller.updater.publisher(for: \.automaticallyDownloadsUpdates))
            .dropFirst()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] checks, downloads in
                guard let self, self.started else { return }
                self.automaticUpdatesEnabled = checks && downloads
                self.preferences.saveAutomaticUpdates(self.automaticUpdatesEnabled)
            }
    }

    var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Версия \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    func setAutomaticUpdates(_ enabled: Bool) {
        guard isAvailable else { return }
        automaticUpdatesEnabled = enabled
        preferences.saveAutomaticUpdates(enabled)
        controller?.updater.automaticallyChecksForUpdates = enabled
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func startIfNeeded() {
        guard isAvailable, !started, let controller else { return }
        setAutomaticUpdates(automaticUpdatesEnabled)
        controller.startUpdater()
        started = true
    }

    func checkForUpdates() {
        guard isAvailable, canInstallUpdate() else { return }
        errorMessage = nil
        startIfNeeded()
        guard controller?.updater.canCheckForUpdates == true else { return }
        controller?.checkForUpdates(nil)
    }

    func refreshPreference() {
        guard started, let updater = controller?.updater else { return }
        automaticUpdatesEnabled = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        preferences.saveAutomaticUpdates(automaticUpdatesEnabled)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard canInstallUpdate() else {
            throw NSError(domain: "g-calendar.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Дождитесь завершения текущей операции и повторите проверку обновлений."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !canInstallUpdate() else { return false }
        postponedInstall = installHandler
        postponeTimer?.invalidate()
        postponeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.resumeInstallationWhenSafe() }
        }
        return true
    }

    private func resumeInstallationWhenSafe() {
        guard canInstallUpdate(), let handler = postponedInstall else { return }
        postponeTimer?.invalidate(); postponeTimer = nil; postponedInstall = nil
        handler()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}
