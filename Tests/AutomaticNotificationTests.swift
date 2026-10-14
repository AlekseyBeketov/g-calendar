import Foundation

actor FakeAutomaticScheduler: AutomaticNotificationScheduling {
    var values: [String: AutomaticNotificationRequest] = [:]
    var authorization = ReminderPermission.authorized
    var adds = 0
    var cancellations = 0
    var legacyCancellations = 0
    var failAdd = false
    private var suspendNextAdd = false
    private var addStarted = false
    private var addStartWaiter: CheckedContinuation<Void, Never>?
    private var addReleaseWaiter: CheckedContinuation<Void, Never>?
    func automaticPermission() async -> ReminderPermission { authorization }
    func automaticPending() async -> [AutomaticNotificationRequest] { Array(values.values) }
    func addAutomatic(_ request: AutomaticNotificationRequest) async throws {
        if failAdd { throw GWSFailure.cacheFailure }
        if suspendNextAdd {
            suspendNextAdd = false
            addStarted = true
            addStartWaiter?.resume(); addStartWaiter = nil
            await withCheckedContinuation { addReleaseWaiter = $0 }
        }
        values[request.identifier] = request; adds += 1
    }
    func cancelAutomaticPending(identifiers: [String]) async {
        for id in identifiers { values.removeValue(forKey: id); cancellations += 1 }
    }
    func cancelLegacyPending(namespace: String) async { legacyCancellations += 1 }
    func setPermission(_ value: ReminderPermission) { authorization = value }
    func setFailAdd(_ value: Bool) { failAdd = value }
    func seed(_ requests: [AutomaticNotificationRequest]) { for request in requests { values[request.identifier] = request } }
    func counters() -> (Int, Int, Int) { (adds, cancellations, legacyCancellations) }
    func delayNextAdd() { suspendNextAdd = true; addStarted = false }
    func waitUntilAddStarted() async {
        if addStarted { return }
        await withCheckedContinuation { addStartWaiter = $0 }
    }
    func releaseAdd() { addReleaseWaiter?.resume(); addReleaseWaiter = nil }
}

struct FixtureAutomaticReader: AutomaticNotificationReading {
    let value: AutomaticNotificationRead
    var fails = false
    func read(now: Date) async throws -> AutomaticNotificationRead {
        if fails { throw GWSFailure.cacheFailure }
        return value
    }
}

