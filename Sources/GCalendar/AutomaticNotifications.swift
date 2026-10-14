import Foundation
import CryptoKit
import UserNotifications

struct AutomaticNotificationRequest: Codable, Equatable, Sendable {
    let identifier: String
    let namespace: String
    let calendarID: String
    let resourceID: String
    let title: String
    let subtitle: String?
    let body: String
    let fireDate: Date
}

struct AutomaticNotificationPlan {
    var requests: [AutomaticNotificationRequest] = []
    var protectedEventIDs = Set<CalendarEventIdentity>()
}

enum AutomaticNotificationPlanner {
    static let horizon: TimeInterval = 30 * 86400
    static let maximumOffset: TimeInterval = 40320 * 60
    static let prefix = "g-calendar.automatic."

    static func plan(calendar: CalendarInfo, events: [CalendarEvent], namespace: String, now: Date,
                     locale: Locale = .current) -> AutomaticNotificationPlan {
        var result = AutomaticNotificationPlan()
        let horizonEnd = now.addingTimeInterval(horizon)
        for event in events where event.calendarID == calendar.id {
            guard !event.isAllDay, event.status != "cancelled", event.declinedByCurrentUser != true,
                  let start = event.start.instant else { continue }
            let identity = CalendarEventIdentity(calendarID: event.calendarID, eventID: event.id)
            guard let settings = event.reminders else {
                result.protectedEventIDs.insert(identity); continue
            }
            let offsets: [GooglePopupReminder]?
            offsets = settings.useDefault ? calendar.defaultReminders : settings.overrides
            guard let offsets else { result.protectedEventIDs.insert(identity); continue }
            for offset in Set(offsets.filter { $0.method == "popup" && (0...40320).contains($0.minutes) }.map(\.minutes)).sorted() {
                let fireDate = start.addingTimeInterval(-Double(offset) * 60)
                guard fireDate > now, fireDate <= horizonEnd else { continue }
                let key = namespace + "\u{0}" + identity.stableKey + "\u{0}" + String(offset)
                let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = location.flatMap { $0.isEmpty ? nil : $0 } ?? ""
                result.requests.append(AutomaticNotificationRequest(identifier: prefix + digest, namespace: namespace,
                    calendarID: event.calendarID, resourceID: event.id, title: event.title,
                    subtitle: subtitle(for: event, calendar: calendar, locale: locale), body: body, fireDate: fireDate))
            }
        }
        return result
    }

    static func subtitle(for event: CalendarEvent, calendar: CalendarInfo, locale: Locale = .current) -> String? {
        guard let start = event.start.instant, let end = event.end.instant else { return nil }
        let timeZone = event.start.timeZoneID.flatMap(TimeZone.init(identifier:))
            ?? calendar.timeZoneID.flatMap(TimeZone.init(identifier:))
            ?? .current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return "\(dateFormatter.string(from: start)), \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
}

struct AutomaticNotificationRead {
    let calendars: [CalendarInfo]
    /// A dictionary entry exists only after every page for that calendar succeeded.
    let events: [String: [CalendarEvent]]
    let failedCalendarIDs: Set<String>
}

protocol AutomaticNotificationReading: Sendable {
    func read(now: Date) async throws -> AutomaticNotificationRead
}

struct EmptyAutomaticNotificationReader: AutomaticNotificationReading {
    func read(now: Date) async throws -> AutomaticNotificationRead {
        AutomaticNotificationRead(calendars: [], events: [:], failedCalendarIDs: [])
    }
}

struct GoogleAutomaticNotificationReader: AutomaticNotificationReading {
    let reader: GWSReadClient

    func read(now: Date) async throws -> AutomaticNotificationRead {
        try await Task.detached(priority: .utility) { try readSynchronously(now: now) }.value
    }

    private func readSynchronously(now: Date) throws -> AutomaticNotificationRead {
            let calendars = try reader.calendars()
            let range = try DateRange(start: now.addingTimeInterval(-86400),
                endExclusive: now.addingTimeInterval(AutomaticNotificationPlanner.horizon + AutomaticNotificationPlanner.maximumOffset + 1))
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 4
            let results = AutomaticCalendarReadResults()
            for calendar in calendars {
                queue.addOperation {
                    results.install(calendarID: calendar.id, result: Result { try reader.events(calendarID: calendar.id, range: range) })
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            return results.snapshot(calendars: calendars)
    }
}

private final class AutomaticCalendarReadResults: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String: [CalendarEvent]] = [:]
    private var failed = Set<String>()
    func install(calendarID: String, result: Result<[CalendarEvent], Error>) {
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .success(let values): events[calendarID] = values
        case .failure: failed.insert(calendarID)
        }
    }
    func snapshot(calendars: [CalendarInfo]) -> AutomaticNotificationRead {
        lock.lock(); defer { lock.unlock() }
        return AutomaticNotificationRead(calendars: calendars, events: events, failedCalendarIDs: failed)
    }
}

