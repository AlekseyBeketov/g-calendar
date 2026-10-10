import Foundation
import CryptoKit
import UserNotifications

struct ReminderRequest: Equatable {
    let identifier: String
    let taskID: String
    let title: String
    let fireDate: Date
}

/// Once Google confirms a task, retries belong exclusively to the device-local stage.
struct TaskReminderSaveState {
    private(set) var verifiedTask: GoogleTask?
    var needsGoogleSave: Bool { verifiedTask == nil }

    mutating func accept(_ result: GWSMutationResult) -> Bool {
        guard case .taskVerified(let task) = result else { return false }
        verifiedTask = task
        return true
    }

    static func validationMessage(enabled: Bool, fireDate: Date, unchangedDate: Date? = nil,
                                  completed: Bool = false, now: Date = Date()) -> String? {
        enabled && !completed && fireDate != unchangedDate && fireDate <= now
            ? "Выберите будущее время локального напоминания." : nil
    }
}

enum NotificationAcceptance {
    /// Explicit test mode only. Never requests permission, reads cache or changes reminders.
    static func scheduleOneTest(using scheduler: ReminderScheduling, now: Date = Date()) async throws -> ReminderRequest {
        guard await scheduler.permission() == .authorized else { throw GWSFailure.forbiddenOperation }
        let identifier = "g-calendar.acceptance." + UUID().uuidString
        let request = ReminderRequest(identifier: identifier, taskID: identifier,
                                      title: "g-calendar: тест системного уведомления", fireDate: now.addingTimeInterval(3))
        try await scheduler.schedule(request)
        return request
    }
}

enum ReminderPermission: Equatable {
    case notDetermined
    case authorized
    case denied
    case unknown

    var statusIdentifier: String {
        switch self {
        case .notDetermined: return "not_determined"
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .unknown: return "unknown"
        }
    }
}

struct NotificationAuthorizationFailure: Error, Equatable {
    let domain: String
    let code: Int

    init(error: Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code)
    }

    init(domain: String, code: Int) {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let value = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = !value.isEmpty && value.count <= 80 && value.unicodeScalars.allSatisfy(allowed.contains)
            ? value
            : "unknown"
        self.code = code
    }
}

struct NotificationAuthorizationResult: Equatable {
    let status: ReminderPermission
    let requestFailure: NotificationAuthorizationFailure?

    init(status: ReminderPermission, requestFailure: NotificationAuthorizationFailure? = nil) {
        self.status = status
        self.requestFailure = requestFailure
    }

    var userMessage: String {
        if requestFailure != nil {
            let currentState: String
            switch status {
            case .notDetermined: currentState = "разрешение ещё не получено"
            case .authorized: currentState = "уведомления разрешены"
            case .denied: currentState = "уведомления отключены"
            case .unknown: currentState = "статус разрешения пока неизвестен"
            }
            return "Не удалось запросить разрешение. Текущее состояние: \(currentState). Проверьте настройки уведомлений macOS."
        }
        switch status {
        case .notDetermined:
            return "Разрешение на уведомления ещё не получено. Напоминание не запланировано."
        case .authorized:
            return "Уведомления разрешены."
        case .denied:
            return "Уведомления отключены в macOS. Разрешите их для g-calendar в системных настройках."
        case .unknown:
            return "macOS вернула неизвестный статус авторизации; напоминание не запланировано. Обновите статус позже."
        }
    }
}

enum NotificationAuthorization {
    static func requestAfterExplicitUserAction(using scheduler: ReminderScheduling) async -> NotificationAuthorizationResult {
        let currentStatus = await scheduler.permission()
        guard currentStatus == .notDetermined else {
            return NotificationAuthorizationResult(status: currentStatus)
        }

        var requestFailure: NotificationAuthorizationFailure?
        do {
            _ = try await scheduler.requestPermission()
        } catch {
            requestFailure = NotificationAuthorizationFailure(error: error)
        }

        // The Bool returned by requestAuthorization is not the source of truth:
        // false can mean denied or still undetermined. Read back system settings.
        return NotificationAuthorizationResult(status: await scheduler.permission(), requestFailure: requestFailure)
    }
}

struct EventReminderRequest: Equatable {
    let identifier: String
    let identity: CalendarEventIdentity
    let title: String
    let fireDate: Date
}

struct NotificationRuntimeStatus: Equatable {
    let authorization: String
    let pendingCount: Int
    let deliveredCount: Int
    let alertSetting: String
    let soundSetting: String
    let foregroundDelegateReady: Bool
    var alertStyle: String = "not_queried"

