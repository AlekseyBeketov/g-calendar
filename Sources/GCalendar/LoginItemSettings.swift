import Combine
import ServiceManagement

@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
private struct SystemLoginItemService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var isUpdating = false
    @Published private(set) var isAvailable = false
    @Published private(set) var errorMessage: String?
    private let service: LoginItemServicing

    init(service: LoginItemServicing? = nil) { self.service = service ?? SystemLoginItemService() }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var statusMessage: String {
        guard isAvailable else { return "Автозапуск отключён в тестовом режиме." }
        switch status {
        case .enabled: return "Приложение будет запускаться при входе в систему."
        case .notRegistered: return "Запуск при входе выключен."
        case .requiresApproval: return "Разрешите запуск g-calendar в системных настройках → Основные → Объекты входа."
        case .notFound: return "macOS не нашла приложение. Установите и запустите g-calendar из папки Applications."
        @unknown default: return "Состояние автозапуска неизвестно. Обновите статус."
        }
    }

    func refresh(isNormalMode: Bool) {
        isAvailable = isNormalMode
        if isNormalMode { status = service.status }
    }

    func setEnabled(_ enabled: Bool) async {
        guard isAvailable, !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { status = service.status; isUpdating = false }
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status != .notRegistered { try await service.unregister() }
        } catch {
            errorMessage = "Не удалось изменить автозапуск: " + error.localizedDescription
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