protocol AutomaticNotificationScheduling: Sendable {
    func automaticPermission() async -> ReminderPermission
    func automaticPending() async -> [AutomaticNotificationRequest]
    func addAutomatic(_ request: AutomaticNotificationRequest) async throws
    func cancelAutomaticPending(identifiers: [String]) async
    func cancelLegacyPending(namespace: String) async
    func cancelAllAutomaticPending(namespace: String) async
}

extension AutomaticNotificationScheduling {
    func cancelAllAutomaticPending(namespace: String) async {
        let pending = await automaticPending()
        await cancelAutomaticPending(identifiers: pending.filter { $0.namespace == namespace }.map(\.identifier))
    }
}

enum AutomaticNotificationOwnership {
    static func owns(identifier: String, userInfo: [AnyHashable: Any], namespace: String) -> Bool {
        identifier.hasPrefix(AutomaticNotificationPlanner.prefix) && userInfo["workspaceContext"] as? String == namespace
    }
}

struct AutomaticNotificationStatus: Equatable {
    var scheduledCount = 0
    var failedCalendarCount = 0
    var problem: String? = nil
    var lastSuccessfulRead: Date? = nil
}

/// All automatic writes are serialized; a newer refresh invalidates the current
/// read before it can apply a stale schedule. Google reads never mutate Google.
actor AutomaticNotificationCoordinator {
    private let namespace: String
    private let scheduler: AutomaticNotificationScheduling
    private let legacyArchive: (@Sendable () throws -> Void)?
    private var working = false
    private var queued: (reader: AutomaticNotificationReading, enabled: Bool, now: Date)?
    private var revision = 0
    private var status = AutomaticNotificationStatus()
    private var pendingConfirmedDeletions = Set<CalendarEventIdentity>()
    private(set) var stopped = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    init(namespace: String, scheduler: AutomaticNotificationScheduling, legacyArchive: (@Sendable () throws -> Void)? = nil) {
        self.namespace = namespace; self.scheduler = scheduler; self.legacyArchive = legacyArchive
    }

    func cancelConfirmedEvent(identity: CalendarEventIdentity) async {
        revision += 1
        pendingConfirmedDeletions.insert(identity)
        guard !working else { return }
        working = true
        await finishWork()
    }

    func invalidateRead() { revision += 1 }

    func shutdown() async {
        stopped = true; revision += 1; queued = nil
        if working { await withCheckedContinuation { shutdownWaiters.append($0) } }
        await scheduler.cancelAllAutomaticPending(namespace: namespace)
    }

    private func drainConfirmedDeletions() async {
        while !pendingConfirmedDeletions.isEmpty {
            let identities = pendingConfirmedDeletions
            pendingConfirmedDeletions.removeAll()
            let pending = await scheduler.automaticPending()
            await scheduler.cancelAutomaticPending(identifiers: pending.filter {
                $0.namespace == namespace && identities.contains(CalendarEventIdentity(calendarID: $0.calendarID, eventID: $0.resourceID))
            }.map(\.identifier))
        }
    }

    private func completeShutdownWaiters() {
        let waiters = shutdownWaiters; shutdownWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func finishWork() async {
        await drainConfirmedDeletions()
        working = false
        completeShutdownWaiters()
        if let next = queued, !stopped {
            queued = nil
            _ = await refresh(reader: next.reader, enabled: next.enabled, now: next.now)
        }
    }

    func refresh(reader: AutomaticNotificationReading, enabled: Bool, now: Date = Date()) async -> AutomaticNotificationStatus {
        guard !stopped else { return status }
        revision += 1
        queued = (reader, enabled, now)
        guard !working else { return status }
        working = true
        while let input = queued {
            queued = nil
            let currentRevision = revision
            do {
                let permission = await scheduler.automaticPermission()
                guard currentRevision == revision else { continue }
                if !input.enabled {
                    try legacyArchive?()
                    guard currentRevision == revision else { continue }
                    await scheduler.cancelAllAutomaticPending(namespace: namespace)
                    await scheduler.cancelLegacyPending(namespace: namespace)
                    status = AutomaticNotificationStatus(problem: "Автоматические уведомления выключены.")
                    continue
                }
                guard permission == .authorized else {
                    status.problem = permission == .denied
                        ? "Разрешите уведомления g-calendar в настройках macOS."
                        : "Включите уведомления один раз в настройках g-calendar."
                    continue
                }
                let read = try await input.reader.read(now: input.now)
                guard currentRevision == revision else { continue }
                let pending = await scheduler.automaticPending()
                guard currentRevision == revision else { continue }
                var desired: [String: AutomaticNotificationRequest] = [:]
                var protected = Set<CalendarEventIdentity>()
                for calendar in read.calendars {
                    guard let events = read.events[calendar.id] else { continue }
                    let plan = AutomaticNotificationPlanner.plan(calendar: calendar, events: events, namespace: namespace, now: input.now)
                    for request in plan.requests { desired[request.identifier] = request }
                    protected.formUnion(plan.protectedEventIDs)
                }
                let previous = Dictionary(pending.filter { $0.namespace == namespace }.map { ($0.identifier, $0) }, uniquingKeysWith: { _, latest in latest })
                for request in desired.values.sorted(by: { $0.fireDate < $1.fireDate }) where previous[request.identifier] != request {
                    guard currentRevision == revision else { break }
                    try await scheduler.addAutomatic(request)
                }
                guard currentRevision == revision else { continue }
                let catalogue = Set(read.calendars.map(\.id))
                let horizonEnd = input.now.addingTimeInterval(AutomaticNotificationPlanner.horizon)
                let obsolete = pending.filter { request in
                    guard request.namespace == namespace, desired[request.identifier] == nil else { return false }
                    if !catalogue.contains(request.calendarID) { return true }
                    guard read.events[request.calendarID] != nil,
                          !protected.contains(CalendarEventIdentity(calendarID: request.calendarID, eventID: request.resourceID)) else { return false }
                    return request.fireDate <= horizonEnd
                }
                try legacyArchive?()
                guard currentRevision == revision else { continue }
                await scheduler.cancelAutomaticPending(identifiers: obsolete.map(\.identifier))
                // Retire manual scheduling only after a fully successful collection
                // and successful installation; metadata is archived, never sent Google.
                if read.failedCalendarIDs.isEmpty && protected.isEmpty {
                    await scheduler.cancelLegacyPending(namespace: namespace)
                }
                let remaining = await scheduler.automaticPending()
                status = AutomaticNotificationStatus(scheduledCount: remaining.filter { $0.namespace == namespace }.count,
                    failedCalendarCount: read.failedCalendarIDs.count,
                    problem: read.failedCalendarIDs.isEmpty && protected.isEmpty ? nil : "Часть данных недоступна. Предыдущее расписание сохранено.",
                    lastSuccessfulRead: input.now)
            } catch {
                status.problem = "Не удалось обновить расписание уведомлений. Повторим при следующей синхронизации."
            }
        }
        await finishWork()
        return status
    }
}

enum AutomaticReminderMigration {
    static func archive(directory: URL) throws {
        let manager = FileManager.default
        let archive = directory.appendingPathComponent("legacy-reminders-archive", isDirectory: true)
        for name in ["local-task-metadata.json", "local-event-reminders.json"] {
            let source = directory.appendingPathComponent(name)
            let target = archive.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: target.path) else { continue }
            try manager.createDirectory(at: archive, withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: target)
        }
    }
}