    var userFacingLines: [String] {
        let access: String
        switch authorization {
        case "authorized": access = "Уведомления разрешены."
        case "denied": access = "Уведомления отключены. Разрешите их для g-calendar в настройках macOS."
        case "not_determined": access = "Разрешение на уведомления ещё не запрошено."
        case "provisional": access = "Разрешены тихие уведомления."
        case "ephemeral": access = "Уведомления разрешены временно."
        default: access = "Статус разрешения неизвестен. Обновите статус позже."
        }
        func setting(_ value: String) -> String {
            switch value {
            case "enabled": return "включён"
            case "disabled": return "выключен"
            case "not_supported": return "недоступен"
            case "not_queried": return "ещё не проверен"
            default: return "неизвестен"
            }
        }
        return [access,
                "Показ уведомлений: \(setting(alertSetting)) · звук: \(setting(soundSetting)).",
                alertStyleMessage,
                "Ожидают доставки: \(pendingCount) · в Центре уведомлений: \(deliveredCount)."]
    }

    var alertStyleMessage: String {
        switch alertStyle {
        case "alert": return "Стиль: предупреждения — остаются до закрытия."
        case "banner": return "Стиль: баннеры — закрываются автоматически."
        case "none": return "Стиль: без всплывающих уведомлений."
        case "not_queried": return "Стиль уведомлений ещё не проверен."
        default: return "Стиль уведомлений неизвестен. Обновите статус позже."
        }
    }

    var safeSummary: String {
        "authorization=\(authorization) alert_setting=\(alertSetting) alert_style=\(alertStyle) sound_setting=\(soundSetting) pending_count=\(pendingCount) delivered_count=\(deliveredCount) foreground_delegate_ready=\(foregroundDelegateReady)"
    }
}

protocol NotificationStatusProviding {
    func notificationStatus() async -> NotificationRuntimeStatus
}

protocol ReminderScheduling {
    func permission() async -> ReminderPermission
    func requestPermission() async throws -> Bool
    func schedule(_ reminder: ReminderRequest) async throws
    func schedule(_ reminder: EventReminderRequest) async throws
    func cancel(identifier: String) async
}

