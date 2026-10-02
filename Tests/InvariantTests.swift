import Foundation
import Darwin
import UserNotifications

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw TestFailure(description: message) }
}

final class FakeProcessRunner: GWSProcessRunning, @unchecked Sendable {
    typealias Handler = (ProcessInvocation) throws -> ProcessResult
    private let lock = NSLock()
    private let handler: Handler
    private var storedInvocations: [ProcessInvocation] = []

    init(handler: @escaping Handler) { self.handler = handler }

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
        lock.lock()
        storedInvocations.append(invocation)
        lock.unlock()
        return try handler(invocation)
    }

    var invocations: [ProcessInvocation] {
        lock.lock(); defer { lock.unlock() }
        return storedInvocations
    }
}

final class FakeExactEventReader: ExactCalendarEventReading, @unchecked Sendable {
    let result: Result<CalendarEvent?, Error>
    init(_ result: Result<CalendarEvent?, Error>) { self.result = result }
    func event(identity: CalendarEventIdentity) throws -> CalendarEvent? { try result.get() }
}

final class MemoryMetadataStore: LocalMetadataStoring {
    private let lock = NSLock()
    private var values: [String: LocalTaskMetadata] = [:]

    func metadata(for taskID: String) -> LocalTaskMetadata {
        lock.lock(); defer { lock.unlock() }
        return values[taskID] ?? LocalTaskMetadata(reminderAt: nil, favorite: false)
    }

    func reminderTaskIDs() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(values.compactMap { taskID, metadata in metadata.reminderAt == nil ? nil : taskID })
    }

    func set(_ metadata: LocalTaskMetadata, for taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[taskID] = metadata
    }

    func remove(taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: taskID)
    }
}

final class RecordingScheduler: ReminderScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var currentPermission: ReminderPermission
    private var resultOfRequest: ReminderPermission
    private let requestFailure: NotificationAuthorizationFailure?
    private var storedRequests: [ReminderRequest] = []
    private var storedEventRequests: [EventReminderRequest] = []
    private var pendingRequestsByID: [String: ReminderRequest] = [:]
    private var pendingEventRequestsByID: [String: EventReminderRequest] = [:]
    private var storedCancellations: [String] = []
    private var storedPermissionRequests = 0

    init(permission: ReminderPermission, requestResult: ReminderPermission = .authorized,
         requestFailure: NotificationAuthorizationFailure? = nil) {
        currentPermission = permission
        resultOfRequest = requestResult
        self.requestFailure = requestFailure
    }

    func permission() async -> ReminderPermission {
        readPermission()
    }

    func requestPermission() async throws -> Bool {
        try requestedPermission()
    }

    private func readPermission() -> ReminderPermission {
        lock.lock(); defer { lock.unlock() }
        return currentPermission
    }

    private func requestedPermission() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        storedPermissionRequests += 1
        if let requestFailure { throw NSError(domain: requestFailure.domain, code: requestFailure.code) }
        currentPermission = resultOfRequest
        return resultOfRequest == .authorized
    }

    func schedule(_ reminder: ReminderRequest) async throws {
        recordSchedule(reminder)
    }

    func schedule(_ reminder: EventReminderRequest) async throws {
        recordSchedule(reminder)
    }

    private func recordSchedule(_ reminder: ReminderRequest) {
        lock.lock(); defer { lock.unlock() }
        storedRequests.append(reminder)
        pendingRequestsByID[reminder.identifier] = reminder
    }

    private func recordSchedule(_ reminder: EventReminderRequest) {
        lock.lock(); defer { lock.unlock() }
        storedEventRequests.append(reminder)
        pendingEventRequestsByID[reminder.identifier] = reminder
    }

    func cancel(identifier: String) async {
        recordCancellation(identifier)
    }

    private func recordCancellation(_ identifier: String) {
        lock.lock(); defer { lock.unlock() }
        storedCancellations.append(identifier)
        pendingRequestsByID.removeValue(forKey: identifier)
        pendingEventRequestsByID.removeValue(forKey: identifier)
    }

    var requests: [ReminderRequest] {
        lock.lock(); defer { lock.unlock() }
        return storedRequests
    }

    var eventRequests: [EventReminderRequest] {
        lock.lock(); defer { lock.unlock() }
        return storedEventRequests
    }

    var pendingRequests: [ReminderRequest] {
        lock.lock(); defer { lock.unlock() }
        return Array(pendingRequestsByID.values)
    }

    var pendingEventRequests: [EventReminderRequest] {
        lock.lock(); defer { lock.unlock() }
        return Array(pendingEventRequestsByID.values)
    }

    var cancellations: [String] {
        lock.lock(); defer { lock.unlock() }
        return storedCancellations
    }

    var permissionRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedPermissionRequests
    }
}