extension UserNotificationScheduler: AutomaticNotificationScheduling {
    func automaticPermission() async -> ReminderPermission { await permission() }

    func automaticPending() async -> [AutomaticNotificationRequest] {
        await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(AutomaticNotificationPlanner.prefix),
                  let data = request.content.userInfo["automaticRequest"] as? Data,
                  let decoded = try? JSONDecoder().decode(AutomaticNotificationRequest.self, from: data),
                  decoded.identifier == request.identifier else { return nil }
            return decoded
        }
    }

    func addAutomatic(_ request: AutomaticNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title; content.subtitle = request.subtitle ?? ""; content.body = request.body; content.sound = .default
        content.userInfo = ["automaticRequest": try JSONEncoder().encode(request), "workspaceContext": request.namespace]
        let trigger = UNCalendarNotificationTrigger(dateMatching: ReminderTriggerFactory.dateComponents(for: request.fireDate), repeats: false)
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    func cancelAutomaticPending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllAutomaticPending(namespace: String) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            AutomaticNotificationOwnership.owns(identifier: $0.identifier, userInfo: $0.content.userInfo, namespace: namespace)
        }.map(\.identifier))
    }

    func cancelLegacyPending(namespace: String) async {
        let pending = await center.pendingNotificationRequests()
        let legacyPrefixes = namespace == "gws" ? ["g-calendar.task.", "g-calendar.event."] : ["g-calendar.rest." + namespace + "."]
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { request in
            legacyPrefixes.contains { request.identifier.hasPrefix($0) }
        }.map(\.identifier))
    }
}