struct ReminderIdentity {
    static func identifier(taskID: String) -> String {
        let digest = SHA256.hash(data: Data(taskID.utf8))
        return "g-calendar.task." + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

struct EventReminderIdentity {
    static func identifier(for identity: CalendarEventIdentity) -> String {
        let digest = SHA256.hash(data: Data(identity.stableKey.utf8))
        return "g-calendar.event." + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

struct ReminderCoordinator {
    let store: LocalMetadataStoring
    let scheduler: ReminderScheduling
    let defaults: UserDefaults
    let enabledKey: String

    init(store: LocalMetadataStoring,
         scheduler: ReminderScheduling,
         defaults: UserDefaults = .standard,
         enabledKey: String = "localRemindersEnabled") {
        self.store = store
        self.scheduler = scheduler
        self.defaults = defaults
        self.enabledKey = enabledKey
    }

    /// Call only from a deliberate user action (e.g. the Enable local reminders button).
    func enableAfterExplicitUserAction() async -> NotificationAuthorizationResult {
        let result = await NotificationAuthorization.requestAfterExplicitUserAction(using: scheduler)
        if result.status == .authorized { defaults.set(true, forKey: enabledKey) }
        else { defaults.set(false, forKey: enabledKey) }
        return result
    }

    func saveReminder(task: GoogleTask, title: String, at date: Date?, explicitEnableAction: Bool = false, now: Date = Date()) async throws -> NotificationAuthorizationResult {
        let authorization = explicitEnableAction
            ? await enableAfterExplicitUserAction()
            : NotificationAuthorizationResult(status: await scheduler.permission())
        let old = store.metadata(for: task.id)
        try store.set(LocalTaskMetadata(reminderAt: date, favorite: old.favorite), for: task.id)
        let identifier = ReminderIdentity.identifier(taskID: task.id)
        await scheduler.cancel(identifier: identifier)
        guard let date, !task.completed, !task.deleted, date > now, defaults.bool(forKey: enabledKey), authorization.status == .authorized else {
            return authorization
        }
        try await scheduler.schedule(ReminderRequest(identifier: identifier, taskID: task.id, title: title, fireDate: date))
        return authorization
    }

    func complete(taskID: String) async {
        await scheduler.cancel(identifier: ReminderIdentity.identifier(taskID: taskID))
    }

    func delete(taskID: String) async throws {
        await scheduler.cancel(identifier: ReminderIdentity.identifier(taskID: taskID))
        try store.remove(taskID: taskID)
    }

    /// Compatibility for the explicit notification-enable UI, whose snapshot may be cached.
    /// This path only schedules/cancels reminders for tasks present in that cache; it never prunes
    /// metadata for absent IDs. Only GWSCompletedFullSync may trigger deletion reconciliation.
    func reconcile(tasks: [GoogleTask], now: Date = Date()) async {
        let reminderTaskIDs = store.reminderTaskIDs()
        guard !reminderTaskIDs.isEmpty else { return }
        let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let permission = await scheduler.permission()
        let maySchedule = defaults.bool(forKey: enabledKey) && permission == .authorized

        for taskID in reminderTaskIDs {
            guard let task = tasksByID[taskID] else { continue }
            let identifier = ReminderIdentity.identifier(taskID: taskID)
            let date = store.metadata(for: taskID).reminderAt
            guard maySchedule, !task.completed, !task.deleted, let date, date > now else {
                await scheduler.cancel(identifier: identifier)
                continue
            }
            do {
                await scheduler.cancel(identifier: identifier)
                try await scheduler.schedule(ReminderRequest(identifier: identifier, taskID: taskID, title: task.title, fireDate: date))
            } catch {
                // Do not log task content or identifiers.
            }
        }
    }

    func reconcile(afterSuccessfulFullSync fullSync: GWSCompletedFullSync, now: Date = Date()) async throws {
        try await reconcile(completedTasks: fullSync.snapshot.tasks, now: now)
    }

    func reconcile(afterSuccessfulTasksSync tasksSync: GWSCompletedTasksSync, now: Date = Date()) async throws {
        try await reconcile(completedTasks: tasksSync.snapshot.tasks, now: now)
    }

    private func reconcile(completedTasks: [GoogleTask], now: Date) async throws {
        let reminderTaskIDs = store.reminderTaskIDs()
        guard !reminderTaskIDs.isEmpty else { return }
        let tasksByID = Dictionary(completedTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let permission = await scheduler.permission()
        let maySchedule = defaults.bool(forKey: enabledKey) && permission == .authorized

        for taskID in reminderTaskIDs {
            let identifier = ReminderIdentity.identifier(taskID: taskID)
            guard let task = tasksByID[taskID] else {
                await scheduler.cancel(identifier: identifier)
                try store.remove(taskID: taskID)
                continue
            }
            if task.deleted {
                await scheduler.cancel(identifier: identifier)
                try store.remove(taskID: taskID)
                continue
            }
            let date = store.metadata(for: taskID).reminderAt
            guard maySchedule, !task.completed, let date, date > now else {
                await scheduler.cancel(identifier: identifier)
                continue
            }
            do {
                await scheduler.cancel(identifier: identifier)
                try await scheduler.schedule(ReminderRequest(identifier: identifier, taskID: taskID, title: task.title, fireDate: date))
            } catch {
                // Do not log task content or identifiers; the UI can report a generic scheduler failure.
            }
        }
    }
}

private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

final class UserNotificationScheduler: ReminderScheduling, NotificationStatusProviding {
    private let center: UNUserNotificationCenter
    private let foregroundPresenter: ForegroundNotificationPresenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        let presenter = ForegroundNotificationPresenter()
        foregroundPresenter = presenter
        center.delegate = presenter
    }

    func permission() async -> ReminderPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ reminder: ReminderRequest) async throws {
        try await add(identifier: reminder.identifier, body: reminder.title, fireDate: reminder.fireDate)
    }

    func schedule(_ reminder: EventReminderRequest) async throws {
        try await add(identifier: reminder.identifier, body: reminder.title, fireDate: reminder.fireDate)
    }

    private func add(identifier: String, body: String, fireDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Локальное напоминание"
        content.body = body
        content.sound = .default
        let components = ReminderTriggerFactory.dateComponents(for: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancel(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func wasDelivered(identifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.contains { $0.request.identifier == identifier })
            }
        }
    }

    func notificationStatus() async -> NotificationRuntimeStatus {
        let settings = await center.notificationSettings()
        let authorization: String
        switch settings.authorizationStatus {
        case .notDetermined: authorization = "not_determined"
        case .denied: authorization = "denied"
        case .authorized: authorization = "authorized"
        case .provisional: authorization = "provisional"
        case .ephemeral: authorization = "ephemeral"
        @unknown default: authorization = "unknown"
        }
        let pending = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0.count) }
        }
        let delivered = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { continuation.resume(returning: $0.count) }
        }
        let alertSetting = Self.settingIdentifier(settings.alertSetting)
        let soundSetting = Self.settingIdentifier(settings.soundSetting)
        return NotificationRuntimeStatus(authorization: authorization,
                                         pendingCount: pending,
                                         deliveredCount: delivered,
                                         alertSetting: alertSetting,
                                         soundSetting: soundSetting,
                                         foregroundDelegateReady: center.delegate === foregroundPresenter,
                                         alertStyle: Self.styleIdentifier(settings.alertStyle))
    }

    private static func styleIdentifier(_ style: UNAlertStyle) -> String {
        switch style {
        case .none: return "none"
        case .banner: return "banner"
        case .alert: return "alert"
        @unknown default: return "unknown"
        }
    }

    private static func settingIdentifier(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "not_supported"
        @unknown default: return "unknown"
        }
    }
}

