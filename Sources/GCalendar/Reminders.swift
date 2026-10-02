import Foundation
import CryptoKit
import UserNotifications

struct ReminderRequest: Equatable {
    let identifier: String
    let taskID: String
    let title: String
    let fireDate: Date
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
        if let requestFailure {
            return "Системный запрос завершился ошибкой (\(requestFailure.domain), код \(requestFailure.code)); фактический статус macOS: \(status.statusIdentifier)."
        }
        switch status {
        case .notDetermined:
            return "Статус macOS — not_determined; уведомления не запланированы."
        case .authorized:
            return "Статус macOS — authorized."
        case .denied:
            return "Статус macOS — denied; приложение не делает вывод, что пользователь нажал «Не разрешать». Проверьте системные настройки уведомлений."
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

    var safeSummary: String {
        "authorization=\(authorization) alert_setting=\(alertSetting) sound_setting=\(soundSetting) pending_count=\(pendingCount) delivered_count=\(deliveredCount) foreground_delegate_ready=\(foregroundDelegateReady)"
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
        let reminderTaskIDs = store.reminderTaskIDs()
        guard !reminderTaskIDs.isEmpty else { return }
        let tasksByID = Dictionary(fullSync.snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
                                         foregroundDelegateReady: center.delegate === foregroundPresenter)
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