@main
struct InvariantTests {
    static let fixtureRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["G_CALENDAR_FIXTURES"] ?? "Tests/Fixtures", isDirectory: true)
    static let executable = URL(fileURLWithPath: "/usr/bin/true")
    static var assertions = 0
    static var failures = 0

    static func main() async {
        run("optional-event-summary", testOptionalEventSummary)
        run("malformed-event-still-rejected", testMalformedEventStillRejected)
        run("file-metadata-date-round-trip", testFileMetadataRoundTrip)
        run("completion-patch-only-status", testCompletionPatchOnlyStatus)
        run("explicit-empty-notes-clears", testExplicitEmptyNotes)
        run("pagination-and-model-mapping", testPaginationAndTypedMapping)
        run("process-errors-malformed-json-timeout", testErrorsAndTimeout)
        run("gws-launcher-finds-node-with-gui-path", testGWSLauncherFindsNodeWithGUIPath)
        run("cache-preserved-after-failed-page", testCachePreservedAfterLaterPageFailure)
        run("date-only-all-day-exclusive-end-dst", testDateOnlyAllDayAndDST)
        run("calendar-task-only-date-is-not-empty", testCalendarTaskOnlyDateIsNotEmpty)
        run("calendar-undated-tasks-once-and-search-scope", testCalendarUndatedTasks)
        await runAsync("demo-runtime-isolated-from-cache-process-and-notifications", testDemoRuntimeIsolation)
        run("calendar-time-grid-all-day-overlap-identity", testCalendarTimeGridLayout)
        run("task-layout-breakpoint-and-event-accessibility-time", testResponsiveAndAccessibilityText)
        run("notification-trigger-retains-subminute-precision", testNotificationTriggerPrecision)
        await runAsync("event-reminder-composite-id-dedupe-range-and-exact-removal", testEventReminderLifecycle)
        run("mutation-guards-and-exact-arguments", testMutationGuardsAndExactArguments)
        run("exact-resource-get-and-mutation-read-back", testExactResourceReadAndMutationReadback)
        await runAsync("reminder-permission-schedule-cancel-reschedule-dedup", testReminderLifecycle)
        await runAsync("notification-authorization-error-and-readback-status", testNotificationAuthorizationOutcome)
        await runAsync("reminder-reconciles-on-wake-and-activation-without-duplicates", testLifecycleReconciliation)
        await runAsync("full-sync-removes-remote-deleted-reminder", testFullSyncRemovesRemoteDeletedReminder)
        await runAsync("failed-later-task-page-preserves-reminder", testFailedTaskPagePreservesReminder)
        if failures > 0 {
            print("FAILURES=\(failures) ASSERTIONS=\(assertions)")
            exit(EXIT_FAILURE)
        }
        print("ASSERTIONS=\(assertions)")
    }

    static func run(_ name: String, _ operation: () throws -> Void) {
        do { try operation(); print("PASS \(name)") }
        catch { failures += 1; fputs("FAIL \(name): \(error)\n", stderr) }
    }

    static func runAsync(_ name: String, _ operation: () async throws -> Void) async {
        do { try await operation(); print("PASS \(name)") }
        catch { failures += 1; fputs("FAIL \(name): \(error)\n", stderr) }
    }

    static func check(_ condition: Bool, _ message: String) throws {
        assertions += 1
        try require(condition, message)
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureRoot.appendingPathComponent(name))
    }

    static func response(_ data: Data, code: Int32 = 0, stderr: String = "") -> ProcessResult {
        ProcessResult(exitCode: code, stdout: data, stderr: Data(stderr.utf8))
    }

    static func params(_ invocation: ProcessInvocation) -> [String: Any] {
        guard let index = invocation.arguments.firstIndex(of: "--params"), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    static func jsonBody(_ invocation: ProcessInvocation) throws -> [String: Any] {
        guard let index = invocation.arguments.firstIndex(of: "--json"), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestFailure(description: "mutation body was not valid JSON")
        }
        return object
    }

    static func testOptionalEventSummary() throws {
        let object = try JSONSerialization.jsonObject(with: fixture("event-no-summary.json")) as! [String: Any]
        let event = try CalendarEvent.decode(object, calendarID: "calendar-fixture")
        try check(event.title == "Без названия", "valid untitled event did not receive a visible fallback")
    }

    static func testMalformedEventStillRejected() throws {
        let validBase = try JSONSerialization.jsonObject(with: fixture("event-no-summary.json")) as! [String: Any]
        var missingID = validBase; missingID.removeValue(forKey: "id")
        var emptyID = validBase; emptyID["id"] = ""
        var whitespaceOnlyID = validBase; whitespaceOnlyID["id"] = " \t\n"
        var missingStart = validBase; missingStart.removeValue(forKey: "start")
        var missingEnd = validBase; missingEnd.removeValue(forKey: "end")
        let invalidDate = try JSONSerialization.jsonObject(with: fixture("event-invalid-date.json")) as! [String: Any]
        for candidate in [missingID, emptyID, whitespaceOnlyID, missingStart, missingEnd, invalidDate] {
            do {
                _ = try CalendarEvent.decode(candidate, calendarID: "calendar-fixture")
                throw TestFailure(description: "malformed event shape/date was accepted")
            } catch let failure as GWSFailure {
                if case .invalidResponse = failure { try check(true, "required event fields/date remain strict") }
                else { throw TestFailure(description: "unexpected typed error for malformed event") }
            }
        }
    }

    static func testFileMetadataRoundTrip() throws {
        let temporaryRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        let directory = temporaryRoot.appendingPathComponent("g-calendar-metadata-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("metadata.json")
        let taskID = "synthetic-file-store-task"
        let reminderDate = ISO8601.parse("2026-10-01T09:30:00Z")!
        let firstStore = FileLocalMetadataStore(fileURL: fileURL)
        try firstStore.set(LocalTaskMetadata(reminderAt: reminderDate, favorite: true), for: taskID)
        let reopenedStore = FileLocalMetadataStore(fileURL: fileURL)
        let restored = reopenedStore.metadata(for: taskID)
        try check(restored.reminderAt == reminderDate, "ISO8601 reminder date did not survive reopening the file store")
        try check(restored.favorite, "favorite metadata did not survive reopening the file store")
    }

    static func testCompletionPatchOnlyStatus() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let task = GoogleTask(id: "synthetic-completion-task", taskListID: "synthetic-list", title: "Newer remote title",
                              notes: "newer remote notes", due: DateOnly(rawValue: "2026-10-01"), completed: false, deleted: false, updated: nil)
        let invocation = try factory.taskPatch(task: task, title: "stale cached title", notes: "stale cached notes",
                                               due: DateOnly(rawValue: "2026-10-02"), completed: true, authorization: .userCompletionToggle)
        let body = try jsonBody(invocation)
        try check(Set(body.keys) == Set(["status"]), "completion PATCH must contain only status; got \(body.keys.sorted())")
        try check(body["status"] as? String == "completed", "completion PATCH status value mismatch")
    }

    static func testExplicitEmptyNotes() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let task = GoogleTask(id: "synthetic-notes-task", taskListID: "synthetic-list", title: "Synthetic task",
                              notes: "old note", due: DateOnly(rawValue: "2026-10-01"), completed: false, deleted: false, updated: nil)
        let omitted = try factory.taskPatch(task: task, title: task.title, notes: nil, due: task.due, authorization: .userSave)
        let explicitClear = try factory.taskPatch(task: task, title: task.title, notes: "", due: task.due, authorization: .userSave)
        let omittedBody = try jsonBody(omitted)
        let clearBody = try jsonBody(explicitClear)
        try check(omittedBody["notes"] == nil, "nil notes should not be sent")
        try check(clearBody["notes"] as? String == "", "explicit empty notes must be sent to clear remote notes")
    }

    static func testPaginationAndTypedMapping() throws {
        let runner = FakeProcessRunner { invocation in
            let pageToken = params(invocation)["pageToken"] as? String
            switch invocation.operation {
            case .calendarList:
                return response(try fixture(pageToken == nil ? "calendars-page-1.json" : "calendars-page-2.json"))
            case .eventsList:
                return response(try fixture(pageToken == nil ? "events-page-1.json" : "events-page-2.json"))
            case .taskListsList:
                return response(try fixture(pageToken == nil ? "tasklists-page-1.json" : "tasklists-page-2.json"))
            case .tasksList:
                return response(try fixture(pageToken == nil ? "tasks-page-1.json" : "tasks-page-2.json"))
            default:
                throw GWSFailure.forbiddenOperation
            }
        }
        let factory = GWSCommandFactory(executableURL: executable)
        let reader = GWSReadClient(factory: factory, runner: runner)
        let calendars = try reader.calendars()
        let lists = try reader.taskLists()
        let tasks = try reader.tasks(taskListID: "list-fixture-1")
        let start = DateOnly(rawValue: "2026-03-08")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let end = DateOnly(rawValue: "2026-03-10")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let events = try reader.events(calendarID: "calendar-fixture-1", range: DateRange(start: start, endExclusive: end))

        try check(calendars.count == 2, "calendar pages were not fully collected")
        try check(lists.count == 2, "task-list pages were not fully collected")
        try check(tasks.count == 2, "task pages were not fully collected")
        try check(events.count == 2, "event pages were not fully collected")
        try check(calendars[1].accessRole == "reader", "calendar accessRole mapping failed")
        try check(tasks[0].due == DateOnly(rawValue: "2026-03-08"), "task due did not map as date-only")

        let calls = runner.invocations
        for operation in [GWSOperation.calendarList, .eventsList, .taskListsList, .tasksList] {
            try check(calls.filter { $0.operation == operation }.count == 2, "pagination did not request both pages for \(operation.rawValue)")
        }
        for operation in [GWSOperation.calendarList, .eventsList, .taskListsList, .tasksList] {
            let secondPage = calls.filter { $0.operation == operation }.last!
            try check(params(secondPage)["pageToken"] as? String != nil, "second-page token missing for \(operation.rawValue)")
        }
    }

    static func testErrorsAndTimeout() throws {
        let nonzeroRunner = FakeProcessRunner { _ in
            response(Data(), code: 37, stderr: "synthetic-private-diagnostic")
        }
        do {
            _ = try GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: nonzeroRunner).calendars()
            throw TestFailure(description: "non-zero process exit was accepted")
        } catch let failure as GWSFailure {
            if case .processFailed(_, 37, "command_failure") = failure { try check(true, "non-zero process code") }
            else { throw TestFailure(description: "non-zero process error was not typed") }
            try check(!(failure.errorDescription ?? "").contains("synthetic-private-diagnostic"), "stderr content escaped safe error category")
        }

        let malformedRunner = FakeProcessRunner { _ in response(Data("{not-json".utf8)) }
        do {
            _ = try GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: malformedRunner).calendars()
            throw TestFailure(description: "malformed JSON was accepted")
        } catch let failure as GWSFailure {
            if case .invalidResponse = failure { try check(true, "malformed JSON typed error") }
            else { throw TestFailure(description: "malformed JSON did not produce invalidResponse") }
        }

        let sleeper = fixtureRoot.appendingPathComponent("sleeping-gws.sh")
        let invocation = ProcessInvocation(executableURL: sleeper, arguments: [], operation: .tasksList, timeout: 0.05, outputLimit: 1024)
        do {
            _ = try FoundationProcessRunner().run(invocation)
            throw TestFailure(description: "timed-out fixture process was accepted")
        } catch let failure as GWSFailure {
            if case .timedOut("tasks.tasks.list") = failure { try check(true, "timeout typed error") }
            else { throw TestFailure(description: "timeout did not produce typed error") }
        }
    }

    static func testGWSLauncherFindsNodeWithGUIPath() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("g-calendar-gui-path-test-\(UUID().uuidString)", isDirectory: true)
        let localBin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let node = localBin.appendingPathComponent("node")
        let launcher = root.appendingPathComponent("gws")
        try "#!/bin/sh\nprintf 'synthetic-node-found\\n'\n".write(to: node, atomically: true, encoding: .utf8)
        try "#!/usr/bin/env node\nprocess.stdout.write('synthetic-node-found\\n')\n".write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let invocation = ProcessInvocation(executableURL: launcher, arguments: [], operation: .calendarList,
                                           timeout: 2, outputLimit: 1024)
        let result = try FoundationProcessRunner(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root).run(invocation)
        try check(result.exitCode == 0, "GUI-launched gws must find node from the standard per-user bin directory; exit=\(result.exitCode)")
        try check(String(decoding: result.stdout, as: UTF8.self).contains("synthetic-node-found"),
                  "the resolved node executable did not run the synthetic gws launcher")
    }

    static func testCachePreservedAfterLaterPageFailure() throws {
        let oldCalendar = CalendarInfo(id: "old-fixture-calendar", title: "Old Synthetic Calendar", accessRole: "reader", timeZoneID: "UTC", colorHex: nil)
        let oldSnapshot = WorkspaceSnapshot(calendars: [oldCalendar], events: [], taskLists: [], tasks: [], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = MemorySnapshotStore(oldSnapshot)
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .calendarList: return response(try fixture("calendars-page-2.json"))
            case .eventsList:
                if params(invocation)["pageToken"] == nil { return response(try fixture("events-page-1.json")) }
                return response(Data(), code: 42, stderr: "synthetic later page error")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let start = DateOnly(rawValue: "2026-03-08")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let end = DateOnly(rawValue: "2026-03-15")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        do {
            _ = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner), cache: cache)
                .refresh(range: DateRange(start: start, endExclusive: end))
            throw TestFailure(description: "failed later page returned a successful refresh")
        } catch let failure as GWSFailure {
            if case .processFailed(_, 42, _) = failure { try check(true, "later page failure surfaced") }
            else { throw TestFailure(description: "later page failure type was not preserved") }
        }
        try check(cache.load() == oldSnapshot, "last-known-good cache changed after later page failure")
    }

    static func testDateOnlyAllDayAndDST() throws {
        let tasksObject = try JSONSerialization.jsonObject(with: fixture("tasks-page-1.json")) as! [String: Any]
        let item = (tasksObject["items"] as! [[String: Any]])[0]
        let task = try GoogleTask.decode(item, taskListID: "list-fixture-1")
        try check(task.due == DateOnly(rawValue: "2026-03-08"), "date-only due retained API time/offset")

        let eventsObject = try JSONSerialization.jsonObject(with: fixture("events-page-1.json")) as! [String: Any]
        let event = try CalendarEvent.decode((eventsObject["items"] as! [[String: Any]])[0], calendarID: "calendar-fixture-1")
        try check(event.isAllDay, "all-day event mapping failed")
        try check(event.visibleAllDayEnd == DateOnly(rawValue: "2026-03-08"), "exclusive all-day end was not converted to visible inclusive end")

        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let dstStart = DateOnly(rawValue: "2026-03-08")!.startOfDay(in: zone)!
        let dstEndExclusive = DateOnly(rawValue: "2026-03-09")!.startOfDay(in: zone)!
        try check(dstEndExclusive.timeIntervalSince(dstStart) == 23 * 60 * 60, "DST all-day span must use local calendar days, not 24-hour arithmetic")
    }

    static func testCalendarTaskOnlyDateIsNotEmpty() throws {
        let task = GoogleTask(id: "synthetic-calendar-task-only", taskListID: "synthetic-list", title: "Synthetic dated task",
                              notes: nil, due: DateOnly(rawValue: "2026-10-01"), completed: false, deleted: false, updated: nil)
        try check(!CalendarContentAvailability.isEmpty(events: [], tasks: [task]), "date-only tasks must keep a calendar day visible when it has no events")
    }

    static func testCalendarUndatedTasks() throws {
        let undated = GoogleTask(id: "synthetic-undated-task", taskListID: "synthetic-list-a", title: "Synthetic timeless task",
                                 notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let dated = GoogleTask(id: "synthetic-dated-task", taskListID: "synthetic-list-a", title: "Synthetic dated task",
                               notes: nil, due: DateOnly(rawValue: "2026-10-02"), completed: false, deleted: false, updated: nil)
        let deleted = GoogleTask(id: "synthetic-deleted-task", taskListID: "synthetic-list-a", title: "Synthetic deleted task",
                                 notes: nil, due: nil, completed: false, deleted: true, updated: nil)
        let otherList = GoogleTask(id: "synthetic-other-list-task", taskListID: "synthetic-list-b", title: "Synthetic other list",
                                   notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let tasks = [undated, dated, deleted, otherList]
        let scoped = CalendarTimeGridLayout.undatedTasks(tasks, selectedTaskListID: "synthetic-list-a", searchText: "timeless")
        try check(scoped == [undated], "timeless region must apply selected task list and search, excluding dated/deleted tasks")
        try check(CalendarTimeGridLayout.undatedTasks(tasks, selectedTaskListID: nil, searchText: "").filter { $0.id == undated.id }.count == 1,
                  "an undated task must be returned once for the week-level region, not once per day")
        try check(!CalendarContentAvailability.isEmpty(events: [], tasks: scoped), "an undated task must keep calendar search/content state non-empty")
        try check(CalendarTimeGridLayout.undatedTasks(tasks, selectedTaskListID: nil, searchText: "missing").isEmpty,
                  "timeless task region must respect no-match search state")
    }

    static func testDemoRuntimeIsolation() async throws {
        try check(AppLaunchMode.parse(arguments: ["g-calendar", "--demo"]) == .demo, "--demo launch flag was not parsed")
        try check(AppLaunchMode.parse(arguments: ["g-calendar", "--notification-status"]) == .notificationStatus,
                  "--notification-status launch flag was not parsed")
        var liveFactoryCalled = false
        let demoRunner = RuntimeProcessBoundary.runner(for: .demo) {
            liveFactoryCalled = true
            return FakeProcessRunner { _ in throw GWSFailure.forbiddenOperation }
        }
        let statusRunner = RuntimeProcessBoundary.runner(for: .notificationStatus) {
            liveFactoryCalled = true
            return FakeProcessRunner { _ in throw GWSFailure.forbiddenOperation }
        }
        let demoRunnerUnavailable: Bool
        if case nil = demoRunner { demoRunnerUnavailable = true } else { demoRunnerUnavailable = false }
        let statusRunnerUnavailable: Bool
        if case nil = statusRunner { statusRunnerUnavailable = true } else { statusRunnerUnavailable = false }
        let adapter = DemoWorkspaceAdapter(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
        let snapshot = adapter.snapshot()
        try check(demoRunnerUnavailable && statusRunnerUnavailable && !liveFactoryCalled,
                  "isolated modes constructed a live Google process runner")
        try check(snapshot.calendars.map(\.id) == ["demo-calendar"] && snapshot.events.first?.id == "demo-event" &&
                  snapshot.tasks.contains(where: { $0.id == "demo-task-undated" }) && snapshot.tasks.count >= 50 &&
                  snapshot.tasks.allSatisfy({ $0.id.hasPrefix("demo-task-") }),
                  "demo adapter must expose deterministic synthetic fixtures including enough rows to exercise scrolling")
        let factory = GWSCommandFactory(executableURL: executable)
        let eventBody: [String: Any] = [
            "summary": "Demo: created event",
            "start": ["dateTime": "1970-01-01T10:00:00Z", "timeZone": "UTC"],
            "end": ["dateTime": "1970-01-01T11:00:00Z", "timeZone": "UTC"]
        ]
        try adapter.perform(factory.eventInsert(calendar: snapshot.calendars[0], body: eventBody, authorization: .userSave))
        guard let createdEvent = adapter.snapshot().events.first(where: { $0.id == "demo-created-event-1" }) else {
            throw TestFailure(description: "demo event create did not update the fixture snapshot")
        }
        try check(createdEvent.title == "Demo: created event", "demo event create did not preserve its title")
        try adapter.perform(factory.eventPatch(event: createdEvent, calendar: snapshot.calendars[0],
                                               body: ["summary": "Demo: edited event"], authorization: .userSave))
        try check(adapter.snapshot().events.first(where: { $0.id == createdEvent.id })?.title == "Demo: edited event",
                  "demo event edit did not update the fixture snapshot")
        try adapter.perform(factory.eventDelete(event: createdEvent, calendar: snapshot.calendars[0], authorization: .confirmedDelete))
        try check(!adapter.snapshot().events.contains(where: { $0.id == createdEvent.id }), "demo event delete did not update the fixture snapshot")

        try adapter.perform(factory.taskListInsert(title: "Demo: new list", authorization: .userSave))
        guard let createdList = adapter.snapshot().taskLists.first(where: { $0.id == "demo-created-task-list-1" }) else {
            throw TestFailure(description: "demo task-list create did not update the fixture snapshot")
        }
        try adapter.perform(factory.taskListPatch(id: createdList.id, title: "Demo: edited list", authorization: .userSave))
        try check(adapter.snapshot().taskLists.first(where: { $0.id == createdList.id })?.title == "Demo: edited list",
                  "demo task-list edit did not update the fixture snapshot")
        try adapter.perform(factory.taskInsert(taskListID: createdList.id, title: "Demo: new task", notes: "fixture",
                                                due: DateOnly(rawValue: "1970-01-02"), authorization: .userSave))
        guard let createdTask = adapter.snapshot().tasks.first(where: { $0.id == "demo-created-task-1" }) else {
            throw TestFailure(description: "demo task create did not update the fixture snapshot")
        }
        try check(createdTask.title == "Demo: new task" && createdTask.due == DateOnly(rawValue: "1970-01-02"),
                  "demo task create did not preserve fixture fields")
        try adapter.perform(factory.taskPatch(task: createdTask, title: createdTask.title, notes: createdTask.notes,
                                              due: createdTask.due, completed: true, authorization: .userCompletionToggle))
        try check(adapter.snapshot().tasks.first(where: { $0.id == createdTask.id })?.completed == true,
                  "demo task completion did not update the fixture snapshot")
        let completedTask = adapter.snapshot().tasks.first(where: { $0.id == createdTask.id })!
        try adapter.perform(factory.taskPatch(task: completedTask, title: "Demo: edited task", notes: "",
                                              due: nil, completed: completedTask.completed, authorization: .userSave))
        let editedTask = adapter.snapshot().tasks.first(where: { $0.id == createdTask.id })!
        try check(editedTask.title == "Demo: edited task" && editedTask.notes == "" && editedTask.due == nil,
                  "demo task edit did not update the fixture snapshot")
        try adapter.perform(factory.taskDelete(task: editedTask, authorization: .confirmedDelete))
        try check(!adapter.snapshot().tasks.contains(where: { $0.id == createdTask.id }), "demo task delete did not update the fixture snapshot")
        try adapter.perform(factory.taskInsert(taskListID: createdList.id, title: "Demo: cascade task", notes: nil,
                                               due: nil, authorization: .userSave))
        try adapter.perform(factory.taskListDelete(id: createdList.id, authorization: .confirmedDelete))
        try check(!adapter.snapshot().taskLists.contains(where: { $0.id == createdList.id }) &&
                  !adapter.snapshot().tasks.contains(where: { $0.taskListID == createdList.id }),
                  "demo task-list delete must remove the list and its fixture tasks")
        try expectForbidden({ try adapter.perform(factory.readTaskLists(pageToken: nil)) }, "demo remote list read")
        try check(adapter.simulatedMutationCount == 11 && !liveFactoryCalled,
                  "demo CRUD actions did not stay inside the in-memory fixture adapter")
        let status = await NoopReminderScheduler().notificationStatus()
        try check(status.authorization == "not_queried" && status.safeSummary.contains("authorization=not_queried"),
                  "demo scheduler must not query UserNotifications")
    }

    static func testEventReminderLifecycle() async throws {
        let event = syntheticTimedEvent(id: "synthetic-reminder-event", calendarID: "synthetic-calendar",
                                        start: "2026-10-02T10:00:00-04:00", end: "2026-10-02T11:00:00-04:00")
        let store = MemoryLocalEventReminderStore()
        let scheduler = RecordingScheduler(permission: .authorized)
        let coordinator = EventReminderCoordinator(store: store, scheduler: scheduler)
        let firstFireDate = Date().addingTimeInterval(3_600.375)
        let fireDate = firstFireDate.addingTimeInterval(61)
        _ = try await coordinator.save(event: event, at: firstFireDate, now: Date())
        _ = try await coordinator.save(event: event, at: fireDate, now: Date())
        let identity = event.identity
        try check(store.all().count == 1 && store.record(for: identity)?.fireDate == fireDate,
                  "event reminder metadata must round-trip and deduplicate by calendar+event identity")
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("g-calendar-event-reminder-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = FileLocalEventReminderStore(fileURL: root.appendingPathComponent("event-reminders.json"))
        let record = LocalEventReminderRecord(identity: identity, fireDate: fireDate)
        try fileStore.set(record, for: identity)
        let roundTripRecord = FileLocalEventReminderStore(fileURL: root.appendingPathComponent("event-reminders.json")).record(for: identity)
        try check(roundTripRecord == record,
                  "event reminder metadata must survive a separate local-store round trip (identity_match=\(roundTripRecord?.identity == identity), expected_bits=\(record.fireDate.timeIntervalSince1970.bitPattern), actual_bits=\(String(describing: roundTripRecord?.fireDate.timeIntervalSince1970.bitPattern)))")
        let legacyURL = root.appendingPathComponent("legacy-event-reminders.json")
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode([identity.stableKey: record]).write(to: legacyURL)
        let legacyRecord = FileLocalEventReminderStore(fileURL: legacyURL).record(for: identity)
        let expectedSecond = Calendar.current.component(.second, from: fireDate)
        try check(legacyRecord.map { Calendar.current.component(.second, from: $0.fireDate) } == expectedSecond,
                  "event reminder store must continue reading legacy ISO-8601 timestamps to second precision")
        try check(scheduler.eventRequests.count == 2 && Set(scheduler.eventRequests.map(\.identifier)).count == 1,
                  "reschedule must use the same deterministic local request identity")
        let reminderIdentifier = EventReminderIdentity.identifier(for: identity)
        try check(scheduler.cancellations == [reminderIdentifier, reminderIdentifier] &&
                  scheduler.pendingEventRequests.count == 1 && scheduler.pendingEventRequests.first?.fireDate == fireDate,
                  "rescheduling must cancel the old request, preserve the exact second-level time, and leave one pending request")

        await coordinator.reconcile(using: FakeExactEventReader(.success(event)), now: Date())
        try check(store.record(for: identity) != nil, "event absent from a bounded list must not be treated as deleted after exact GET finds it")
        let exactEventJSON = try JSONSerialization.data(withJSONObject: [
            "id": event.id,
            "summary": event.title,
            "start": ["dateTime": event.start.rawValue, "timeZone": event.start.timeZoneID ?? "UTC"],
            "end": ["dateTime": event.end.rawValue, "timeZone": event.end.timeZoneID ?? "UTC"],
            "status": "confirmed"
        ])
        let boundedRangeRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .eventsList: return response(Data(#"{"items":[]}"#.utf8))
            case .eventGet: return response(exactEventJSON)
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let boundedReader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: boundedRangeRunner)
        let eventStart = event.start.instant!
        let eventEnd = event.end.instant!
        let eventRange = try DateRange(start: eventStart.addingTimeInterval(-3_600), endExclusive: eventEnd.addingTimeInterval(3_600),
                                       timeZone: TimeZone(identifier: "America/New_York")!)
        try check(try boundedReader.events(calendarID: event.calendarID, range: eventRange).isEmpty,
                  "bounded calendar fixture should omit the event from its current range")
        await coordinator.reconcile(using: boundedReader, now: Date())
        try check(store.record(for: identity) != nil,
                  "absence from a range-bounded event list must not prune local reminder metadata")
        await coordinator.reconcile(using: FakeExactEventReader(.failure(GWSFailure.processFailed("calendar.events.get", 1, "network"))), now: Date())
        try check(store.record(for: identity) != nil, "failed exact refresh must preserve event reminder metadata")
        await coordinator.reconcile(using: FakeExactEventReader(.success(nil)), now: Date())
        try check(store.record(for: identity) == nil, "only exact confirmed not-found may prune remote event reminder metadata")
        try check(scheduler.cancellations.contains(EventReminderIdentity.identifier(for: identity)),
                  "exact remote removal must cancel the deterministic pending request")

        let allDay = CalendarEvent(id: "synthetic-all-day", calendarID: "synthetic-calendar", title: "Synthetic all day",
                                   start: EventTime(rawValue: "2026-10-02", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-02"), timeZoneID: nil),
                                   end: EventTime(rawValue: "2026-10-03", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-03"), timeZoneID: nil),
                                   recurring: false, status: nil)
        do {
            _ = try await coordinator.save(event: allDay, at: fireDate, now: Date())
            throw TestFailure(description: "all-day event reminder was accepted")
        } catch let failure as GWSFailure {
            try check(failure == .forbiddenOperation, "all-day reminder must be guarded")
        }
        let recurring = CalendarEvent(id: "synthetic-recurring-event", calendarID: "synthetic-calendar", title: "Synthetic recurring",
                                      start: event.start, end: event.end, recurring: true, status: nil)
        do {
            _ = try await coordinator.save(event: recurring, at: fireDate, now: Date())
            throw TestFailure(description: "recurring event reminder was accepted")
        } catch let failure as GWSFailure {
            try check(failure == .forbiddenOperation, "recurring event reminder must be guarded")
        }
    }

    static func testResponsiveAndAccessibilityText() throws {
        try check(TaskWorkspaceLayout.usesSingleColumn(availableWidth: 760), "narrow task workspace must switch to one column")
        let windowWidth = 920.0
        let detailWidth = TaskWorkspaceLayout.detailWidth(windowWidth: windowWidth)
        try check(detailWidth == 675, "920-point window with the sidebar must reserve the configured sidebar width")
        try check(TaskWorkspaceLayout.usesSingleColumn(availableWidth: detailWidth),
                  "920-point window must use a single task column after accounting for the visible sidebar")
        try check(TaskWorkspaceLayout.usesSingleColumn(availableWidth: windowWidth),
                  "920-point window must also use a single task column when the sidebar is collapsed")
        try check(!TaskWorkspaceLayout.usesSingleColumn(availableWidth: 1_020), "wide task workspace should retain available columns at its threshold")
        try check(CalendarGridLayout.columnWidth(isDayView: true, availableWidth: 640) == 640,
                  "day grid must use the available detail width")
        try check(CalendarGridLayout.columnWidth(isDayView: true, availableWidth: 160) == CalendarGridLayout.minimumColumnWidth,
                  "day grid must retain its minimum readable width in a narrow viewport")
        try check(CalendarGridLayout.columnWidth(isDayView: false, availableWidth: 1_400) == CalendarGridLayout.minimumColumnWidth,
                  "week grid must retain the configured per-day width")
        let event = syntheticTimedEvent(id: "synthetic-accessibility-event", calendarID: "synthetic-calendar",
                                        start: "2026-10-02T09:00:00-04:00", end: "2026-10-02T10:00:00-04:00")
        try check(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: TimeZone(secondsFromGMT: 0)!) == "09:00–10:00",
                  "event accessibility time must use the event calendar time zone, not system time zone")
    }

    static func testNotificationTriggerPrecision() throws {
        for lead in [10.0, 90.0] {
            let requestedDate = Date().addingTimeInterval(lead)
            let trigger = UNCalendarNotificationTrigger(dateMatching: ReminderTriggerFactory.dateComponents(for: requestedDate), repeats: false)
            guard let nextDate = trigger.nextTriggerDate() else {
                throw TestFailure(description: "future trigger at \(Int(lead)) seconds returned no next date")
            }
            let difference = abs(nextDate.timeIntervalSince(requestedDate))
            try check(difference <= 1.25, "future trigger at \(Int(lead)) seconds drifted by \(difference) seconds")
        }
    }

    static func testCalendarTimeGridLayout() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let day = DateOnly(rawValue: "2026-10-01")!.startOfDay(in: zone)!
        let first = syntheticTimedEvent(id: "shared-event-id", calendarID: "calendar-alpha", start: "2026-10-01T09:00:00-04:00", end: "2026-10-01T10:00:00-04:00")
        let overlap = syntheticTimedEvent(id: "overlap-event", calendarID: "calendar-beta", start: "2026-10-01T09:30:00-04:00", end: "2026-10-01T10:30:00-04:00")
        let overnight = syntheticTimedEvent(id: "overnight-event", calendarID: "calendar-alpha", start: "2026-09-30T23:30:00-04:00", end: "2026-10-01T00:30:00-04:00")
        let placements = CalendarTimeGridLayout.timedPlacements([overlap, first, overnight], on: day, timeZone: zone)
        let firstPlacement = placements.first { $0.identity == first.identity }
        let overlapPlacement = placements.first { $0.identity == overlap.identity }
        let overnightPlacement = placements.first { $0.identity == overnight.identity }
        try check(firstPlacement?.startOffsetMinutes == 540 && firstPlacement?.durationMinutes == 60, "timed event must use selected-zone local position and duration")
        try check(firstPlacement?.laneCount == 2 && overlapPlacement?.laneCount == 2 && firstPlacement?.laneIndex != overlapPlacement?.laneIndex,
                  "overlapping events must receive deterministic, non-obscuring lanes")
        try check(overnightPlacement?.startOffsetMinutes == 0 && overnightPlacement?.durationMinutes == 30, "cross-midnight event must be clipped to the visible local day")

        let allDay = CalendarEvent(id: "all-day-event", calendarID: "calendar-alpha", title: "Synthetic all-day",
                                   start: EventTime(rawValue: "2026-10-01", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-01"), timeZoneID: nil),
                                   end: EventTime(rawValue: "2026-10-03", instant: nil, dateOnly: DateOnly(rawValue: "2026-10-03"), timeZoneID: nil),
                                   recurring: false, status: nil)
        let secondDay = DateOnly(rawValue: "2026-10-02")!.startOfDay(in: zone)!
        let exclusiveEndDay = DateOnly(rawValue: "2026-10-03")!.startOfDay(in: zone)!
        try check(CalendarTimeGridLayout.allDayEvents([allDay], on: secondDay, timeZone: zone).map(\.identity) == [allDay.identity],
                  "all-day event must appear through its inclusive visible end")
        try check(CalendarTimeGridLayout.allDayEvents([allDay], on: exclusiveEndDay, timeZone: zone).isEmpty,
                  "exclusive all-day end must not render as a visible date")

        let sameRemoteID = syntheticTimedEvent(id: first.id, calendarID: "calendar-beta", start: "2026-10-01T11:00:00-04:00", end: "2026-10-01T12:00:00-04:00")
        let calendars = [
            CalendarInfo(id: "calendar-alpha", title: "Synthetic Alpha", accessRole: "writer", timeZoneID: zone.identifier, colorHex: "#336699"),
            CalendarInfo(id: "calendar-beta", title: "Synthetic Beta", accessRole: "reader", timeZoneID: zone.identifier, colorHex: "#993366")
        ]
        let colorsByCalendar = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.colorHex) })
        try check(first.identity != sameRemoteID.identity, "event identity must include its calendar ID")
        try check(colorsByCalendar[first.identity.calendarID] == "#336699" && colorsByCalendar[sameRemoteID.identity.calendarID] == "#993366",
                  "event rendering must resolve color from the event's own calendar")

        let springDay = DateOnly(rawValue: "2026-03-08")!.startOfDay(in: zone)!
        let fallDay = DateOnly(rawValue: "2026-11-01")!.startOfDay(in: zone)!
        try check(CalendarTimeGridLayout.dayInterval(containing: springDay, timeZone: zone)?.durationMinutes == 23 * 60,
                  "spring DST grid must use the actual 23-hour local day")
        try check(CalendarTimeGridLayout.dayInterval(containing: fallDay, timeZone: zone)?.durationMinutes == 25 * 60,
                  "fall DST grid must use the actual 25-hour local day")
    }

    static func syntheticTimedEvent(id: String, calendarID: String, start: String, end: String) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: calendarID, title: "Synthetic event",
                      start: EventTime(rawValue: start, instant: ISO8601.parse(start), dateOnly: nil, timeZoneID: "America/New_York"),
                      end: EventTime(rawValue: end, instant: ISO8601.parse(end), dateOnly: nil, timeZoneID: "America/New_York"),
                      recurring: false, status: nil)
    }

    static func expectForbidden(_ operation: () throws -> Void, _ label: String) throws {
        do {
            try operation()
            throw TestFailure(description: "guard allowed \(label)")
        } catch let failure as GWSFailure {
            try check(failure == .forbiddenOperation, "wrong guard error for \(label)")
        }
    }

    static func testExactResourceReadAndMutationReadback() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let calendar = CalendarInfo(id: "synthetic-writable-calendar", title: "Synthetic Writable", accessRole: "writer", timeZoneID: "UTC", colorHex: nil)
        let body: [String: Any] = ["summary": "Synthetic verified event",
                                   "start": ["dateTime": "2026-10-02T10:00:00Z", "timeZone": "UTC"],
                                   "end": ["dateTime": "2026-10-02T11:00:00Z", "timeZone": "UTC"]]
        let insert = try factory.eventInsert(calendar: calendar, body: body, authorization: .userSave)
        let params = Self.params(insert)
        try check(params["calendarId"] as? String == calendar.id && params["sendUpdates"] as? String == "none",
                  "event insert must target selected writable calendar and suppress attendee updates")
        let eventJSON = #"{"id":"synthetic-created-event","summary":"Synthetic verified event","start":{"dateTime":"2026-10-02T10:00:00Z","timeZone":"UTC"},"end":{"dateTime":"2026-10-02T11:00:00Z","timeZone":"UTC"},"status":"confirmed"}"#
        let insertRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .eventInsert: return response(Data(#"{"id":"synthetic-created-event"}"#.utf8))
            case .eventGet: return response(Data(eventJSON.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let reader = GWSReadClient(factory: factory, runner: insertRunner)
        let result = try GWSMutationService(runner: insertRunner).perform(insert, reader: reader)
        guard case .eventVerified(let verifiedEvent) = result else { throw TestFailure(description: "event create did not produce typed exact-read result") }
        try check(verifiedEvent.id == "synthetic-created-event" && result.isReadBackVerified,
                  "event create must verify the exact returned resource and expected fields")
        try check(insertRunner.invocations.map(\.operation) == [.eventInsert, .eventGet],
                  "event create must perform exact GET after the mutation")

        let taskBody = try factory.taskInsert(taskListID: "synthetic-task-list", title: "Synthetic verified task", notes: nil,
                                              due: DateOnly(rawValue: "2026-10-02"), authorization: .userSave)
        let taskRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskInsert: return response(Data(#"{"id":"synthetic-created-task"}"#.utf8))
            case .taskGet: return response(Data(#"{"id":"synthetic-created-task","title":"Synthetic verified task","due":"2026-10-02T00:00:00.000Z","status":"needsAction"}"#.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let taskReader = GWSReadClient(factory: factory, runner: taskRunner)
        let taskResult = try GWSMutationService(runner: taskRunner).perform(taskBody, reader: taskReader)
        guard case .taskVerified(let verifiedTask) = taskResult else { throw TestFailure(description: "task create did not produce typed exact-read result") }
        try check(verifiedTask.id == "synthetic-created-task" && verifiedTask.due == DateOnly(rawValue: "2026-10-02"),
                  "task create exact GET did not verify returned ID and date-only due")

        let taskListBody = try factory.taskListInsert(title: "Synthetic verified list", authorization: .userSave)
        let taskListJSON = #"{"id":"synthetic-created-list","title":"Synthetic verified list"}"#
        let taskListInsertRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskListInsert: return response(Data(#"{"id":"synthetic-created-list"}"#.utf8))
            case .taskListGet: return response(Data(taskListJSON.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let taskListReader = GWSReadClient(factory: factory, runner: taskListInsertRunner)
        let taskListResult = try GWSMutationService(runner: taskListInsertRunner).perform(taskListBody, reader: taskListReader)
        guard case .taskListVerified(let verifiedList) = taskListResult else {
            throw TestFailure(description: "task-list create did not produce typed exact-read result")
        }
        try check(verifiedList.id == "synthetic-created-list" && verifiedList.title == "Synthetic verified list" && taskListResult.isReadBackVerified,
                  "task-list create must verify the returned ID and expected title")
        try check(taskListInsertRunner.invocations.map(\.operation) == [.taskListInsert, .taskListGet],
                  "task-list create must perform an exact GET after mutation")

        let taskListPatch = try factory.taskListPatch(id: "synthetic-existing-list", title: "Synthetic renamed list", authorization: .userSave)
        let patchedListJSON = #"{"id":"synthetic-existing-list","title":"Synthetic renamed list"}"#
        let taskListPatchRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskListPatch: return response(Data(patchedListJSON.utf8))
            case .taskListGet: return response(Data(patchedListJSON.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let patchedListResult = try GWSMutationService(runner: taskListPatchRunner).perform(
            taskListPatch, reader: GWSReadClient(factory: factory, runner: taskListPatchRunner))
        guard case .taskListVerified(let patchedList) = patchedListResult else {
            throw TestFailure(description: "task-list rename did not produce typed exact-read result")
        }
        try check(patchedList.id == "synthetic-existing-list" && patchedList.title == "Synthetic renamed list",
                  "task-list rename exact GET did not verify the target identity and title")

        let taskListDelete = try factory.taskListDelete(id: "synthetic-deleted-list", authorization: .confirmedDelete)
        let taskListDeleteRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskListDelete: return response(Data())
            case .taskListGet: return response(Data(), code: 404, stderr: "404 not found")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let taskListDeleteResult = try GWSMutationService(runner: taskListDeleteRunner).perform(
            taskListDelete, reader: GWSReadClient(factory: factory, runner: taskListDeleteRunner))
        try check(taskListDeleteResult == .resourceDeleted && taskListDeleteResult.isReadBackVerified,
                  "task-list deletion must be accepted only after exact GET confirms absence")
        try check(taskListDeleteRunner.invocations.map(\.operation) == [.taskListDelete, .taskListGet],
                  "task-list deletion must perform an exact GET after mutation")

        let mismatchedRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .eventInsert: return response(Data(#"{"id":"synthetic-created-event"}"#.utf8))
            case .eventGet: return response(Data(eventJSON.replacingOccurrences(of: "Synthetic verified event", with: "Synthetic mismatch").utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSMutationService(runner: mismatchedRunner).perform(insert,
                reader: GWSReadClient(factory: factory, runner: mismatchedRunner))
            throw TestFailure(description: "mutation read-back mismatch was accepted")
        } catch let failure as GWSFailure {
            try check(failure == .mutationNotVerified, "mutation mismatch must remain an unconfirmed safe error")
        }

        let eventReadErrorRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .eventInsert: return response(Data(#"{"id":"synthetic-created-event"}"#.utf8))
            case .eventGet: return response(Data(), code: 71, stderr: "synthetic network timeout")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSMutationService(runner: eventReadErrorRunner).perform(insert,
                reader: GWSReadClient(factory: factory, runner: eventReadErrorRunner))
            throw TestFailure(description: "event exact-read failure was reported as success")
        } catch let failure as GWSFailure {
            guard case let .processFailed(operation, code, category) = failure,
                  operation == GWSOperation.eventGet.rawValue, code == 71, category == "network" else {
                throw TestFailure(description: "event exact-read failure was not preserved safely")
            }
            try check(true, "event exact-read failure is surfaced")
        }

        let mismatchedTaskRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskInsert: return response(Data(#"{"id":"synthetic-created-task"}"#.utf8))
            case .taskGet: return response(Data(#"{"id":"synthetic-created-task","title":"Synthetic mismatch","due":"2026-10-02T00:00:00.000Z","status":"needsAction"}"#.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSMutationService(runner: mismatchedTaskRunner).perform(taskBody,
                reader: GWSReadClient(factory: factory, runner: mismatchedTaskRunner))
            throw TestFailure(description: "task mutation read-back mismatch was accepted")
        } catch let failure as GWSFailure {
            try check(failure == .mutationNotVerified, "task mutation mismatch must remain unconfirmed")
        }

        let taskReadErrorRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskInsert: return response(Data(#"{"id":"synthetic-created-task"}"#.utf8))
            case .taskGet: return response(Data(), code: 72, stderr: "synthetic network timeout")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSMutationService(runner: taskReadErrorRunner).perform(taskBody,
                reader: GWSReadClient(factory: factory, runner: taskReadErrorRunner))
            throw TestFailure(description: "task exact-read failure was reported as success")
        } catch let failure as GWSFailure {
            guard case let .processFailed(operation, code, category) = failure,
                  operation == GWSOperation.taskGet.rawValue, code == 72, category == "network" else {
                throw TestFailure(description: "task exact-read failure was not preserved safely")
            }
            try check(true, "task exact-read failure is surfaced")
        }

        let listInsertWithoutReader = try factory.taskListInsert(title: "Synthetic list", authorization: .userSave)
        do {
            _ = try GWSMutationService(runner: FakeProcessRunner { _ in response(Data("{}".utf8)) }).perform(listInsertWithoutReader)
            throw TestFailure(description: "task-list mutation without exact read-back was accepted")
        } catch let failure as GWSFailure {
            try check(failure == .mutationNotVerified, "task-list mutation without an exact reader must fail closed")
        }
    }

    static func testMutationGuardsAndExactArguments() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let readOnly = CalendarInfo(id: "readonly-fixture", title: "Synthetic Read Only", accessRole: "reader", timeZoneID: "UTC", colorHex: nil)
        let writable = CalendarInfo(id: "writable-fixture", title: "Synthetic Writable", accessRole: "writer", timeZoneID: "UTC", colorHex: nil)
        let allDay = EventTime(rawValue: "2026-03-08", instant: nil, dateOnly: DateOnly(rawValue: "2026-03-08"), timeZoneID: nil)
        let event = CalendarEvent(id: "event-fixture", calendarID: writable.id, title: "Synthetic event", start: allDay, end: EventTime(rawValue: "2026-03-09", instant: nil, dateOnly: DateOnly(rawValue: "2026-03-09"), timeZoneID: nil), recurring: false, status: nil)
        try expectForbidden({ _ = try factory.eventInsert(calendar: readOnly, body: ["summary": "Synthetic"], authorization: .userSave) }, "read-only calendar insert")
        try expectForbidden({ _ = try factory.eventPatch(event: event, calendar: readOnly, body: ["summary": "Synthetic"], authorization: .userSave) }, "read-only calendar patch")
        try expectForbidden({ _ = try factory.eventDelete(event: event, calendar: writable, authorization: .userSave) }, "delete without confirmation")
        try expectForbidden({ _ = try factory.taskListDelete(id: "list-fixture-1", authorization: .cancelled) }, "cancelled list deletion")

        let due = DateOnly(rawValue: "2026-04-01")!
        let invocation = try factory.taskInsert(taskListID: "list-fixture-1", title: "Synthetic task", notes: nil, due: due, authorization: .userSave)
        try check(invocation.operation == .taskInsert, "task insertion operation mismatch")
        try check(invocation.arguments == [
            "tasks", "tasks", "insert", "--params", "{\"tasklist\":\"list-fixture-1\"}",
            "--json", "{\"due\":\"2026-04-01T00:00:00.000Z\",\"status\":\"needsAction\",\"title\":\"Synthetic task\"}"
        ], "task insert argument vector or JSON body changed")

        try expectForbidden({ _ = try factory.eventInsert(calendar: writable, body: ["summary": "Synthetic", "attendees": [["email": "fixture@example.invalid"]]], authorization: .userSave) }, "attendee/invitation payload")
    }

    static func testReminderLifecycle() async throws {
        let task = GoogleTask(id: "task-reminder-fixture", taskListID: "list-fixture", title: "Synthetic reminder task", notes: nil,
                              due: nil, completed: false, deleted: false, updated: nil)
        let store = MemoryMetadataStore()
        let scheduler = RecordingScheduler(permission: .notDetermined)
        let defaults = UserDefaults(suiteName: "g-calendar-tests-\(UUID().uuidString)")!
        let coordinator = ReminderCoordinator(store: store, scheduler: scheduler, defaults: defaults, enabledKey: "enabled")
        let firstDate = Date().addingTimeInterval(600)
        let secondDate = Date().addingTimeInterval(1_200)

        let beforeEnable = try await coordinator.saveReminder(task: task, title: task.title, at: firstDate, explicitEnableAction: false)
        try check(beforeEnable.status == .notDetermined && scheduler.permissionRequestCount == 0, "permission was requested without explicit action")
        try check(scheduler.requests.isEmpty, "reminder scheduled before notification permission enable")
        try check((await coordinator.enableAfterExplicitUserAction()).status == .authorized, "explicit reminder enable did not grant permission")
        try check(scheduler.permissionRequestCount == 1, "explicit enable should request permission once")

        _ = try await coordinator.saveReminder(task: task, title: task.title, at: firstDate, explicitEnableAction: false)
        _ = try await coordinator.saveReminder(task: task, title: task.title, at: secondDate, explicitEnableAction: false)
        try check(scheduler.requests.count == 2, "reminder schedule/reschedule did not schedule both versions")
        try check(scheduler.requests.allSatisfy { $0.identifier == ReminderIdentity.identifier(taskID: task.id) }, "reminder identifier is not deterministic")
        try check(Set(scheduler.requests.map(\.identifier)).count == 1, "rescheduling created duplicate notification identifiers")
        try check(scheduler.cancellations.count == 3, "save/reschedule must cancel the prior deterministic notification identifier")
        try check(scheduler.requests.last?.fireDate == secondDate, "reschedule did not use latest date")

        await coordinator.complete(taskID: task.id)
        try check(scheduler.cancellations.count == 4, "completion did not cancel local reminder")
        try await coordinator.delete(taskID: task.id)
        try check(scheduler.cancellations.count == 5, "deletion did not cancel local reminder")
        try check(store.metadata(for: task.id).reminderAt == nil, "deletion did not remove local reminder metadata")

        let deniedScheduler = RecordingScheduler(permission: .notDetermined, requestResult: .denied)
        let deniedDefaults = UserDefaults(suiteName: "g-calendar-tests-\(UUID().uuidString)")!
        let deniedCoordinator = ReminderCoordinator(store: MemoryMetadataStore(), scheduler: deniedScheduler, defaults: deniedDefaults, enabledKey: "enabled")
        _ = try await deniedCoordinator.saveReminder(task: task, title: task.title, at: firstDate, explicitEnableAction: false)
        try check(deniedScheduler.permissionRequestCount == 0 && deniedScheduler.requests.isEmpty, "denied state caused prompt or schedule without user action")
        try check((await deniedCoordinator.enableAfterExplicitUserAction()).status == .denied, "explicit permission denial was not returned")
        try check(deniedScheduler.permissionRequestCount == 1 && deniedScheduler.requests.isEmpty, "denied permission must not schedule notifications")
    }

    static func testNotificationAuthorizationOutcome() async throws {
        let stillUndetermined = RecordingScheduler(permission: .notDetermined, requestResult: .notDetermined)
        let falseWithoutDecision = await NotificationAuthorization.requestAfterExplicitUserAction(using: stillUndetermined)
        try check(falseWithoutDecision.status == .notDetermined && falseWithoutDecision.requestFailure == nil,
                  "a false authorization result with a not_determined read-back must not be reported as denial")
        try check(stillUndetermined.permissionRequestCount == 1,
                  "the explicit action must request authorization only once")

        let schedulerError = NotificationAuthorizationFailure(domain: "UNErrorDomain", code: 7)
        let erroredScheduler = RecordingScheduler(permission: .notDetermined, requestFailure: schedulerError)
        let failedRequest = await NotificationAuthorization.requestAfterExplicitUserAction(using: erroredScheduler)
        try check(failedRequest.status == .notDetermined && failedRequest.requestFailure == schedulerError,
                  "request errors must preserve the actual authorization read-back instead of mapping to denied")
        try check(failedRequest.userMessage.contains("UNErrorDomain") && failedRequest.userMessage.contains("not_determined"),
                  "the safe diagnostic must include only the error domain/code and actual status")

        let deniedScheduler = RecordingScheduler(permission: .notDetermined, requestResult: .denied)
        let denied = await NotificationAuthorization.requestAfterExplicitUserAction(using: deniedScheduler)
        try check(denied.status == .denied && denied.requestFailure == nil,
                  "a denied read-back must remain distinct from an authorization API error")
        try check(NotificationAuthorizationFailure(domain: "/private/account/path", code: 9).domain == "unknown",
                  "non-identifier error domains must be redacted")
    }

    static func testFullSyncRemovesRemoteDeletedReminder() async throws {
        let taskID = "synthetic-remote-deleted-task"
        let reminderDate = Date().addingTimeInterval(3_600)
        let store = MemoryMetadataStore()
        try store.set(LocalTaskMetadata(reminderAt: reminderDate, favorite: true), for: taskID)
        let scheduler = RecordingScheduler(permission: .authorized)
        let identifier = ReminderIdentity.identifier(taskID: taskID)
        try await scheduler.schedule(ReminderRequest(identifier: identifier, taskID: taskID, title: "Synthetic pending reminder", fireDate: reminderDate))
        let defaults = UserDefaults(suiteName: "g-calendar-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "enabled")
        let coordinator = ReminderCoordinator(store: store, scheduler: scheduler, defaults: defaults, enabledKey: "enabled")

        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .calendarList, .taskListsList: return response(try fixture("items-empty.json"))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let start = DateOnly(rawValue: "2026-10-01")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let end = DateOnly(rawValue: "2026-10-08")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let completedSync = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner),
                                                    cache: MemorySnapshotStore())
            .refreshCompletedFullSync(range: DateRange(start: start, endExclusive: end))
        try await coordinator.reconcile(afterSuccessfulFullSync: completedSync, now: Date())
        try check(scheduler.cancellations.contains(identifier), "successful complete sync did not cancel removed task notification")
        try check(store.metadata(for: taskID).reminderAt == nil, "successful complete sync did not remove stale local reminder metadata")
    }

    static func testLifecycleReconciliation() async throws {
        let now = Date()
        let task = GoogleTask(id: "synthetic-lifecycle-task", taskListID: "synthetic-lifecycle-list",
                              title: "Synthetic lifecycle task", notes: nil, due: nil,
                              completed: false, deleted: false, updated: nil)
        let taskFireDate = now.addingTimeInterval(3_600)
        let taskStore = MemoryMetadataStore()
        try taskStore.set(LocalTaskMetadata(reminderAt: taskFireDate, favorite: false), for: task.id)
        let taskScheduler = RecordingScheduler(permission: .authorized)
        let defaults = UserDefaults(suiteName: "g-calendar-lifecycle-\(UUID().uuidString)")!
        defaults.set(true, forKey: "enabled")
        let taskCoordinator = ReminderCoordinator(store: taskStore, scheduler: taskScheduler, defaults: defaults, enabledKey: "enabled")

        let event = syntheticTimedEvent(id: "synthetic-lifecycle-event", calendarID: "synthetic-lifecycle-calendar",
                                        start: "2026-10-02T10:00:00-04:00", end: "2026-10-02T11:00:00-04:00")
        let eventFireDate = now.addingTimeInterval(7_200)
        let eventStore = MemoryLocalEventReminderStore()
        try eventStore.set(LocalEventReminderRecord(identity: event.identity, fireDate: eventFireDate), for: event.identity)
        let eventScheduler = RecordingScheduler(permission: .authorized)
        let eventCoordinator = EventReminderCoordinator(store: eventStore, scheduler: eventScheduler)
        let exactReader = FakeExactEventReader(.success(event))
        var handledTriggers: [ReminderLifecycleTrigger] = []

        for trigger in ReminderLifecycleTrigger.allCases {
            await ReminderLifecycleReconciliation.perform(for: trigger) {
                handledTriggers.append(trigger)
                await taskCoordinator.reconcile(tasks: [task], now: now)
                await eventCoordinator.reconcile(using: exactReader, now: now)
            }
        }

        try check(handledTriggers == ReminderLifecycleTrigger.allCases,
                  "app activation and system wake must both enter the reminder reconciliation path")
        try check(taskScheduler.pendingRequests.count == 1 && taskScheduler.pendingRequests.first?.identifier == ReminderIdentity.identifier(taskID: task.id),
                  "activation/wake reconciliation must leave one task notification per stable identifier")
        try check(eventScheduler.pendingEventRequests.count == 1 &&
                  eventScheduler.pendingEventRequests.first?.identifier == EventReminderIdentity.identifier(for: event.identity),
                  "activation/wake reconciliation must leave one event notification per composite identity")
        try check(taskStore.metadata(for: task.id).reminderAt == taskFireDate && eventStore.record(for: event.identity)?.fireDate == eventFireDate,
                  "activation/wake reconciliation must preserve local reminder definitions")
    }

    static func testFailedTaskPagePreservesReminder() async throws {
        let taskID = "synthetic-task-with-pending-reminder"
        let reminderDate = Date().addingTimeInterval(3_600)
        let store = MemoryMetadataStore()
        try store.set(LocalTaskMetadata(reminderAt: reminderDate, favorite: true), for: taskID)
        let scheduler = RecordingScheduler(permission: .authorized)
        let identifier = ReminderIdentity.identifier(taskID: taskID)
        try await scheduler.schedule(ReminderRequest(identifier: identifier, taskID: taskID, title: "Synthetic pending reminder", fireDate: reminderDate))
        let defaults = UserDefaults(suiteName: "g-calendar-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "enabled")
        let coordinator = ReminderCoordinator(store: store, scheduler: scheduler, defaults: defaults, enabledKey: "enabled")
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .calendarList: return response(try fixture("calendars-page-2.json"))
            case .eventsList: return response(try fixture("items-empty.json"))
            case .taskListsList:
                let token = params(invocation)["pageToken"] as? String
                return response(try fixture(token == nil ? "tasklists-page-1.json" : "tasklists-page-2.json"))
            case .tasksList:
                if params(invocation)["pageToken"] == nil { return response(try fixture("tasks-page-1.json")) }
                return response(Data(), code: 49, stderr: "synthetic later task page failure")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let start = DateOnly(rawValue: "2026-10-01")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        let end = DateOnly(rawValue: "2026-10-08")!.startOfDay(in: TimeZone(secondsFromGMT: 0)!)!
        do {
            let completedSync = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner),
                                                        cache: MemorySnapshotStore())
                .refreshCompletedFullSync(range: DateRange(start: start, endExclusive: end))
            try await coordinator.reconcile(afterSuccessfulFullSync: completedSync, now: Date())
            throw TestFailure(description: "later page failure unexpectedly produced a complete sync snapshot")
        } catch let failure as GWSFailure {
            if case .processFailed(_, 49, _) = failure { try check(true, "later task page failure surfaced") }
            else { throw TestFailure(description: "later task page failure returned an unexpected error") }
        }
        try check(store.metadata(for: taskID).reminderAt == reminderDate, "failed partial sync cleared local reminder metadata")
        try check(scheduler.cancellations.isEmpty, "failed partial sync canceled an existing notification")
    }
}