actor SuspendedAutomaticReader: AutomaticNotificationReading {
    let value: AutomaticNotificationRead
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(value: AutomaticNotificationRead) { self.value = value }
    func read(now: Date) async throws -> AutomaticNotificationRead {
        started = true
        startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return value
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

extension InvariantTests {
    static func notificationEvent(id: String = "event", now: Date, minutes: Int = 0) -> CalendarEvent {
        let start = now.addingTimeInterval(3600)
        return CalendarEvent(id: id, calendarID: "calendar", title: "Synthetic event",
            start: EventTime(rawValue: ISO8601.format(start), instant: start, dateOnly: nil, timeZoneID: "Europe/Moscow"),
            end: EventTime(rawValue: ISO8601.format(start.addingTimeInterval(3600)), instant: start.addingTimeInterval(3600), dateOnly: nil, timeZoneID: "Europe/Moscow"),
            recurring: false, status: "confirmed", reminders: GoogleEventReminders(useDefault: false, overrides: [GooglePopupReminder(method: "popup", minutes: minutes)]))
    }

    static func testAutomaticNotificationPlanner() throws {
        let now = ISO8601.parse("2026-10-13T10:00:00Z")!
        var calendar = CalendarInfo(id: "calendar", title: "Calendar", accessRole: "owner", defaultReminders: [GooglePopupReminder(method: "popup", minutes: 10)])
        var event = notificationEvent(now: now)
        event.location = "Переговорная"
        func plan(_ event: CalendarEvent, locale: Locale = .current) -> AutomaticNotificationPlan {
            AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "account-a", now: now, locale: locale)
        }
        let displayRequest = plan(event, locale: Locale(identifier: "en_US_POSIX")).requests.first!
        try check(displayRequest.title == event.title, "event title is the notification title")
        try check(displayRequest.body == "Переговорная", "notification body contains the event location")
        try check(displayRequest.subtitle?.contains("Oct") == true && displayRequest.subtitle?.contains("2026") == true
                  && displayRequest.subtitle?.contains("2:00") == true && displayRequest.subtitle?.contains("3:00") == true
                  && displayRequest.subtitle?.contains("11:00") == false,
                  "notification date and both times use the event timezone")
        try check(plan(event).requests.first?.fireDate == now.addingTimeInterval(3600), "zero offset fires at exact start")
        event.reminders = GoogleEventReminders(useDefault: true, overrides: [])
        try check(plan(event).requests.first?.fireDate == now.addingTimeInterval(3000), "calendar defaults inherited")
        calendar.defaultReminders = [GooglePopupReminder(method: "popup", minutes: 20)]
        try check(plan(event).requests.first?.fireDate == now.addingTimeInterval(2400), "calendar reminder changes recalculate without event updated")
        event.reminders = GoogleEventReminders(useDefault: false, overrides: [])
        try check(plan(event).requests.isEmpty && plan(event).protectedEventIDs.isEmpty, "empty override disables defaults")
        event.reminders = GoogleEventReminders(useDefault: false, overrides: [GooglePopupReminder(method: "email", minutes: 0)])
        try check(plan(event).requests.isEmpty, "email does not create local popup")
        event.reminders = GoogleEventReminders(useDefault: false, overrides: [GooglePopupReminder(method: "popup", minutes: 0), GooglePopupReminder(method: "popup", minutes: 0), GooglePopupReminder(method: "popup", minutes: 5)])
        try check(plan(event).requests.count == 2, "duplicate offsets deduplicated")
        let requests = plan(event).requests
        try check(Set(requests.map(\.identifier)).count == 2, "offsets have separate identities")
        let other = AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "account-b", now: now)
        try check(Set(other.requests.map(\.identifier)).isDisjoint(with: requests.map(\.identifier)), "accounts isolated")
        try check(requests.allSatisfy { $0.namespace == "account-a" }, "planner retains exact account namespace")
        var distant = notificationEvent(now: now, minutes: 40320)
        let distantStart = now.addingTimeInterval(58 * 86400)
        distant.start = EventTime(rawValue: ISO8601.format(distantStart), instant: distantStart, dateOnly: nil, timeZoneID: "UTC")
        let distantPlan = plan(distant)
        try check(distantPlan.requests.count == 1, "event 58 days away contributes its 28-day advance reminder")
        try check(distantPlan.requests.first?.fireDate == now.addingTimeInterval(30 * 86400), "inclusive 30-day notification horizon")
        distant.start = EventTime(rawValue: ISO8601.format(distantStart.addingTimeInterval(1)), instant: distantStart.addingTimeInterval(1), dateOnly: nil, timeZoneID: "UTC")
        try check(plan(distant).requests.isEmpty, "notification beyond horizon is excluded")
        var firingNow = notificationEvent(now: now, minutes: 60)
        try check(plan(firingNow).requests.isEmpty, "notification at now is excluded")
        firingNow.reminders = GoogleEventReminders(useDefault: false, overrides: [GooglePopupReminder(method: "popup", minutes: 59)])
        try check(plan(firingNow).requests.count == 1, "future notification remains eligible")
        event.recurring = true
        let second = notificationEvent(id: "second-occurrence", now: now)
        try check(AutomaticNotificationPlanner.plan(calendar: calendar, events: [event, second], namespace: "account-a", now: now).requests.count == 3, "recurring occurrences scheduled separately")
        event.reminders = nil
        try check(plan(event).requests.isEmpty && plan(event).protectedEventIDs.count == 1, "unknown reminders protected instead of disabled")
        event.reminders = GoogleEventReminders(useDefault: true, overrides: [])
        calendar.defaultReminders = nil
        try check(plan(event).protectedEventIDs.count == 1, "unknown calendar defaults protected")
        event.start = EventTime(rawValue: "2026-10-13", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-13"), timeZoneID: nil)
        event.end = EventTime(rawValue: "2026-10-14", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-14"), timeZoneID: nil)
        try check(plan(event).requests.isEmpty && plan(event).protectedEventIDs.isEmpty, "all-day events never notified")
        event = notificationEvent(now: now); event.status = "cancelled"
        try check(plan(event).requests.isEmpty, "cancelled never notified")
        event.status = "confirmed"; event.declinedByCurrentUser = true
        try check(plan(event).requests.isEmpty, "declined never notified")
        let locatedEvent = try CalendarEvent.decode(["id": "located", "summary": "Meeting", "location": "  Conference room  ",
            "start": ["dateTime": "2026-10-13T11:00:00+03:00", "timeZone": "Europe/Moscow"],
            "end": ["dateTime": "2026-10-13T11:30:00+03:00", "timeZone": "Europe/Moscow"]], calendarID: "calendar")
        try check(locatedEvent.location == "Conference room", "Google event location is decoded and trimmed")
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(notificationEvent(now: now))) as! [String: Any]
        oldJSON.removeValue(forKey: "reminders"); oldJSON.removeValue(forKey: "declinedByCurrentUser"); oldJSON.removeValue(forKey: "location")
        let old = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try check(old.reminders == nil && old.location == nil, "old event cache remains readable without new optional fields")
        var oldRequestJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(displayRequest)) as! [String: Any]
        oldRequestJSON.removeValue(forKey: "subtitle")
        let oldRequest = try JSONDecoder().decode(AutomaticNotificationRequest.self, from: JSONSerialization.data(withJSONObject: oldRequestJSON))
        try check(oldRequest.subtitle == nil, "previously scheduled notification payload remains readable without subtitle")
        let invalid: [String: Any] = ["useDefault": false, "overrides": [["method": "popup", "minutes": -1]]]
        do { _ = try GoogleEventReminders.decode(invalid); throw TestFailure(description: "malformed reminders accepted") }
        catch GWSFailure.invalidResponse { assertions += 1 }
        for malformed in [
            "{\"useDefault\":0}",
            "{\"useDefault\":false,\"overrides\":[{\"method\":\"popup\",\"minutes\":true}]}"
        ] {
            let object = try JSONSerialization.jsonObject(with: Data(malformed.utf8))
            do { _ = try GoogleEventReminders.decode(object); throw TestFailure(description: "wrong scalar type accepted") }
            catch GWSFailure.invalidResponse { assertions += 1 }
        }
        let malformedPayload: [AnyHashable: Any] = ["workspaceContext": "account-a", "automaticRequest": Data("invalid JSON".utf8)]
        let automaticID = AutomaticNotificationPlanner.prefix + "synthetic-owned-request"
        try check(AutomaticNotificationOwnership.owns(identifier: automaticID, userInfo: malformedPayload, namespace: "account-a"), "raw automatic namespace ownership survives corrupt decoded payload")
        try check(!AutomaticNotificationOwnership.owns(identifier: automaticID, userInfo: malformedPayload, namespace: "account-b"), "corrupt automatic payload never permits other-account cleanup")
        try check(!AutomaticNotificationOwnership.owns(identifier: "g-calendar.task.synthetic", userInfo: malformedPayload, namespace: "account-a"), "automatic ownership excludes legacy identifier even with matching namespace")
        try check(!AutomaticNotificationOwnership.owns(identifier: automaticID, userInfo: ["automaticRequest": Data("invalid JSON".utf8)], namespace: "account-a"), "unknown namespace never permits raw automatic cleanup")
    }

    static func testAutomaticNotificationReconciliation() async throws {
        let now = ISO8601.parse("2026-10-13T10:00:00Z")!
        let calendar = CalendarInfo(id: "calendar", title: "Calendar", accessRole: "owner")
        var event = notificationEvent(now: now)
        event.location = "Meeting room"
        let good = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [event]], failedCalendarIDs: []))
        let scheduler = FakeAutomaticScheduler()
        let coordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: scheduler)
        let initial = await coordinator.refresh(reader: good, enabled: true, now: now)
        try check(initial.scheduledCount == 1 && initial.problem == nil, "automatic reconcile schedules without manual metadata")
        var legacyRequestJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "account", now: now).requests.first!)) as! [String: Any]
        legacyRequestJSON["title"] = "g-calendar"
        legacyRequestJSON["body"] = event.title
        legacyRequestJSON.removeValue(forKey: "subtitle")
        let legacyRequest = try JSONDecoder().decode(AutomaticNotificationRequest.self, from: JSONSerialization.data(withJSONObject: legacyRequestJSON))
        let legacyScheduler = FakeAutomaticScheduler()
        await legacyScheduler.seed([legacyRequest])
        let legacyCoordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: legacyScheduler)
        _ = await legacyCoordinator.refresh(reader: good, enabled: true, now: now)
        let migrated = await legacyScheduler.automaticPending().first
        try check(migrated?.identifier == legacyRequest.identifier && migrated?.title == event.title
                  && migrated?.subtitle != nil && migrated?.body == "Meeting room",
                  "old pending notification is replaced with event details under the same stable identifier")
        _ = await coordinator.refresh(reader: good, enabled: true, now: now)
        let counters = await scheduler.counters()
        try check(counters.0 == 1 && counters.1 == 0, "unchanged refresh does not rewrite or cancel")
        let originalRequest = await scheduler.automaticPending().first!
        var rescheduled = event
        let changedStart = event.start.instant!.addingTimeInterval(900)
        rescheduled.start = EventTime(rawValue: ISO8601.format(changedStart), instant: changedStart, dateOnly: nil, timeZoneID: "Europe/Moscow")
        _ = await coordinator.refresh(reader: FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [rescheduled]], failedCalendarIDs: [])), enabled: true, now: now)
        let changedRequest = await scheduler.automaticPending().first!
        try check(changedRequest.identifier == originalRequest.identifier && changedRequest.fireDate == changedStart, "time edit replaces existing stable identifier")
        let changedCounters = await scheduler.counters()
        try check(changedCounters.0 == 2 && changedCounters.1 == 0, "time edit installs once without cancelling stable identifier")
        _ = await coordinator.refresh(reader: good, enabled: true, now: now)
        let failed = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: [:], failedCalendarIDs: ["calendar"]))
        _ = await coordinator.refresh(reader: failed, enabled: true, now: now)
        let preserved = await scheduler.automaticPending()
        try check(preserved.count == 1, "calendar error preserves pending")
        var unknown = event; unknown.reminders = nil
        _ = await coordinator.refresh(reader: FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [unknown]], failedCalendarIDs: [])), enabled: true, now: now)
        try check(await scheduler.automaticPending().count == 1, "unknown reminders preserve pending")
        var edited = event; edited.title = "New title"
        _ = await coordinator.refresh(reader: FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [edited]], failedCalendarIDs: [])), enabled: true, now: now)
        let editedRequest = await scheduler.automaticPending().first
        try check(editedRequest?.title == "New title" && editedRequest?.body == "Meeting room",
                  "title replacement uses same stable ID and preserves location")
        let other = AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "other", now: now).requests
        await scheduler.seed(other)
        await scheduler.setFailAdd(true)
        var moved = event; moved.reminders = GoogleEventReminders(useDefault: false, overrides: [GooglePopupReminder(method: "popup", minutes: 5)])
        let failure = await coordinator.refresh(reader: FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [moved]], failedCalendarIDs: [])), enabled: true, now: now)
        let pendingAfterFailure = await scheduler.automaticPending()
        try check(failure.problem != nil && pendingAfterFailure.count == 2, "add failure prevents destructive cleanup")
        await scheduler.setFailAdd(false)
        let empty = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": []], failedCalendarIDs: []))
        _ = await coordinator.refresh(reader: empty, enabled: true, now: now)
        try check(await scheduler.automaticPending().map(\.namespace) == ["other"], "confirmed empty cancels only own namespace")
        await scheduler.setPermission(.denied)
        let denied = await coordinator.refresh(reader: good, enabled: true, now: now)
        let pendingAfterDenied = await scheduler.automaticPending()
        try check(denied.problem != nil && pendingAfterDenied.count == 1, "denied never invokes add or permission request")
        await scheduler.setPermission(.authorized)
        _ = await coordinator.refresh(reader: good, enabled: true, now: now)
        _ = await coordinator.refresh(reader: good, enabled: false, now: now)
        try check(await scheduler.automaticPending().count == 1, "global disable cancels automatic own requests")
        _ = await coordinator.refresh(reader: good, enabled: true, now: now)
        let missingCatalogue = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [], events: [:], failedCalendarIDs: []))
        _ = await coordinator.refresh(reader: missingCatalogue, enabled: true, now: now)
        try check(await scheduler.automaticPending().map(\.namespace) == ["other"], "complete catalog removal cancels only removed account calendar")

        try await verifyAutomaticReaderPagination(now: now, calendar: calendar, event: event)
        try await verifyAutomaticRefreshSupersession(now: now, calendar: calendar, event: event)
        try await verifyAutomaticDeleteDuringAdd(now: now, calendar: calendar, event: event)
        try await verifyAutomaticShutdownDuringAdd(now: now, calendar: calendar, event: event)
    }

    static func verifyAutomaticReaderPagination(now: Date, calendar: CalendarInfo, event: CalendarEvent) async throws {
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .calendarList:
                return response(Data(#"{"items":[{"id":"calendar","summary":"Synthetic Calendar","accessRole":"owner"}]}"#.utf8))
            case .eventsList:
                if params(invocation)["pageToken"] == nil {
                    return response(Data(#"{"items":[],"nextPageToken":"second"}"#.utf8))
                }
                return response(Data(), code: 42, stderr: "synthetic second-page failure")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let reader = GoogleAutomaticNotificationReader(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner))
        let read = try await reader.read(now: now)
        try check(read.events["calendar"] == nil && read.failedCalendarIDs == ["calendar"], "later-page failure never publishes partial calendar events")
        let eventCalls = runner.invocations.filter { $0.operation == .eventsList }
        try check(eventCalls.count == 2 && params(eventCalls[1])["pageToken"] as? String == "second", "automatic reader follows event pagination")
        let rangeEnd = ISO8601.parse(params(eventCalls[0])["timeMax"] as! String)!
        try check(rangeEnd > now.addingTimeInterval(58 * 86400), "automatic reader includes 30-day horizon plus maximum reminder offset")
        let scheduler = FakeAutomaticScheduler()
        let requests = AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "account", now: now).requests
        await scheduler.seed(requests)
        let coordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: scheduler)
        let status = await coordinator.refresh(reader: FixtureAutomaticReader(value: read), enabled: true, now: now)
        let retained = await scheduler.automaticPending()
        let counters = await scheduler.counters()
        try check(retained == requests && status.failedCalendarCount == 1, "pagination failure retains previous schedule and reports failed calendar")
        try check(counters.0 == 0 && counters.1 == 0 && counters.2 == 0, "incomplete pagination performs no destructive migration or scheduling")
        let catalogueFailure = await coordinator.refresh(reader: FixtureAutomaticReader(value: read, fails: true), enabled: true, now: now)
        let afterCatalogueFailure = await scheduler.automaticPending()
        try check(catalogueFailure.problem != nil && afterCatalogueFailure == requests, "catalog read error preserves previous pending requests")
    }

    static func verifyAutomaticRefreshSupersession(now: Date, calendar: CalendarInfo, event: CalendarEvent) async throws {
        let scheduler = FakeAutomaticScheduler()
        let coordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: scheduler)
        let oldRead = SuspendedAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [event]], failedCalendarIDs: []))
        let oldRefresh = Task { await coordinator.refresh(reader: oldRead, enabled: true, now: now) }
        await oldRead.waitUntilStarted()
        var latest = event; latest.title = "Latest synthetic title"
        let newReader = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [latest]], failedCalendarIDs: []))
        _ = await coordinator.refresh(reader: newReader, enabled: true, now: now)
        await oldRead.release()
        _ = await oldRefresh.value
        let pending = await scheduler.automaticPending()
        let counters = await scheduler.counters()
        try check(pending.count == 1 && pending.first?.title == latest.title, "queued refresh supersedes suspended stale Google read")
        try check(counters.0 == 1 && counters.1 == 0, "superseded read never installs stale request")

        let suspended = SuspendedAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [event]], failedCalendarIDs: []))
        let refresh = Task { await coordinator.refresh(reader: suspended, enabled: true, now: now) }
        await suspended.waitUntilStarted()
        _ = await coordinator.refresh(reader: newReader, enabled: false, now: now)
        await suspended.release()
        _ = await refresh.value
        let disabledPending = await scheduler.automaticPending()
        let disabledCounters = await scheduler.counters()
        try check(disabledPending.isEmpty && disabledCounters.0 == 1 && disabledCounters.1 == 1, "disable queued during read cancels without resurrecting stale notifications")
    }

    static func verifyAutomaticDeleteDuringAdd(now: Date, calendar: CalendarInfo, event: CalendarEvent) async throws {
        let scheduler = FakeAutomaticScheduler()
        let unrelated = notificationEvent(id: "unrelated", now: now)
        let unrelatedRequests = AutomaticNotificationPlanner.plan(calendar: calendar, events: [unrelated], namespace: "account", now: now).requests
        let otherAccountRequests = AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "other", now: now).requests
        await scheduler.seed(unrelatedRequests + otherAccountRequests)
        await scheduler.delayNextAdd()
        let coordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: scheduler)
        let reader = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [event, unrelated]], failedCalendarIDs: []))
        let refresh = Task { await coordinator.refresh(reader: reader, enabled: true, now: now) }
        await scheduler.waitUntilAddStarted()
        await coordinator.cancelConfirmedEvent(identity: CalendarEventIdentity(calendarID: calendar.id, eventID: event.id))
        await scheduler.releaseAdd()
        _ = await refresh.value
        let pending = await scheduler.automaticPending()
        let counters = await scheduler.counters()
        try check(Set(pending.map(\.identifier)) == Set((unrelatedRequests + otherAccountRequests).map(\.identifier)), "confirmed deletion during suspended add removes only exact event in own namespace")
        try check(counters.0 == 1 && counters.1 == 1, "confirmed deletion drains after active add finishes")
    }

    static func verifyAutomaticShutdownDuringAdd(now: Date, calendar: CalendarInfo, event: CalendarEvent) async throws {
        let scheduler = FakeAutomaticScheduler()
        let otherAccountRequests = AutomaticNotificationPlanner.plan(calendar: calendar, events: [event], namespace: "other", now: now).requests
        await scheduler.seed(otherAccountRequests)
        await scheduler.delayNextAdd()
        let coordinator = AutomaticNotificationCoordinator(namespace: "account", scheduler: scheduler)
        let reader = FixtureAutomaticReader(value: AutomaticNotificationRead(calendars: [calendar], events: ["calendar": [event]], failedCalendarIDs: []))
        let refresh = Task { await coordinator.refresh(reader: reader, enabled: true, now: now) }
        await scheduler.waitUntilAddStarted()
        let shutdown = Task { await coordinator.shutdown() }
        var shutdownStarted = false
        for _ in 0..<10000 {
            if await coordinator.stopped { shutdownStarted = true; break }
            await Task.yield()
        }
        await scheduler.releaseAdd()
        await shutdown.value
        _ = await refresh.value
        try check(shutdownStarted, "shutdown enters stopped state before active scheduler write is released")
        let pending = await scheduler.automaticPending()
        let counters = await scheduler.counters()
        try check(pending == otherAccountRequests && counters.0 == 1 && counters.1 == 1, "shutdown waits for active add then cleans only outgoing account")
        _ = await coordinator.refresh(reader: reader, enabled: true, now: now)
        let afterRestartAttempt = await scheduler.automaticPending()
        let finalCounters = await scheduler.counters()
        try check(afterRestartAttempt == otherAccountRequests && finalCounters.0 == 1, "stopped coordinator cannot recreate outgoing account notifications")
    }
}