final class NoopReminderScheduler: ReminderScheduling, NotificationStatusProviding {
    func permission() async -> ReminderPermission { .notDetermined }
    func requestPermission() async throws -> Bool { throw GWSFailure.forbiddenOperation }
    func schedule(_ reminder: ReminderRequest) async throws { throw GWSFailure.forbiddenOperation }
    func schedule(_ reminder: EventReminderRequest) async throws { throw GWSFailure.forbiddenOperation }
    func cancel(identifier: String) async { }
    func notificationStatus() async -> NotificationRuntimeStatus {
        NotificationRuntimeStatus(authorization: "not_queried", pendingCount: 0, deliveredCount: 0,
                                  alertSetting: "not_queried", soundSetting: "not_queried",
                                  foregroundDelegateReady: false)
    }
}

protocol ExactCalendarEventReading: Sendable {
    func event(identity: CalendarEventIdentity) throws -> CalendarEvent?
}

struct EventReminderCoordinator {
    let store: LocalEventReminderStoring
    let scheduler: ReminderScheduling

    func remove(identity: CalendarEventIdentity) async throws {
        try store.set(nil, for: identity)
        await scheduler.cancel(identifier: EventReminderIdentity.identifier(for: identity))
    }

    func save(event: CalendarEvent, at fireDate: Date?, explicitEnableAction: Bool = false,
              now: Date = Date()) async throws -> NotificationAuthorizationResult {
        guard !event.isAllDay, !event.recurring, event.start.instant != nil else { throw GWSFailure.forbiddenOperation }
        if let fireDate, fireDate <= now { throw GWSFailure.invalidInput("event_reminder_time") }
        let authorization = explicitEnableAction
            ? await NotificationAuthorization.requestAfterExplicitUserAction(using: scheduler)
            : NotificationAuthorizationResult(status: await scheduler.permission())
        let identity = event.identity
        let identifier = EventReminderIdentity.identifier(for: identity)
        if let fireDate {
            try store.set(LocalEventReminderRecord(identity: identity, fireDate: fireDate), for: identity)
            await scheduler.cancel(identifier: identifier)
            if authorization.status == .authorized {
                try await scheduler.schedule(EventReminderRequest(identifier: identifier, identity: identity,
                                                                   title: event.title, fireDate: fireDate))
            }
        } else {
            try store.set(nil, for: identity)
            await scheduler.cancel(identifier: identifier)
        }
        return authorization
    }

    func reconcile(using reader: ExactCalendarEventReading, now: Date = Date()) async {
        let records = store.all()
        guard !records.isEmpty else { return }
        let permission = await scheduler.permission()
        for record in records {
            do {
                guard let event = try reader.event(identity: record.identity) else {
                    await scheduler.cancel(identifier: EventReminderIdentity.identifier(for: record.identity))
                    try store.set(nil, for: record.identity)
                    continue
                }
                let identifier = EventReminderIdentity.identifier(for: record.identity)
                if event.status == "cancelled" {
                    await scheduler.cancel(identifier: identifier)
                    try store.set(nil, for: record.identity)
                    continue
                }
                guard !event.isAllDay, !event.recurring, record.fireDate > now, permission == .authorized else {
                    await scheduler.cancel(identifier: identifier)
                    continue
                }
                await scheduler.cancel(identifier: identifier)
                try await scheduler.schedule(EventReminderRequest(identifier: identifier, identity: record.identity,
                                                                   title: event.title, fireDate: record.fireDate))
            } catch {
                // Exact-read or scheduler failures preserve local metadata; diagnostics omit event identity/content.
            }
        }
    }
}

enum ReminderTriggerFactory {
    static func dateComponents(for date: Date, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}
