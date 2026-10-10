import Foundation
import Darwin
import UserNotifications
import ServiceManagement

@MainActor
final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registerCount = 0
    var unregisterCount = 0
    var fails = false
    func register() throws {
        registerCount += 1
        if fails { throw GWSFailure.permissionDenied }
        status = .requiresApproval
    }
    func unregister() async throws {
        unregisterCount += 1
        if fails { throw GWSFailure.permissionDenied }
        status = .notRegistered
    }
}

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

final class FailingMigrationMetadataStore: LocalMetadataStoring {
    let backing: MemoryMetadataStore
    let targetID: String
    private var setFailures: Int
    private var removeFailures: Int
    private let lock = NSLock()

    init(backing: MemoryMetadataStore, targetID: String, setFailures: Int, removeFailures: Int) {
        self.backing = backing
        self.targetID = targetID
        self.setFailures = setFailures
        self.removeFailures = removeFailures
    }
    func metadata(for taskID: String) -> LocalTaskMetadata { backing.metadata(for: taskID) }
    func reminderTaskIDs() -> Set<String> { backing.reminderTaskIDs() }
    func set(_ metadata: LocalTaskMetadata, for taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        if taskID == targetID && setFailures > 0 {
            setFailures -= 1
            throw TestFailure(description: "Synthetic target persistence failure")
        }
        try backing.set(metadata, for: taskID)
    }
    func remove(taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        if removeFailures > 0 {
            removeFailures -= 1
            throw TestFailure(description: "Synthetic source removal failure")
        }
        try backing.remove(taskID: taskID)
    }
}

final class RecordingScheduler: ReminderScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var currentPermission: ReminderPermission
    private var resultOfRequest: ReminderPermission
    private let requestFailure: NotificationAuthorizationFailure?
    private var scheduleFailuresRemaining: Int
    private var storedRequests: [ReminderRequest] = []
    private var storedEventRequests: [EventReminderRequest] = []
    private var pendingRequestsByID: [String: ReminderRequest] = [:]
    private var pendingEventRequestsByID: [String: EventReminderRequest] = [:]
    private var storedCancellations: [String] = []
    private var storedPermissionRequests = 0

    init(permission: ReminderPermission, requestResult: ReminderPermission = .authorized,
         requestFailure: NotificationAuthorizationFailure? = nil, scheduleFailures: Int = 0) {
        currentPermission = permission
        resultOfRequest = requestResult
        self.requestFailure = requestFailure
        scheduleFailuresRemaining = scheduleFailures
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
        try rejectFailedSchedule()
        recordSchedule(reminder)
    }

    func schedule(_ reminder: EventReminderRequest) async throws {
        recordSchedule(reminder)
    }

    private func rejectFailedSchedule() throws {
        lock.lock(); defer { lock.unlock() }
        if scheduleFailuresRemaining > 0 {
            scheduleFailuresRemaining -= 1
            throw TestFailure(description: "Synthetic scheduling failure")
        }
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
        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--journal-lock-probe" {
            do { try runJournalLockProbe(); return }
            catch { Darwin.exit(1) }
        }
        await runAsync("login-item-status-register-error-and-demo-isolation", testLoginItems)
        run("calendar-writable-sort-and-default-selection", testCalendarNavigation)
        run("optional-event-summary", testOptionalEventSummary)
        run("malformed-event-still-rejected", testMalformedEventStillRejected)
        run("file-metadata-date-round-trip", testFileMetadataRoundTrip)
        run("completion-patch-only-status", testCompletionPatchOnlyStatus)
        run("explicit-empty-notes-clears", testExplicitEmptyNotes)
        run("recoverable-write-journal-exact-recheck", testRecoverableWrites)
        run("independent-journals-preserve-pending-owner", testIndependentMutationJournals)
        run("native-synthetic-lifecycle-ledger-scope", testSyntheticLifecycle)
        run("pagination-and-model-mapping", testPaginationAndTypedMapping)
        run("process-errors-malformed-json-timeout", testErrorsAndTimeout)
        run("gws-launcher-finds-node-with-gui-path", testGWSLauncherFindsNodeWithGUIPath)
        run("cache-preserved-after-failed-page", testCachePreservedAfterLaterPageFailure)
        run("date-only-all-day-exclusive-end-dst", testDateOnlyAllDayAndDST)
        run("calendar-task-only-date-is-not-empty", testCalendarTaskOnlyDateIsNotEmpty)
        run("calendar-undated-tasks-once-and-search-scope", testCalendarUndatedTasks)
        run("task-date-filters-and-groups", testTaskFilters)
        run("all-board-columns-filtering-and-identities", testTaskBoardGroups)
        run("task-keyboard-selection-scope-and-commands", testTaskKeyboardNavigation)
        run("workspace-shortcut-defaults-persistence-conflicts-reset", testWorkspaceShortcuts)
        run("theme-srgb-text-and-control-contrast", testThemeContrast)
        run("notification-status-user-facing-copy", testNotificationStatusCopy)
        run("sync-failure-recovery-category", testSyncFailureState)
        run("local-task-projection-performance-baseline", testTaskProjectionBaseline)
        await runAsync("demo-runtime-isolated-from-cache-process-and-notifications", testDemoRuntimeIsolation)
        run("calendar-time-grid-all-day-overlap-identity", testCalendarTimeGridLayout)
        run("calendar-timed-card-policy", testCalendarTimedCardPolicy)
        run("calendar-time-grid-stress-profile", testCalendarTimeGridStress)
        run("task-layout-breakpoint-and-event-accessibility-time", testResponsiveAndAccessibilityText)
        run("refresh-coordinator-keeps-latest-range", testRefreshCoordinatorLatestRange)
        run("calendar-range-coverage-and-cache-migration", testCalendarRangeCoverageAndMigration)
        run("calendar-content-distinguishes-unknown-range", testCalendarContentState)
        run("calendar-range-refresh-skips-task-api", testCalendarRangeRefreshSkipsTaskAPI)
        run("notification-trigger-retains-subminute-precision", testNotificationTriggerPrecision)
        await runAsync("event-reminder-composite-id-dedupe-range-and-exact-removal", testEventReminderLifecycle)
        run("mutation-guards-and-exact-arguments", testMutationGuardsAndExactArguments)
        run("exact-resource-get-and-mutation-read-back", testExactResourceReadAndMutationReadback)
        await runAsync("native-task-move-exact-verification-recovery-and-metadata", testTaskMoveVerificationAndRecovery)
        await runAsync("reminder-permission-schedule-cancel-reschedule-dedup", testReminderLifecycle)
        await runAsync("verified-task-reminder-local-retry-and-denied-metadata", testVerifiedTaskReminderSave)
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

    @MainActor
    static func testLoginItems() async throws {
        let fake = FakeLoginItemService()
        let settings = LoginItemSettings(service: fake)
        settings.refresh(isNormalMode: false)
        await settings.setEnabled(true)
        try check(fake.registerCount == 0 && !settings.isAvailable, "demo must never register login items")
        settings.refresh(isNormalMode: true)
        await settings.setEnabled(true)
        try check(settings.isRegistered && settings.status == .requiresApproval && fake.registerCount == 1, "registration must expose approval state")
        await settings.setEnabled(true)
        try check(fake.registerCount == 1, "pending approval must not trigger duplicate registration")
        fake.status = .enabled
        settings.refresh(isNormalMode: true)
        try check(settings.status == .enabled, "settings must read externally changed macOS status")
        fake.fails = true
        await settings.setEnabled(false)
        try check(settings.isRegistered && settings.errorMessage != nil && !settings.isUpdating, "unregister error must retain actual status")
        fake.fails = false
        await settings.setEnabled(false)
        try check(!settings.isRegistered && settings.status == .notRegistered && settings.errorMessage == nil, "unregister success must read back disabled status")
        fake.status = .notFound
        settings.refresh(isNormalMode: true)
        try check(!settings.isRegistered && settings.statusMessage.contains("Applications"), "missing bundle must provide installation guidance")
    }

    static func testCalendarNavigation() throws {
        let reader = CalendarInfo(id: "reader", title: "А", accessRole: "reader", timeZoneID: nil, colorHex: nil)
        let owner = CalendarInfo(id: "owner", title: "Я", accessRole: "owner", timeZoneID: nil, colorHex: nil)
        let writer = CalendarInfo(id: "writer", title: "Б", accessRole: "writer", timeZoneID: nil, colorHex: nil)
        let sameTitle = CalendarInfo(id: "a", title: "Б", accessRole: "writer", timeZoneID: nil, colorHex: nil)
        try check(CalendarNavigation.sorted([reader, owner, writer, sameTitle]).map(\.id) == ["a", "writer", "owner", "reader"], "writable calendars must lead with localized name ordering and ID tie-break")
        try check(CalendarNavigation.selectedID(nil, calendars: [reader, owner]) == "owner", "missing selection must prefer writable calendar")
        try check(CalendarNavigation.selectedID("removed", calendars: [reader, writer]) == "writer", "removed calendar must fall back to writable context")
        try check(CalendarNavigation.selectedID("reader", calendars: [reader, owner]) == "reader", "explicit read-only selection must survive refresh")
        try check(CalendarNavigation.selectedID(nil, calendars: [reader]) == "reader", "read-only-only collection must remain selectable")
        try check(CalendarNavigation.selectedID("reader", calendars: []) == nil, "empty collection must clear selection")
        try check(!reader.isWritable && owner.isWritable && writer.isWritable, "Google roles must determine writable state")
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

    static func testTaskFilters() throws {
        let today = DateOnly(rawValue: "2026-10-02")!
        func task(_ id: String, due: String?, completed: Bool = false, deleted: Bool = false, list: String = "synthetic-list") -> GoogleTask {
            GoogleTask(id: id, taskListID: list, title: "Synthetic \(id)", notes: nil,
                       due: due.flatMap(DateOnly.init(rawValue:)), completed: completed, deleted: deleted, updated: nil)
        }
        let lists = [TaskList(id: "synthetic-a", title: "Synthetic A", updated: nil),
                     TaskList(id: "synthetic-b", title: "Synthetic B", updated: nil)]
        try check(TaskWorkspaceLayout.validSelectedListID("synthetic-b", lists: lists) == "synthetic-b", "refresh must retain an existing selected list")
        try check(TaskWorkspaceLayout.validSelectedListID("synthetic-removed", lists: lists) == nil, "removed board must return to all boards")
        try check(TaskWorkspaceLayout.validSelectedListID(nil, lists: lists) == nil, "refresh must preserve all-board default scope")
        try check(TaskWorkspaceLayout.validSelectedListID("synthetic-a", lists: []) == nil, "an empty refreshed collection must clear stale list context")
        try check(TaskWorkspaceLayout.isOverdue(task("past-status", due: "2026-10-01"), today: today), "past active task needs an explicit overdue status")
        try check(!TaskWorkspaceLayout.isOverdue(task("today-status", due: "2026-10-02"), today: today), "today must not be styled as overdue")
        try check(!TaskWorkspaceLayout.isOverdue(task("completed-status", due: "2026-10-01", completed: true), today: today), "completed task must not announce overdue")
        try check(!TaskWorkspaceLayout.isOverdue(task("deleted-status", due: "2026-10-01", deleted: true), today: today), "deleted task must not announce overdue")
        let tasks = [task("past", due: "2026-10-01"), task("today", due: "2026-10-02"),
                     task("future", due: "2026-10-03"), task("undated", due: nil),
                     task("completed", due: "2026-10-03", completed: true),
                     task("deleted", due: "2026-10-03", deleted: true),
                     task("other-list", due: "2026-10-03", list: "synthetic-other")]
        func filtered(_ filter: TaskWorkspaceFilter) -> [GoogleTask] {
            TaskWorkspaceLayout.filteredTasks(tasks, filter: filter, selectedTaskListID: "synthetic-list", searchText: "", today: today)
        }
        try check(filtered(.today).map(\.id) == ["today"], "Today must include only active tasks due today")
        try check(filtered(.upcoming).map(\.id) == ["future"], "Upcoming must exclude today, undated, completed, deleted and other lists")
        try check(filtered(.overdue).map(\.id) == ["past"], "Overdue must include only active past dates")
        try check(filtered(.withoutDue).map(\.id) == ["undated"], "Without due must be a separate active-task filter")
        let all = filtered(.all)
        try check(Set(all.map(\.id)) == ["past", "today", "future", "undated", "completed"], "All must retain completed tasks and enforce list/deletion scope")
        let groups = TaskWorkspaceLayout.groups(all, today: today)
        try check(groups.map { $0.1.map(\.id) } == [["past"], ["today"], ["future"], ["undated"], ["completed"]],
                  "each scoped task must occur in exactly one matching due/completion group")
        let searched = TaskWorkspaceLayout.filteredTasks(tasks, filter: .all, selectedTaskListID: "synthetic-list",
                                                        searchText: "FUTURE", today: today)
        try check(searched.map(\.id) == ["future"], "task filters must preserve case-insensitive search scope")
        try check(TaskWorkspacePresentation.defaultMode == .list, "task presentation must start as a list")
        try check(!TaskWorkspaceLayout.usesColumnBoard(presentation: .list, availableWidth: 1_600), "width must not opt a list into columns")
        try check(!TaskWorkspaceLayout.usesColumnBoard(presentation: .columns, availableWidth: 760), "explicit columns need a readable narrow fallback")
        try check(TaskWorkspaceLayout.usesColumnBoard(presentation: .columns, availableWidth: 1_600), "explicit columns must remain available on wide windows")
        let unordered = [task("later", due: "2026-10-07"), task("same-a", due: "2026-10-03"),
                         task("same-b", due: "2026-10-03"), task("undated-b", due: nil), task("undated-a", due: nil)]
        let ordered = TaskWorkspaceLayout.filteredTasks(unordered, filter: .upcoming, selectedTaskListID: "synthetic-list", searchText: "", today: today)
        try check(ordered.map(\.id) == ["same-a", "same-b", "later"], "dated views must sort by due and retain source order for equal dates")
        try check(TaskWorkspaceLayout.groups(unordered, today: today)[3].1.map(\.id) == ["undated-b", "undated-a"], "undated manual order must not change")
    }

    static func testTaskBoardGroups() throws {
        let today = DateOnly(rawValue: "2026-10-10")!
        let boards = [TaskList(id: "a", title: "Same", updated: nil), TaskList(id: "b", title: "Same", updated: nil),
                      TaskList(id: "empty", title: "Empty", updated: nil)]
        func task(_ id: String, board: String, completed: Bool = false, deleted: Bool = false) -> GoogleTask {
            GoogleTask(id: id, taskListID: board, title: "Find " + id, notes: nil, due: today,
                       completed: completed, deleted: deleted, updated: nil)
        }
        let tasks = [task("done", board: "a", completed: true), task("shared", board: "a"),
                     task("shared", board: "b"), task("deleted", board: "b", deleted: true)]
        let visible = TaskWorkspaceLayout.filteredTasks(tasks, filter: .all, selectedTaskListID: nil, searchText: "", today: today)
        let groups = TaskWorkspaceLayout.boardGroups(visible, lists: boards)
        try check(groups.map(\.id) == ["a", "b", "empty"], "board columns use IDs even with duplicate names and retain empty boards")
        try check(groups.map { $0.tasks.count } == [2, 1, 0], "each task must belong only to its board and deleted tasks are excluded")
        try check(groups[0].tasks.map(\.id) == ["shared", "done"], "active tasks precede completed tasks within a board")
        let identities = groups.flatMap(\.tasks).map(\.selectionIdentity)
        try check(Set(identities).count == 3, "same Google task ID in distinct boards retains distinct keyboard identities")
        let found = TaskWorkspaceLayout.filteredTasks(tasks, filter: .today, selectedTaskListID: nil, searchText: "SHARED", today: today)
        try check(TaskWorkspaceLayout.boardGroups(found, lists: boards).map { $0.tasks.count } == [1, 1, 0], "search and date filters must work across all boards")
        let selected = TaskWorkspaceLayout.filteredTasks(tasks, filter: .all, selectedTaskListID: "b", searchText: "", today: today)
        try check(selected.count == 1 && selected[0].taskListID == "b", "specific board scope must exclude other boards")
        try check(!TaskWorkspaceLayout.usesColumnBoard(presentation: .columns, availableWidth: 1600, selectedTaskListID: "b"), "specific board must always render a list")
        let width = TaskWorkspaceLayout.boardColumnWidth(availableWidth: 1100, boardCount: 8)
        try check(width >= 320 && width <= 420, "columns must keep readable explicit widths instead of compressing eight boards")
        let keyboard = TaskKeyboardNavigation.visibleTasks(filteredTasks: found, groups: groups.map { ("board:" + $0.id, $0.tasks) },
                                                           usesGroups: true, usesColumns: false, collapsedGroups: ["board:a"])
        try check(keyboard.map(\.taskListID) == ["b"], "narrow fallback must exclude collapsed board tasks from keyboard navigation")
    }

    static func testWorkspaceShortcuts() throws {
        let suite = "g-calendar-shortcut-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WorkspaceShortcutSettings.load(from: defaults)
        try require(settings[.toggleSidebar] == WorkspaceShortcutBinding(key: "b"), "sidebar defaults to command B")
        try require(Set(WorkspaceShortcutAction.allCases.map { settings[$0] }).count == 9, "defaults have no conflicts")
        let changed = WorkspaceShortcutBinding(key: "K", command: true, option: true)
        try require(settings.update(changed, for: .toggleSidebar) == nil, "custom shortcut accepted")
        settings.save(to: defaults)
        try require(WorkspaceShortcutSettings.load(from: defaults)[.toggleSidebar] == changed.normalized, "shortcut persists normalized")
        let beforeConflict = settings
        try require(settings.update(changed, for: .search) != nil && settings == beforeConflict, "duplicate rejected without mutation")
        for invalid in [WorkspaceShortcutBinding(key: "q"), WorkspaceShortcutBinding(key: "v"),
                        WorkspaceShortcutBinding(key: "ab"), WorkspaceShortcutBinding(key: ""),
                        WorkspaceShortcutBinding(key: "ф"), WorkspaceShortcutBinding(key: "b", command: false),
                        WorkspaceShortcutBinding(key: "b", command: false, shift: true)] {
            try require(settings.update(invalid, for: .toggleSidebar) != nil, "invalid or reserved shortcut rejected")
        }
        settings = WorkspaceShortcutSettings()
        settings.save(to: defaults)
        try require(WorkspaceShortcutSettings.load(from: defaults) == settings, "reset persists all defaults")
        defaults.set(Data("invalid".utf8), forKey: WorkspaceShortcutSettings.storageKey)
        try require(WorkspaceShortcutSettings.load(from: defaults) == WorkspaceShortcutSettings(), "malformed storage falls back safely")
        let conflicting = ["search": WorkspaceShortcutBinding(key: "b")]
        defaults.set(try JSONEncoder().encode(conflicting), forKey: WorkspaceShortcutSettings.storageKey)
        try require(WorkspaceShortcutSettings.load(from: defaults) == WorkspaceShortcutSettings(), "stored conflicts fall back safely")
    }

    static func testTaskKeyboardNavigation() throws {
        let a = GoogleTask(id: "shared-id", taskListID: "synthetic-a", title: "A", notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let b = GoogleTask(id: "shared-id", taskListID: "synthetic-b", title: "B", notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let c = GoogleTask(id: "completed", taskListID: "synthetic-a", title: "C", notes: nil, due: nil, completed: true, deleted: false, updated: nil)
        let ids = [a, b, c].map(\.selectionIdentity)
        try check(a.selectionIdentity != b.selectionIdentity, "selection must include list ID even when Google IDs overlap")
        try check(TaskKeyboardNavigation.command(keyCode: 126, hasModifiers: false, isRepeat: true) == .previous, "held arrows may navigate")
        try check(TaskKeyboardNavigation.command(keyCode: 125, hasModifiers: false, isRepeat: false) == .next, "down selects the next visible item")
        try check(TaskKeyboardNavigation.command(keyCode: 36, hasModifiers: false, isRepeat: false) == .edit, "Return opens the selected task")
        try check(TaskKeyboardNavigation.command(keyCode: 76, hasModifiers: false, isRepeat: false) == .edit, "keypad Return also opens the task")
        try check(TaskKeyboardNavigation.command(keyCode: 49, hasModifiers: false, isRepeat: false) == .toggleCompletion, "Space toggles the selected task")
        try check([36, 76, 49].allSatisfy { TaskKeyboardNavigation.command(keyCode: UInt16($0), hasModifiers: false, isRepeat: true) == nil }, "holding action keys must not repeat edits or writes")
        try check([126, 125, 36, 49].allSatisfy { TaskKeyboardNavigation.command(keyCode: UInt16($0), hasModifiers: true, isRepeat: false) == nil }, "modified keys stay in the responder chain")
        try check(TaskKeyboardNavigation.command(keyCode: 48, hasModifiers: false, isRepeat: false) == nil, "Tab remains native focus navigation")
        try check(TaskKeyboardNavigation.movedSelection(nil, in: ids, command: .next) == ids.first, "down enters at the first task")
        try check(TaskKeyboardNavigation.movedSelection(nil, in: ids, command: .previous) == ids.last, "up enters at the last task")
        try check(TaskKeyboardNavigation.movedSelection(ids[0], in: ids, command: .previous) == ids[0], "selection must stop at the start")
        try check(TaskKeyboardNavigation.movedSelection(ids[2], in: ids, command: .next) == ids[2], "selection must stop at the end")
        try check(TaskKeyboardNavigation.movedSelection(ids[0], in: ids, command: .next) == ids[1], "navigation must follow visible order")
        try check(TaskKeyboardNavigation.movedSelection(ids[0], in: [], command: .next) == nil, "empty results clear selection")
        try check(TaskKeyboardNavigation.reconciledSelection(ids[1], previous: ids, visible: [ids[0], ids[2]]) == ids[2], "a removed selection moves to the same visible position")
        try check(TaskKeyboardNavigation.reconciledSelection(ids[2], previous: ids, visible: [ids[0]]) == ids[0], "selection clamps after filtering")
        try check(TaskKeyboardNavigation.reconciledSelection(nil, previous: ids, visible: ids) == nil, "refresh must not select a task without user focus")
        let groups = [("Без срока", [a, b]), ("Готово", [c])]
        let list = TaskKeyboardNavigation.visibleTasks(filteredTasks: [a, b, c], groups: groups, usesGroups: true, usesColumns: false, collapsedGroups: ["Готово"])
        try check(list.map(\.selectionIdentity) == Array(ids.prefix(2)), "keyboard navigation excludes collapsed list rows")
        let columns = TaskKeyboardNavigation.visibleTasks(filteredTasks: [a, b, c], groups: groups, usesGroups: true, usesColumns: true, collapsedGroups: ["Готово"])
        try check(columns.map(\.selectionIdentity) == ids, "visible column tasks remain navigable regardless of list collapse state")
        let filtered = TaskKeyboardNavigation.visibleTasks(filteredTasks: [b], groups: groups, usesGroups: false, usesColumns: true, collapsedGroups: [])
        try check(filtered == [b], "a filter must not leak tasks from other groups into navigation")
    }

    static func testThemeContrast() throws {
        let black = ThemePalette.RGB(hex: 0x000000), white = ThemePalette.RGB(hex: 0xFFFFFF)
        try check(abs(black.contrast(against: white) - 21) < 0.00001, "black/white contrast must be 21:1")
        try check(white.contrast(against: white) == 1, "equal colors have 1:1 contrast")
        try check(black.blended(over: white, opacity: 0) == white && black.blended(over: white, opacity: 1) == black, "alpha endpoints must use the actual foreground/background")
        let textRoles: [ThemePalette.Role] = [.textPrimary, .textSecondary, .accent, .task, .overdue, .success, .warning]
        let backgrounds: [ThemePalette.Role] = [.surface, .surfaceRaised, .canvas, .selection]
        for dark in [false, true] {
            for role in textRoles {
                for background in backgrounds {
                    let ratio = ThemePalette.color(role, dark: dark).contrast(against: ThemePalette.color(background, dark: dark))
                    try check(ratio >= 4.5, "\(role) text on \(background), dark=\(dark), contrast \(ratio) must meet 4.5:1 without rounding")
                }
            }
            for background in backgrounds {
                try check(ThemePalette.color(.outline, dark: dark).contrast(against: ThemePalette.color(background, dark: dark)) >= 3,
                          "outline/control boundary must meet 3:1 against \(background), dark=\(dark)")
            }
            for opacity in [0.55, 0.65] {
                let selected = ThemePalette.color(.selection, dark: dark).blended(over: ThemePalette.color(.surface, dark: dark), opacity: opacity)
                for role in textRoles {
                    try check(ThemePalette.color(role, dark: dark).contrast(against: selected) >= 4.5,
                              "\(role) must stay readable on actual translucent selected rows/badges, dark=\(dark)")
                }
            }
        }
        try check(white.contrast(against: ThemePalette.color(.accent, dark: false)) >= 4.5, "light primary blue supports white action text")
        // Google supplies arbitrary calendar colors: one tint over surface, primary ink.
        for dark in [false, true] {
            for hex: UInt32 in [0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0xB2EBF2, 0x0B57D0, 0x188038, 0x7986CB, 0x33B679, 0x8E24AA, 0xE67C73, 0xF6BF26, 0xF4511E, 0x039BE5, 0x616161, 0x3F51B5, 0x0B8043, 0xD50000] {
                let tint = ThemePalette.RGB(hex: hex)
                let outer = tint.blended(over: ThemePalette.color(.surface, dark: dark), opacity: 0.16)
                try check(ThemePalette.color(.textPrimary, dark: dark).contrast(against: outer) >= 4.5,
                          "event title must remain readable over the single calendar tint layer, dark=\(dark)")
            }
        }
    }

    static func testNotificationStatusCopy() throws {
        for access in ["authorized", "denied", "not_determined", "provisional", "ephemeral", "synthetic-unrecognized"] {
            let status = NotificationRuntimeStatus(authorization: access, pendingCount: 2, deliveredCount: 3,
                                                  alertSetting: "enabled", soundSetting: "disabled", foregroundDelegateReady: true)
            let copy = status.userFacingLines.joined(separator: " ")
            try check(!copy.contains(access) && !copy.contains("foreground") && !copy.contains("delegate"), "settings must explain notification state without raw API/debug identifiers")
            try check(copy.contains("Ожидают доставки: 2") && copy.contains("в Центре уведомлений: 3"), "user-facing counts must distinguish scheduled from delivered notifications")
            try check(status.safeSummary.contains("authorization=\(access)") && status.safeSummary.contains("foreground_delegate_ready=true"), "CLI diagnostic summary must retain exact machine-readable status")
        }
        for (style, expected) in [("alert", "остаются до закрытия"), ("banner", "закрываются автоматически"),
                                  ("none", "без всплывающих"), ("not_queried", "ещё не проверен"), ("unknown", "неизвестен")] {
            let status = NotificationRuntimeStatus(authorization: "authorized", pendingCount: 0, deliveredCount: 0,
                                                  alertSetting: "enabled", soundSetting: "enabled", foregroundDelegateReady: true,
                                                  alertStyle: style)
            try check(status.alertStyleMessage.contains(expected) && status.safeSummary.contains("alert_style=\(style)"),
                      "notification style must explain actual system persistence")
        }
        let unavailable = NotificationRuntimeStatus(authorization: "unknown", pendingCount: 0, deliveredCount: 0,
                                                   alertSetting: "not_supported", soundSetting: "not_queried", foregroundDelegateReady: false)
        try check(unavailable.userFacingLines[1].contains("недоступен") && unavailable.userFacingLines[1].contains("ещё не проверен"), "unsupported and unqueried settings must be distinct")
    }

    static func testSyncFailureState() throws {
        try check(WorkspaceSyncState.afterFailure(.executableUnavailable) == .setupRequired, "missing executable must offer setup")
        try check(WorkspaceSyncState.afterFailure(.processFailed("synthetic", 1, "auth_or_permission")) == .setupRequired, "auth failure must offer setup")
        try check(WorkspaceSyncState.afterFailure(.processFailed("synthetic", 1, "network")) == .offline, "network failure must be distinct from setup")
        try check(WorkspaceSyncState.afterFailure(.invalidResponse("synthetic")) == .failed, "invalid response must offer retry without claiming offline")
        try check(WorkspaceSyncState.afterFailure(.timedOut("synthetic")) == .failed, "timeout alone must not claim missing configuration")
    }

    static func testTaskProjectionBaseline() throws {
        let today = DateOnly(rawValue: "2026-06-15")!
        let tasks = (0..<4_096).map { index in
            GoogleTask(id: "synthetic-perf-\(index)", taskListID: "synthetic-list-\(index % 4)",
                       title: "Synthetic task \(index)", notes: nil,
                       due: index.isMultiple(of: 17) ? nil : DateOnly(year: 2026, month: 6, day: index % 30 + 1),
                       completed: index.isMultiple(of: 5), deleted: false, updated: nil)
        }
        var filtered: [GoogleTask] = []
        let filtering = measuredSamples {
            filtered = TaskWorkspaceLayout.filteredTasks(tasks, filter: .upcoming, selectedTaskListID: "synthetic-list-1",
                                                         searchText: "task 1", today: today)
        }
        try check(!filtered.isEmpty && filtered.allSatisfy { !$0.completed && $0.due.map { $0 > today } == true },
                  "performance fixture must exercise a nonempty active future search")
        var grouped: [(String, [GoogleTask])] = []
        let projection = measuredSamples {
            grouped = TaskWorkspaceLayout.groups(tasks, today: today)
        }
        try check(grouped.flatMap { $0.1 }.count == tasks.count, "projection baseline must retain all fixture rows exactly once")
        print(String(format: "PERF task_upcoming_search items=4096 samples=9 p50_ms=%.3f p95_ms=%.3f", filtering.0, filtering.1))
        print(String(format: "PERF task_groups items=4096 samples=9 p50_ms=%.3f p95_ms=%.3f", projection.0, projection.1))
    }

    static func measuredSamples(_ operation: () -> Void) -> (Double, Double) {
        operation()
        let samples = (0..<9).map { _ -> Double in
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }.sorted()
        return (samples[4], samples[8])
    }

    static func testDemoRuntimeIsolation() async throws {
        try expectForbidden({ _ = try SyntheticLedgerAcceptanceSession.explicitLedgerURL(arguments: ["g-calendar", "--ledger-acceptance"]) }, "implicit historical acceptance ledger")
        try expectForbidden({ _ = try SyntheticLedgerAcceptanceSession.explicitLedgerURL(arguments: ["g-calendar", "--acceptance-ledger", "relative.json"]) }, "relative acceptance ledger")
        try expectForbidden({ _ = try SyntheticLedgerAcceptanceSession.explicitLedgerURL(arguments: ["g-calendar", "--acceptance-ledger", "/private/tmp/one.json", "--acceptance-ledger", "/private/tmp/two.json"]) }, "ambiguous acceptance ledger")
        try check(try SyntheticLedgerAcceptanceSession.explicitLedgerURL(arguments: ["g-calendar", "--acceptance-ledger", "/private/tmp/synthetic-ledger.json"]).path == "/private/tmp/synthetic-ledger.json", "acceptance must use only the explicitly selected ledger")
        try check(AppLaunchMode.parse(arguments: ["g-calendar", "--demo"]) == .demo, "--demo launch flag was not parsed")
        try check(AppLaunchMode.parse(arguments: ["g-calendar", "--notification-status"]) == .notificationStatus,
                  "--notification-status launch flag was not parsed")
        try check(AppLaunchMode.parse(arguments: ["g-calendar", "--notification-test"]) == .notificationTest,
                  "notification test must require its own explicit launch flag")
        let allowedNotifications = RecordingScheduler(permission: .authorized)
        let testNow = Date(timeIntervalSince1970: 1_800_000_000)
        let notification = try await NotificationAcceptance.scheduleOneTest(using: allowedNotifications, now: testNow)
        try check(allowedNotifications.requests == [notification] && notification.identifier.hasPrefix("g-calendar.acceptance.") && notification.fireDate == testNow.addingTimeInterval(3),
                  "notification acceptance must schedule exactly one isolated synthetic request")
        let deniedNotifications = RecordingScheduler(permission: .denied)
        do {
            _ = try await NotificationAcceptance.scheduleOneTest(using: deniedNotifications, now: testNow)
            throw TestFailure(description: "unauthorized notification test scheduled")
        } catch let failure as GWSFailure {
            try check(failure == .forbiddenOperation && deniedNotifications.requests.isEmpty && deniedNotifications.permissionRequestCount == 0,
                      "notification test must never prompt or schedule when authorization is absent")
        }
        var liveFactoryCalled = false
        let demoRunner = RuntimeProcessBoundary.runner(for: .demo) {
            liveFactoryCalled = true
            return FakeProcessRunner { _ in throw GWSFailure.forbiddenOperation }
        }
        let statusRunner = RuntimeProcessBoundary.runner(for: .notificationStatus) {
            liveFactoryCalled = true
            return FakeProcessRunner { _ in throw GWSFailure.forbiddenOperation }
        }
        let notificationRunner = RuntimeProcessBoundary.runner(for: .notificationTest) {
            liveFactoryCalled = true
            return FakeProcessRunner { _ in throw GWSFailure.forbiddenOperation }
        }
        try check(notificationRunner == nil, "notification test must not construct a Google runner")
        let demoRunnerUnavailable: Bool
        if case nil = demoRunner { demoRunnerUnavailable = true } else { demoRunnerUnavailable = false }
        let statusRunnerUnavailable: Bool
        if case nil = statusRunner { statusRunnerUnavailable = true } else { statusRunnerUnavailable = false }
        let adapter = DemoWorkspaceAdapter(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
        let snapshot = adapter.snapshot()
        try check(demoRunnerUnavailable && statusRunnerUnavailable && !liveFactoryCalled,
                  "isolated modes constructed a live Google process runner")
        try check(snapshot.calendars.map(\.id) == ["demo-calendar", "demo-readonly-calendar"] && snapshot.events.first?.id == "demo-event" &&
                  snapshot.tasks.contains(where: { $0.id == "demo-task-undated" }) && snapshot.tasks.count >= 50 &&
                  snapshot.tasks.allSatisfy({ $0.id.hasPrefix("demo-task-") }) && snapshot.calendarCoverage != nil,
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
        try check(CalendarGridLayout.columnWidth(isDayView: true, availableWidth: 640) == 586,
                  "day grid, shared time axis, and spacing must use the available detail width")
        try check(CalendarGridLayout.columnWidth(isDayView: true, availableWidth: 120) == CalendarGridLayout.minimumColumnWidth,
                  "day grid must retain its minimum readable width in a narrow viewport")
        let wideWeekColumnWidth = CalendarGridLayout.columnWidth(isDayView: false, availableWidth: 1_400)
        try check(wideWeekColumnWidth > CalendarGridLayout.minimumWeekColumnWidth && wideWeekColumnWidth < 220,
                  "wide week columns must expand toward the available width without exceeding it")
        try check(wideWeekColumnWidth * 7 + CalendarGridLayout.timeAxisWidth + 70 <= 1_400,
                  "seven adaptive day columns, shared axis and spacing must fit a wide viewport")
        try check(CalendarGridLayout.columnWidth(isDayView: false, availableWidth: 800) == CalendarGridLayout.minimumWeekColumnWidth,
                  "week columns must preserve a readable minimum and allow horizontal navigation on narrow windows")
        try check(CalendarGridLayout.dateOnlyRegionHeight == 116,
                  "date-only regions must have a shared bounded height across calendar days")
        try check(CalendarGridLayout.dateOnlyHeight(maximumItemCount: 0) == 0, "empty date-only rows must reserve no blank panel")
        try check(CalendarGridLayout.dateOnlyHeight(maximumItemCount: 1) == 62, "one date-only item needs a compact readable region")
        try check(CalendarGridLayout.dateOnlyHeight(maximumItemCount: 1_000) == 116, "large date-only content must stay bounded and scrollable")
        let event = syntheticTimedEvent(id: "synthetic-accessibility-event", calendarID: "synthetic-calendar",
                                        start: "2026-10-02T09:00:00-04:00", end: "2026-10-02T10:00:00-04:00")
        try check(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: TimeZone(secondsFromGMT: 0)!) == "09:00–10:00",
                  "event accessibility time must use the event calendar time zone, not system time zone")
    }

    static func testRefreshCoordinatorLatestRange() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        let rangeA = try DateRange(start: start, endExclusive: start.addingTimeInterval(day), timeZone: zone)
        let rangeB = try DateRange(start: start.addingTimeInterval(day), endExclusive: start.addingTimeInterval(2 * day), timeZone: zone)
        let rangeC = try DateRange(start: start.addingTimeInterval(2 * day), endExclusive: start.addingTimeInterval(3 * day), timeZone: zone)

        var coordinator = LatestWinsRefreshCoordinator<DateRange>()
        let requestA = coordinator.request(rangeA)!
        _ = coordinator.request(rangeB)
        _ = coordinator.request(rangeC)
        let requestC: RefreshTicket<DateRange>
        switch coordinator.finish(requestA) {
        case .superseded(let latest): requestC = latest
        case .accepted: throw TestFailure(description: "A→B→C refresh accepted stale range A instead of queuing C")
        case .ignored: throw TestFailure(description: "active range A was unexpectedly ignored")
        }
        try check(requestC.key == rangeC, "refresh coordinator must coalesce navigation to the latest range")
        if case .ignored = coordinator.finish(requestA) { try check(true, "stale completion ignored") }
        else { throw TestFailure(description: "duplicate completion for stale request A was accepted") }
        if case .accepted = coordinator.finish(requestC) { try check(true, "latest range accepted") }
        else { throw TestFailure(description: "latest range completion was not accepted") }

        var returnedToActiveRange = LatestWinsRefreshCoordinator<DateRange>()
        let activeA = returnedToActiveRange.request(rangeA)!
        _ = returnedToActiveRange.request(rangeB)
        _ = returnedToActiveRange.request(rangeA)
        if case .accepted = returnedToActiveRange.finish(activeA) { try check(true, "return to active range cancels obsolete pending navigation") }
        else { throw TestFailure(description: "returning to active range queued an unnecessary refresh") }

        var scopedCoordinator = LatestWinsRefreshCoordinator<WorkspaceRefreshQuery>()
        let fullA = scopedCoordinator.request(WorkspaceRefreshQuery(range: rangeA, scope: .full))!
        _ = scopedCoordinator.request(WorkspaceRefreshQuery(range: rangeB, scope: .calendarRange))
        _ = scopedCoordinator.request(WorkspaceRefreshQuery(range: rangeC, scope: .calendarRange))
        guard case .superseded(let latest) = scopedCoordinator.finish(fullA) else {
            throw TestFailure(description: "full sync did not yield to the latest calendar-range query")
        }
        try check(latest.key.range == rangeC && latest.key.scope == .calendarRange,
                  "latest-wins must preserve both final range and resource scope")
        try check(WorkspaceRefreshScope.afterVerifiedMutation(.eventPatch) == .calendarRange,
                  "verified event mutations must select calendar-only refresh")
        try check(WorkspaceRefreshScope.afterVerifiedMutation(.taskPatch) == .tasks,
                  "verified Tasks mutations must select Tasks-only refresh")
        try check(WorkspaceRefreshScope.afterVerifiedMutation(.calendarList) == nil,
                  "non-mutation operations must not select a mutation refresh scope")

        var forcedSameRange = LatestWinsRefreshCoordinator<WorkspaceRefreshQuery>()
        let activeRange = forcedSameRange.request(WorkspaceRefreshQuery(range: rangeA, scope: .calendarRange))!
        let postMutationRead = WorkspaceRefreshQuery(range: rangeA, scope: .calendarRange, requestID: 1)
        _ = forcedSameRange.request(postMutationRead)
        guard case .superseded(let forced) = forcedSameRange.finish(activeRange) else {
            throw TestFailure(description: "a post-mutation read-back refresh was dropped behind an in-flight same-range query")
        }
        try check(forced.key == postMutationRead,
                  "forced refresh identity must preserve a same-range mutation refresh request")
    }

    static func testCalendarRangeCoverageAndMigration() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = DateOnly(rawValue: "2026-10-05")!.startOfDay(in: zone)!
        let end = DateOnly(rawValue: "2026-10-12")!.startOfDay(in: zone)!
        let loadedRange = try DateRange(start: start, endExclusive: end, timeZone: zone)
        let coverage = CalendarRangeCoverage(range: loadedRange)
        let containedRange = try DateRange(start: start.addingTimeInterval(86_400),
                                           endExclusive: end.addingTimeInterval(-86_400), timeZone: zone)
        let adjacentRange = try DateRange(start: end, endExclusive: end.addingTimeInterval(86_400), timeZone: zone)
        let sameInstantsDifferentZone = try DateRange(start: start, endExclusive: end, timeZone: TimeZone(secondsFromGMT: 0)!)
        try check(coverage.covers(loadedRange) && coverage.covers(containedRange),
                  "calendar coverage must include its exact range and contained day ranges")
        try check(!coverage.covers(adjacentRange) && !coverage.covers(sameInstantsDifferentZone),
                  "calendar coverage must reject adjacent dates and mismatched time zones")

        var snapshot = WorkspaceSnapshot(calendars: [], events: [], taskLists: [], tasks: [], fetchedAt: start)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedObject = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        var legacyObject = encodedObject
        legacyObject.removeValue(forKey: "calendarCoverage")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        try check(migrated.calendarCoverage == nil,
                  "legacy snapshots without range coverage must decode as unknown, not empty coverage")

        snapshot.calendarCoverage = coverage
        let roundTrip = try decoder.decode(WorkspaceSnapshot.self, from: encoder.encode(snapshot))
        try check(roundTrip.calendarCoverage == coverage,
                  "calendar range coverage must survive a snapshot cache round trip")
    }

    static func testCalendarContentState() throws {
        let unknown = CalendarContentAvailability.state(events: [], tasks: [], rangeCovered: false, hasSearch: false)
        let empty = CalendarContentAvailability.state(events: [], tasks: [], rangeCovered: true, hasSearch: false)
        let incompleteSearch = CalendarContentAvailability.state(events: [], tasks: [], rangeCovered: false, hasSearch: true)
        let noResults = CalendarContentAvailability.state(events: [], tasks: [], rangeCovered: true, hasSearch: true)
        let task = GoogleTask(id: "synthetic-content-state-task", taskListID: "synthetic-list", title: "Synthetic task",
                              notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let content = CalendarContentAvailability.state(events: [], tasks: [task], rangeCovered: false, hasSearch: false)
        try check(unknown == .unknownRange, "unknown event coverage must not be labeled as a verified empty calendar")
        try check(empty == .emptyRange, "a covered range with no events/tasks must be identified as truly empty")
        try check(incompleteSearch == .unknownRange,
                  "a no-match query over an uncovered range must not be presented as a definitive search result")
        try check(noResults == .noResults, "search no-match state must stay distinct from a verified empty range")
        try check(content == .hasContent, "known tasks must remain visible while event-range coverage is incomplete")
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
        let springMarks = CalendarTimeGridLayout.hourMarks(
            for: CalendarTimeGridLayout.dayInterval(containing: springDay, timeZone: zone)!,
            timeZone: zone
        )
        let fallMarks = CalendarTimeGridLayout.hourMarks(
            for: CalendarTimeGridLayout.dayInterval(containing: fallDay, timeZone: zone)!,
            timeZone: zone
        )
        try check(springMarks.count == 23 && !springMarks.contains(where: { $0.localHour == 2 }),
                  "spring shared axis must omit the nonexistent local hour")
        try check(fallMarks.filter { $0.localHour == 1 }.count == 2 &&
                  Set(fallMarks.filter { $0.localHour == 1 }.map(\.label)).count == 2,
                  "fall shared axis must distinguish both repeated local hours")
    }

    static func testCalendarTimedCardPolicy() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let day = DateOnly(rawValue: "2026-10-08")!.startOfDay(in: zone)!
        func event(_ id: String, _ minute: Double, calendarID: String = "a") -> CalendarEvent {
            let start = day.addingTimeInterval(minute * 60)
            let end = start.addingTimeInterval(5 * 60)
            return syntheticTimedEvent(id: id, calendarID: calendarID, start: ISO8601.format(start), end: ISO8601.format(end))
        }
        let events = [event("same", 600), event("same", 610, calendarID: "b"), event("boundary", 630)]
        for minimum in [24.0, 32.0, 48.0] {
            let placements = CalendarTimeGridLayout.timedPlacements(events, on: day, timeZone: zone, minimumEventHeight: minimum)
            try check(placements[0].laneIndex != placements[1].laneIndex, "nearby short cards reserve different lanes")
            try check(placements[0].durationMinutes == 5 && placements[1].startOffsetMinutes == 610, "visual height never changes actual placement duration/start")
            try check(placements == CalendarTimeGridLayout.timedPlacements(Array(events.reversed()), on: day, timeZone: zone, minimumEventHeight: minimum), "permutations and composite identities are deterministic")
            try check((placements[0].laneIndex == placements[2].laneIndex) == (minimum == 24), "lane reuse at exactly 30 minutes depends on shared minimum")
            let exact = [event("first", 600), event("second", 600 + minimum / CalendarGridLayout.pointsPerMinute)]
            let boundary = CalendarTimeGridLayout.timedPlacements(exact, on: day, timeZone: zone, minimumEventHeight: minimum)
            try check(boundary.allSatisfy { $0.laneIndex == 0 && $0.laneCount == 1 }, "custom minimum releases lane at exact visual boundary")
            let late = CalendarTimeGridLayout.timedPlacements([event("late", 1435)], on: day, timeZone: zone, minimumEventHeight: minimum)[0]
            let visibleEnd = late.startOffsetMinutes * CalendarGridLayout.pointsPerMinute + CalendarTimedCardLayout.displayHeight(durationMinutes: late.durationMinutes, minimumHeight: minimum)
            try check(late.startOffsetMinutes == 1435 && late.durationMinutes == 5 && visibleEnd <= 1440 * CalendarGridLayout.pointsPerMinute + CalendarTimedCardLayout.bottomPadding(minimumHeight: minimum), "shared bottom padding contains end-day card without shifting start")
        }
        let nearBoundary = CalendarTimeGridLayout.timedPlacements([event("early", 600), event("near-boundary", 625)], on: day, timeZone: zone)
        try check(nearBoundary[0].laneIndex != nearBoundary[1].laneIndex, "25-minute separation must reserve the 24pt card; legacy 18pt would release too early")
        let policy = CalendarTimedCardLayout()
        for height in [24.0, 39, 40, 55, 56, 96] {
            let budget = policy.contentBudget(height: height)
            try check(budget.titleLines == (height >= 40 ? 2 : 1) && budget.showsTime == (height >= 56), "boundary content budgets are title-first")
        }
        let grown = CalendarTimedCardLayout(titleLineHeight: 28, timeLineHeight: 24)
        try check(grown.minimumHeight == 34 && grown.twoLineThreshold == 62 && grown.timeThreshold == 88, "font growth raises all shared line budgets")
        try check(CalendarTimedCardLayout.displayHeight(durationMinutes: 1) == 24 && CalendarTimedCardLayout.displayHeight(durationMinutes: 120) == 96, "display height retains scale and default minimum")
    }

    static func testCalendarTimeGridStress() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let date = DateOnly(rawValue: "2026-06-01")!
        let day = date.startOfDay(in: zone)!
        let eventCount = 1_024
        let events = (0..<eventCount).map { index in
            syntheticTimedEvent(id: "stress-event-\(index)", calendarID: "stress-calendar",
                                start: "2026-06-01T09:00:00Z", end: "2026-06-01T10:00:00Z")
        }

        let startedAt = Date.timeIntervalSinceReferenceDate
        let placements = CalendarTimeGridLayout.timedPlacements(events, on: day, timeZone: zone)
        let elapsedMilliseconds = (Date.timeIntervalSinceReferenceDate - startedAt) * 1_000

        try check(placements == CalendarTimeGridLayout.timedPlacements(Array(events.reversed()), on: day, timeZone: zone), "stress layout remains deterministic under permutation")
        try check(placements.count == eventCount && Set(placements.map(\.identity)).count == eventCount,
                  "stress overlap layout must retain each distinct event exactly once")
        try check(Set(placements.map(\.laneIndex)).count == eventCount && placements.allSatisfy({ $0.laneCount == eventCount }),
                  "fully overlapping stress events must receive separate lanes without obscuring one another")
        print(String(format: "PERF calendar_overlap events=%d elapsed_ms=%.2f", eventCount, elapsedMilliseconds))
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

        var fractionalBody = body
        fractionalBody["start"] = ["dateTime": "2026-10-02T13:00:00.332+03:00", "timeZone": "UTC"]
        fractionalBody["end"] = ["dateTime": "2026-10-02T14:00:00.332+03:00", "timeZone": "UTC"]
        let canonicalInsert = try factory.eventInsert(calendar: calendar, body: fractionalBody, authorization: .userSave)
        let canonicalBody = try Self.jsonBody(canonicalInsert)
        try check((canonicalBody["start"] as? [String: Any])?["dateTime"] as? String == "2026-10-02T10:00:00Z" &&
                  (canonicalBody["end"] as? [String: Any])?["dateTime"] as? String == "2026-10-02T11:00:00Z",
                  "event draft must use second precision before journaling, preserving absolute instants")
        try check(try GWSMutationService(runner: insertRunner).perform(canonicalInsert, reader: reader).isReadBackVerified,
                  "Google's second-precision read-back must verify the canonical event draft")
        let canonicalPatch = try factory.eventPatch(event: verifiedEvent, calendar: calendar, body: fractionalBody, authorization: .userSave)
        try check(try Self.jsonBody(canonicalPatch) as NSDictionary == canonicalBody as NSDictionary,
                  "event create and edit must apply the same precision policy")
        let shiftedRunner = FakeProcessRunner { input in
            if input.operation == .eventInsert { return response(Data(#"{"id":"synthetic-created-event"}"#.utf8)) }
            return response(Data(eventJSON.replacingOccurrences(of: "10:00:00Z", with: "10:00:01Z").utf8))
        }
        do {
            _ = try GWSMutationService(runner: shiftedRunner).perform(canonicalInsert, reader: GWSReadClient(factory: factory, runner: shiftedRunner))
            throw TestFailure(description: "whole-second mismatch accepted")
        } catch let failure as GWSFailure {
            try check(failure == .mutationNotVerified, "canonicalization must not weaken exact instant verification")
        }
        let eventDeletion = try factory.eventDelete(event: verifiedEvent, calendar: calendar, authorization: .confirmedDelete)
        for id in [verifiedEvent.id, "synthetic-foreign-event"] {
            let cancelledRunner = FakeProcessRunner { input in
                if input.operation == .eventDelete { return response(Data()) }
                return response(try JSONSerialization.data(withJSONObject: ["id": id, "status": "cancelled"]))
            }
            do {
                let outcome = try GWSMutationService(runner: cancelledRunner).perform(eventDeletion, reader: GWSReadClient(factory: factory, runner: cancelledRunner))
                try check(id == verifiedEvent.id && outcome == .resourceDeleted, "sparse cancelled event must prove exact deletion without requiring times")
            } catch let failure as GWSFailure {
                try check(id != verifiedEvent.id && failure == .invalidResponse("event_identity"), "foreign cancelled event must not prove deletion")
            }
        }

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

        let emptyNotesInsert = try factory.taskInsert(taskListID: "synthetic-task-list", title: "Synthetic verified task", notes: "",
                                                      due: DateOnly(rawValue: "2026-10-02"), authorization: .userSave)
        let emptyNotesResult = try GWSMutationService(runner: taskRunner).perform(emptyNotesInsert, reader: taskReader)
        try check(emptyNotesResult.isReadBackVerified, "omitted Google notes must verify an explicitly empty notes draft")

        let deletion = try factory.taskDelete(task: verifiedTask, authorization: .confirmedDelete)
        for (id, deleted) in [(verifiedTask.id, true), (verifiedTask.id, false), ("synthetic-other-task", true)] {
            let tombstoneRunner = FakeProcessRunner { input in
                if input.operation == .taskDelete { return response(Data()) }
                return response(try JSONSerialization.data(withJSONObject: ["id": id, "title": "Synthetic", "deleted": deleted, "status": "needsAction"]))
            }
            do {
                let outcome = try GWSMutationService(runner: tombstoneRunner).perform(deletion, reader: GWSReadClient(factory: factory, runner: tombstoneRunner))
                try check(id == verifiedTask.id && deleted && outcome == .resourceDeleted,
                          "only the exact task deletion tombstone may confirm deletion")
            } catch let failure as GWSFailure {
                try check((id != verifiedTask.id && failure == .invalidResponse("task_identity")) || (!deleted && failure == .mutationNotVerified),
                          "active task or wrong-identity tombstone must not confirm deletion")
            }
        }

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
        for (code, message, expectedMissing) in [(404, "Not Found", true), (410, "Gone", true), (401, "Resource synthetic404 permission denied", false)] {
            let errorRunner = FakeProcessRunner { input in
                if input.operation == .taskListDelete { return response(Data()) }
                return response(try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message]]), code: 1)
            }
            do {
                let outcome = try GWSMutationService(runner: errorRunner).perform(taskListDelete, reader: GWSReadClient(factory: factory, runner: errorRunner))
                try check(expectedMissing && outcome == .resourceDeleted, "structured exact 404/410 must prove deletion")
            } catch let failure as GWSFailure {
                if case .processFailed = failure { try check(!expectedMissing, "an identifier containing 404 must not prove deletion after an auth error") }
                else { throw failure }
            }
        }

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

    static func testRecoverableWrites() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let insert = try factory.taskInsert(taskListID: "synthetic-list", title: "Synthetic pending", notes: "", due: nil, authorization: .userSave)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("g-calendar-journal-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("pending.json")
        let journal = MutationJournal(fileURL: file)
        var readsFail = true
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskInsert: return response(Data(#"{"id":"synthetic-created"}"#.utf8))
            case .taskGet:
                if readsFail { throw GWSFailure.timedOut("synthetic-exact-get") }
                return response(Data(#"{"id":"synthetic-created","title":"Synthetic pending","status":"needsAction"}"#.utf8))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let reader = GWSReadClient(factory: factory, runner: runner)
        let service = RecoverableMutationService(runner: runner, journal: journal)
        do { _ = try service.perform(insert, reader: reader); throw TestFailure(description: "failed GET accepted") }
        catch is GWSFailure { }
        try check(journal.pending?.resourceID == "synthetic-created", "accepted identity must survive verification failure")
        do { _ = try service.perform(insert, reader: reader); throw TestFailure(description: "duplicate INSERT allowed") }
        catch is MutationRecoveryFailure { }
        try check(runner.invocations.filter { $0.operation == .taskInsert }.count == 1, "repeat Save must not resend INSERT")
        let restored = MutationJournal(fileURL: file)
        try check(restored.pending == journal.pending && restored.isBlocked, "restart must retain exact identity and draft")
        try check(restored.pending?.draftTitle == "Synthetic pending", "draft body must survive restart privately")
        readsFail = false
        let result = try RecoverableMutationService(runner: runner, journal: restored).recheck(reader: reader)
        try check(result.isReadBackVerified && !restored.isBlocked, "exact recheck must verify and clear the journal")
        try check(runner.invocations.filter { $0.operation == .taskInsert }.count == 1, "recheck must be read-only")

        let unknownJournal = MutationJournal()
        let unknownRunner = FakeProcessRunner { _ in response(Data("{}".utf8)) }
        let unknownService = RecoverableMutationService(runner: unknownRunner, journal: unknownJournal)
        let unknownReader = GWSReadClient(factory: factory, runner: unknownRunner)
        do { _ = try unknownService.perform(insert, reader: unknownReader); throw TestFailure(description: "missing ID accepted") }
        catch is GWSFailure { }
        do { _ = try unknownService.recheck(reader: unknownReader); throw TestFailure(description: "unknown ID rechecked") }
        catch is MutationRecoveryFailure { }
        try check(unknownRunner.invocations.count == 1 && unknownJournal.isBlocked, "unknown ID must never trigger another write or guessed GET")

        let rejectedJournal = MutationJournal()
        let rejectedRunner = FakeProcessRunner { _ in throw GWSFailure.executableUnavailable }
        do {
            _ = try RecoverableMutationService(runner: rejectedRunner, journal: rejectedJournal).perform(insert,
                reader: GWSReadClient(factory: factory, runner: rejectedRunner))
            throw TestFailure(description: "unavailable executable accepted")
        } catch is GWSFailure { }
        try check(!rejectedJournal.isBlocked, "rejected-before-launch must permit corrected Save")

        let ownTask = GoogleTask(id: "synthetic-delete", taskListID: "synthetic-list", title: "Synthetic", notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let deletion = try factory.taskDelete(task: ownTask, authorization: .confirmedDelete)
        for deleted in [true, false] {
            let deletionJournal = MutationJournal()
            let deletionRunner = FakeProcessRunner { input in
                if input.operation == .taskDelete { return response(Data(), code: 1, stderr: "synthetic CLI failure after submission") }
                return response(try JSONSerialization.data(withJSONObject: ["id": ownTask.id, "title": ownTask.title, "deleted": deleted]))
            }
            do {
                let outcome = try RecoverableMutationService(runner: deletionRunner, journal: deletionJournal).perform(deletion, reader: GWSReadClient(factory: factory, runner: deletionRunner))
                try check(deleted && outcome == .resourceDeleted && !deletionJournal.isBlocked, "nonzero DELETE may succeed only when exact GET proves its deletion")
            } catch let failure as GWSFailure {
                try check(!deleted && failure == .mutationNotVerified && deletionJournal.isBlocked, "nonzero DELETE without exact deletion proof must stay blocked")
            }
            try check(deletionRunner.invocations.map(\.operation) == [.taskDelete, .taskGet], "nonzero DELETE recovery must be one exact read and never a second write")
        }

        let nonemptyInsert = try factory.taskInsert(taskListID: "synthetic-list", title: "Synthetic pending", notes: "Meaningful", due: nil, authorization: .userSave)
        let mismatchJournal = MutationJournal()
        do {
            _ = try RecoverableMutationService(runner: runner, journal: mismatchJournal).perform(nonemptyInsert, reader: reader)
            throw TestFailure(description: "nonempty notes mismatch accepted")
        } catch let failure as GWSFailure {
            try check(failure == .mutationNotVerified && mismatchJournal.isBlocked, "nonempty notes mismatch must fail and retain attempt")
        }

        try Data("not-json".utf8).write(to: file)
        let corrupt = MutationJournal(fileURL: file)
        try check(corrupt.blockingFailure == .corruptJournal, "malformed durable bytes must still report journal corruption")
        try check(corrupt.isBlocked && FileManager.default.fileExists(atPath: file.path), "corrupt journal must block writes and preserve original")
        try corrupt.releaseAfterManualReview()
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("reviewed-attempt-") }
        try check(!corrupt.isBlocked && backups.count == 1 && (try Data(contentsOf: backups[0])) == Data("not-json".utf8),
                  "explicit manual review must preserve corrupt data privately while releasing the block")

        let calendar = CalendarInfo(id: "synthetic-calendar", title: "Synthetic", accessRole: "writer", timeZoneID: "UTC", colorHex: nil)
        let eventInsert = try factory.eventInsert(calendar: calendar,
            body: ["summary": "Synthetic", "start": ["date": "2026-10-05"], "end": ["date": "2026-10-06"]], authorization: .userSave)
        let listInsert = try factory.taskListInsert(title: "Synthetic", authorization: .userSave)
        for invocation in [eventInsert, listInsert] {
            let currentJournal = MutationJournal()
            let currentRunner = FakeProcessRunner { input in
                if input.operation == invocation.operation { return response(Data(#"{"id":"synthetic-resource"}"#.utf8)) }
                throw GWSFailure.timedOut("synthetic-exact-get")
            }
            let currentReader = GWSReadClient(factory: factory, runner: currentRunner)
            let currentService = RecoverableMutationService(runner: currentRunner, journal: currentJournal)
            do { _ = try currentService.perform(invocation, reader: currentReader); throw TestFailure(description: "unverified write accepted") }
            catch is GWSFailure { }
            do { _ = try currentService.perform(invocation, reader: currentReader); throw TestFailure(description: "duplicate write allowed") }
            catch is MutationRecoveryFailure { }
            try check(currentJournal.pending?.resourceID == "synthetic-resource" && currentRunner.invocations.count == 2,
                      "event/list accepted IDs must be retained and subsequent writes blocked")
        }
    }

    static func testIndependentMutationJournals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("g-calendar-independent-journals-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("pending.json")
        let factory = GWSCommandFactory(executableURL: executable)
        let invocation = try factory.taskInsert(taskListID: "synthetic-list", title: "Synthetic race", notes: nil, due: nil, authorization: .userSave)
        let first = MutationJournal(fileURL: file)
        let stale = MutationJournal(fileURL: file)
        try first.begin(invocation)
        let firstID = first.pending?.id
        do {
            try stale.begin(invocation)
            throw TestFailure(description: "stale journal replaced another process's pending mutation")
        } catch is MutationRecoveryFailure { }
        try check(MutationJournal(fileURL: file).pending?.id == firstID, "independent journal must retain the durable owner")
        guard let firstID else { throw TestFailure(description: "missing race owner") }
        let oldObserver = MutationJournal(fileURL: file)
        try first.clear(expectedID: firstID)
        let replacementID = try stale.begin(invocation)
        for action in [
            { try oldObserver.capture(Data(#"{"id":"synthetic-foreign"}"#.utf8), expectedID: firstID) },
            { try oldObserver.clear(expectedID: firstID) },
            { try oldObserver.releaseAfterManualReview(expectedID: firstID) },
            { try oldObserver.releaseAfterManualReview() }
        ] {
            do { try action(); throw TestFailure(description: "stale owner acknowledged a replacement attempt") }
            catch is MutationRecoveryFailure { }
            try check(MutationJournal(fileURL: file).pending?.id == replacementID, "stale capture/clear/manual release must preserve the replacement UUID")
        }
        let untouchedRunner = FakeProcessRunner { _ in throw TestFailure(description: "stale recheck reached exact GET") }
        do {
            _ = try RecoverableMutationService(runner: untouchedRunner, journal: oldObserver).recheck(
                reader: GWSReadClient(factory: factory, runner: untouchedRunner), expectedID: firstID)
            throw TestFailure(description: "stale recheck accepted the replacement")
        } catch is MutationRecoveryFailure { }
        try check(untouchedRunner.invocations.isEmpty, "stale recheck must stop before reading a different attempt")
        try stale.capture(Data(#"{"id":"synthetic-current"}"#.utf8), expectedID: replacementID)
        try check(MutationJournal(fileURL: file).pending?.resourceID == "synthetic-current", "current owner may capture its exact response")

        let corruptObserver = MutationJournal(fileURL: file)
        try Data("synthetic corrupt one".utf8).write(to: file)
        let corrupt = MutationJournal(fileURL: file)
        try Data("synthetic corrupt two".utf8).write(to: file)
        do { try corrupt.releaseAfterManualReview(); throw TestFailure(description: "changed corrupt journal released") }
        catch is MutationRecoveryFailure { }
        do { try corruptObserver.clear(expectedID: replacementID); throw TestFailure(description: "corrupt replacement cleared") }
        catch is MutationRecoveryFailure { }
        try check(try Data(contentsOf: file) == Data("synthetic corrupt two".utf8), "changed corrupt data must remain untouched")

        // Hold the service lease while an exact GET is delayed. Independent journal
        // objects use distinct file descriptors, exercising the sidecar flock too.
        let overlapFile = root.appendingPathComponent("overlap.json")
        let firstOverlap = MutationJournal(fileURL: overlapFile)
        let secondOverlap = MutationJournal(fileURL: overlapFile)
        let reading = DispatchSemaphore(value: 0)
        let finishRead = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let outcomeLock = NSLock()
        var firstOutcome: Result<GWSMutationResult, Error>?
        let firstRunner = FakeProcessRunner { input in
            if input.operation == .taskInsert { return response(Data(#"{"id":"synthetic-overlap"}"#.utf8)) }
            reading.signal()
            guard finishRead.wait(timeout: .now() + 5) == .success else { throw TestFailure(description: "overlap fixture release timed out") }
            return response(Data(#"{"id":"synthetic-overlap","title":"Synthetic race","status":"needsAction"}"#.utf8))
        }
        DispatchQueue.global().async {
            let outcome = Result { try RecoverableMutationService(runner: firstRunner, journal: firstOverlap).perform(
                invocation, reader: GWSReadClient(factory: factory, runner: firstRunner)) }
            outcomeLock.lock(); firstOutcome = outcome; outcomeLock.unlock()
            finished.signal()
        }
        guard reading.wait(timeout: .now() + 5) == .success else { throw TestFailure(description: "overlap fixture did not reach GET") }
        let initializedWhileBusy = MutationJournal(fileURL: overlapFile)
        try check(initializedWhileBusy.pending == nil && initializedWhileBusy.isBlocked && initializedWhileBusy.blockingFailure == .journalBusy,
                  "initialization during another operation must report busy, never corrupt journal")
        let busyReview = initializedWhileBusy.review()
        try check(busyReview.pending == nil && busyReview.failure == .journalBusy, "atomic UI review must distinguish a busy lease from a corrupt or missing draft")
        try check(firstOverlap.isBlocked && firstOverlap.pending == nil, "same-process observation must fail closed without waiting for network I/O")
        let secondRunner = FakeProcessRunner { _ in throw TestFailure(description: "overlapping write reached process runner") }
        do {
            _ = try RecoverableMutationService(runner: secondRunner, journal: secondOverlap).perform(
                invocation, reader: GWSReadClient(factory: factory, runner: secondRunner))
            throw TestFailure(description: "overlapping service acquired the lease")
        } catch is MutationRecoveryFailure { }
        try check(secondRunner.invocations.isEmpty && secondOverlap.isBlocked, "overlapping service must fail closed without starting a process")
        finishRead.signal()
        guard finished.wait(timeout: .now() + 5) == .success else { throw TestFailure(description: "overlap service failed to finish") }
        outcomeLock.lock(); let outcome = firstOutcome; outcomeLock.unlock()
        try check(try outcome?.get().isReadBackVerified == true && !firstOverlap.isBlocked, "lease owner must finish exact verification and clear only its attempt")
        try check(initializedWhileBusy.blockingFailure == nil && !initializedWhileBusy.isBlocked, "busy initialization must recover after the owner releases its lease")
        let releasedReview = initializedWhileBusy.review()
        try check(releasedReview.pending == nil && releasedReview.failure == nil, "atomic UI review must clear a released busy state")
        let lockFile = URL(fileURLWithPath: overlapFile.path + ".lock")
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockFile.path)
        try check((lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 && FileManager.default.fileExists(atPath: lockFile.path), "sidecar must remain private and stable after atomic journal removal")

        // A separate test-binary process holds the same sidecar, proving this is
        // OS-level exclusion rather than just the journal's NSRecursiveLock.
        let processFile = root.appendingPathComponent("process.json")
        let ready = root.appendingPathComponent("process-ready")
        let release = root.appendingPathComponent("process-release")
        let processJournal = MutationJournal(fileURL: processFile)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--journal-lock-probe", processFile.path, ready.path, release.path]
        try child.run()
        defer {
            try? Data().write(to: release)
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path) && child.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard FileManager.default.fileExists(atPath: ready.path) else { throw TestFailure(description: "separate process did not acquire the journal lease") }
        do { try processJournal.begin(invocation); throw TestFailure(description: "separate-process lease allowed a write") }
        catch is MutationRecoveryFailure { }
        try check(processJournal.isBlocked && !FileManager.default.fileExists(atPath: processFile.path), "separate-process lease must block before creating a journal or running a mutation")
        try Data().write(to: release)
        let exitDeadline = Date().addingTimeInterval(5)
        while child.isRunning && Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.01) }
        guard !child.isRunning else { throw TestFailure(description: "separate-process lease did not release") }
        try check(child.terminationStatus == 0, "separate-process lease probe must finish successfully")
        let processID = try processJournal.begin(invocation)
        try processJournal.clear(expectedID: processID)
        let after = try FileManager.default.attributesOfItem(atPath: processFile.path + ".lock")
        try check((after[.posixPermissions] as? NSNumber)?.intValue == 0o600, "a released OS lock must remain usable by the next process")
    }

    static func runJournalLockProbe() throws {
        let journal = MutationJournal(fileURL: URL(fileURLWithPath: CommandLine.arguments[2]))
        try journal.withExclusiveAccess {
            try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
            let deadline = Date().addingTimeInterval(8)
            while !FileManager.default.fileExists(atPath: CommandLine.arguments[4]) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard FileManager.default.fileExists(atPath: CommandLine.arguments[4]) else { throw TestFailure(description: "journal lock probe release timed out") }
        }
    }

    static func testSyntheticLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("g-calendar-lifecycle-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var event: [String: Any]?
        var list: [String: Any]?
        var task: [String: Any]?
        var interruptDeletionRead = false
        let owner: [String: Any] = ["id": "synthetic-owner", "summary": "Synthetic", "accessRole": "owner", "timeZone": "UTC"]
        let runner = FakeProcessRunner { invocation in
            let arguments = invocation.arguments
            var body: [String: Any] = [:]
            if let index = arguments.firstIndex(of: "--json"), let data = arguments[index + 1].data(using: .utf8) {
                body = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
            let object: [String: Any]
            switch invocation.operation {
            case .calendarList: object = ["items": [owner]]
            case .calendarGet: object = owner
            case .eventInsert:
                event = body; event?["id"] = "synthetic-live-event"; object = event!
            case .eventPatch:
                event?.merge(body) { _, new in new }; object = event!
            case .eventGet:
                guard let event else { throw GWSFailure.resourceNotFound }; object = event
            case .eventDelete: event?["status"] = "cancelled"; object = [:]
            case .taskListInsert:
                list = body; list?["id"] = "synthetic-live-list"; object = list!
            case .taskListPatch:
                list?.merge(body) { _, new in new }; object = list!
            case .taskListGet:
                guard let list else { throw GWSFailure.resourceNotFound }; object = list
            case .taskListDelete: list = nil; object = [:]
            case .taskInsert:
                task = body; task?["id"] = "synthetic-live-task"; object = task!
            case .taskPatch:
                task?.merge(body) { _, new in new }; object = task!
            case .taskGet:
                if interruptDeletionRead && task?["deleted"] as? Bool == true {
                    interruptDeletionRead = false
                    throw GWSFailure.timedOut("synthetic-delete-read")
                }
                guard let task else { throw GWSFailure.resourceNotFound }; object = task
            case .taskDelete: task?["deleted"] = true; object = [:]
            default: throw GWSFailure.forbiddenOperation
            }
            return response(try JSONSerialization.data(withJSONObject: object))
        }
        let factory = GWSCommandFactory(executableURL: executable)
        let run = try SyntheticAcceptanceRun(directory: directory, factory: factory, runner: runner)
        try check(try run.run(now: Date(timeIntervalSince1970: 1_800_000_000.332)) == 11, "native acceptance must verify all 11 create/edit/toggle/delete steps")
        try check(event?["status"] as? String == "cancelled" && task?["deleted"] as? Bool == true && list == nil, "only current-run synthetic resources must be cleaned, including exact deletion tombstones")
        try check(runner.invocations.filter { [.eventInsert, .taskInsert, .taskListInsert].contains($0.operation) }.count == 3,
                  "native acceptance must never repeat an INSERT")
        try check(runner.invocations.filter { $0.operation == .eventGet }.count == 5 &&
                  runner.invocations.filter { $0.operation == .taskGet }.count == 9 &&
                  runner.invocations.filter { $0.operation == .taskListGet }.count == 5,
                  "every edit/toggle/delete must have exact GET before and after")
        let ledgerFile = directory.appendingPathComponent("ledger.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: ledgerFile.path)
        let ledger = try JSONSerialization.jsonObject(with: Data(contentsOf: ledgerFile)) as? [String: Any]
        try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 && ledger?["complete"] as? Bool == true,
                  "exact ledger must remain private and honestly completed")
        do {
            _ = try SyntheticAcceptanceRun(directory: directory, factory: factory, runner: runner)
            throw TestFailure(description: "existing acceptance run was reused")
        } catch is GWSFailure { }
        try check(AppLaunchMode.parse(arguments: ["app", "--synthetic-lifecycle"]) == .syntheticAcceptance,
                  "live acceptance must require its own explicit launch mode")
        try check(DemoScenario.parse(arguments: ["app", "--demo-state", "recovery"]) == .ready &&
                  DemoScenario.parse(arguments: ["app", "--demo", "--demo-state", "recovery"]) == .recovery,
                  "synthetic UI scenarios must never affect normal mode")

        let recoveryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("g-calendar-lifecycle-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        interruptDeletionRead = true
        do {
            _ = try SyntheticAcceptanceRun(directory: recoveryDirectory, factory: factory, runner: runner).run()
            throw TestFailure(description: "failed deletion GET accepted")
        } catch let failure as GWSFailure {
            if case .timedOut = failure { try check(true, "accepted deletion with failed GET must stop before further writes") }
            else { throw failure }
        }
        let pendingFile = recoveryDirectory.appendingPathComponent("pending.json")
        let originalPending = try Data(contentsOf: pendingFile)
        var foreignPending = try JSONSerialization.jsonObject(with: originalPending) as! [String: Any]
        foreignPending["resourceID"] = "synthetic-foreign-id"
        try JSONSerialization.data(withJSONObject: foreignPending).write(to: pendingFile)
        let beforeForeign = runner.invocations.count
        try expectForbidden({
            _ = try SyntheticAcceptanceRun(directory: recoveryDirectory, factory: factory, runner: runner, finishExistingCleanup: true).finishExistingCleanup()
        }, "cleanup journal outside exact ledger")
        try check(runner.invocations.count == beforeForeign, "foreign cleanup identity must be rejected before any process call")
        try originalPending.write(to: pendingFile)
        let beforeResume = runner.invocations.count
        let resumed = try SyntheticAcceptanceRun(directory: recoveryDirectory, factory: factory, runner: runner, finishExistingCleanup: true)
        try check(try resumed.finishExistingCleanup() == 11, "cleanup must resume by exact read-only recheck and verify all remaining deletions")
        let resumedWrites = runner.invocations.dropFirst(beforeResume).filter { [.eventInsert, .eventDelete, .eventPatch, .taskInsert, .taskDelete, .taskPatch, .taskListInsert, .taskListDelete, .taskListPatch].contains($0.operation) }
        try check(resumedWrites.map(\.operation) == [.eventDelete, .taskListDelete], "cleanup must not repeat the already accepted task DELETE or any INSERT")
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

    static func testTaskMoveVerificationAndRecovery() async throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let due = DateOnly(rawValue: "2026-10-12")!
        let task = GoogleTask(id: "synthetic-move-source", taskListID: "synthetic-source-board", title: "Synthetic edited task",
                              notes: "Synthetic notes", due: due, completed: false, deleted: false, updated: nil)
        let destination = "synthetic-target-board"
        let move = try factory.taskMove(task: task, destinationTaskListID: destination, authorization: .userSave)
        try check(move.arguments == ["tasks", "tasks", "move", "--params", "{\"destinationTasklist\":\"synthetic-target-board\",\"task\":\"synthetic-move-source\",\"tasklist\":\"synthetic-source-board\"}"],
                  "native cross-board move must carry exact source/destination params and no body")
        try check(move.expectedTask == task && !move.arguments.contains("--json"), "verification snapshot must stay local")
        for authorization in [MutationAuthorization.cancelled, .confirmedDelete, .userCompletionToggle] {
            try expectForbidden({ _ = try factory.taskMove(task: task, destinationTaskListID: destination, authorization: authorization) }, "move authorization")
        }
        for target in ["", task.taskListID] {
            try expectForbidden({ _ = try factory.taskMove(task: task, destinationTaskListID: target, authorization: .userSave) }, "invalid destination")
        }
        try check(WorkspaceRefreshScope.afterVerifiedMutation(.taskMove) == .tasks, "move must refresh only task scope")
        func object(id: String, title: String = "Synthetic edited task", notes: String = "Synthetic notes", due: String = "2026-10-12T00:00:00.000Z", completed: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["id": id, "title": title, "notes": notes, "due": due,
                                                       "status": completed ? "completed" : "needsAction"])
        }
        func response(_ data: Data, code: Int32 = 0) -> ProcessResult {
            ProcessResult(exitCode: code, stdout: data, stderr: code == 404 ? Data("404 not found".utf8) : Data())
        }
        for mismatch in ["none", "title", "notes", "due", "status", "source", "destination-deleted"] {
            let runner = FakeProcessRunner { invocation in
                if invocation.operation == .taskMove { return response(Data("{\"id\":\"synthetic-move-source\"}".utf8)) }
                guard invocation.operation == .taskGet else { throw GWSFailure.forbiddenOperation }
                if Self.params(invocation)["tasklist"] as? String == destination {
                    if mismatch == "destination-deleted" { return response(Data("{\"id\":\"synthetic-move-source\",\"deleted\":true}".utf8)) }
                    return response(try object(id: task.id, title: mismatch == "title" ? "Different" : task.title,
                                               notes: mismatch == "notes" ? "Different" : "Synthetic notes",
                                               due: mismatch == "due" ? "2026-10-13T00:00:00.000Z" : "2026-10-12T00:00:00.000Z",
                                               completed: mismatch == "status"))
                }
                if mismatch == "source" { return response(try object(id: task.id)) }
                return response(Data("{\"id\":\"synthetic-move-source\",\"deleted\":true}".utf8))
            }
            do {
                let result = try GWSMutationService(runner: runner).perform(move, reader: GWSReadClient(factory: factory, runner: runner))
                try check(mismatch == "none", "move mismatch must not be accepted")
                guard case .taskVerified(let moved) = result else { throw TestFailure(description: "move result must be typed") }
                try check(moved.id == task.id && moved.taskListID == destination, "verified move preserves native ID and target membership")
                try check(runner.invocations.map(\.operation) == [.taskMove, .taskGet, .taskGet], "move must exact-read destination and source")
            } catch let failure as GWSFailure {
                try check(mismatch != "none" && failure == .mutationNotVerified, "wrong fields/membership must remain unconfirmed")
            }
        }

        var destinationReady = false
        let changedID = "synthetic-move-returned-id"
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskPatch: return response(try object(id: task.id))
            case .taskMove: return response(Data("{\"id\":\"synthetic-move-returned-id\"}".utf8))
            case .taskGet:
                if Self.params(invocation)["tasklist"] as? String == destination {
                    return destinationReady ? response(try object(id: changedID)) : response(Data(), code: 404)
                }
                if destinationReady { return response(Data(), code: 404) }
                return response(try object(id: task.id))
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("g-calendar-move-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let journal = MutationJournal(fileURL: temporary.appendingPathComponent("pending.json"))
        let reader = GWSReadClient(factory: factory, runner: runner)
        let service = RecoverableMutationService(runner: runner, journal: journal)
        let patch = try factory.taskPatch(task: task, title: task.title, notes: task.notes, due: due, authorization: .userSave, destinationTaskListID: destination)
        var state = TaskReminderSaveState()
        try check(state.accept(try service.perform(patch, reader: reader)) && !state.needsGoogleSave && state.needsMove(to: destination),
                  "verified patch must advance to move without repeating fields or local reminder")
        do {
            _ = try service.perform(move, reader: reader)
            throw TestFailure(description: "uncertain move must remain recoverable")
        } catch let failure as GWSFailure { try check(failure == .mutationNotVerified, "missing destination must block completion") }
        let pending = journal.pending!
        try check(pending.operation == .taskMove && pending.sourceTaskID == task.id && pending.resourceID == changedID,
                  "move response ID must not replace exact source identity")
        try check(pending.destinationTaskListID == destination && pending.expectedTask == task,
                  "reopened recovery must restore destination and patched field snapshot")
        try check(!state.needsGoogleSave && state.needsMove(to: destination) && journal.isBlocked,
                  "pending move must retain Google recovery control after patch success")
        let resumedJournal = MutationJournal(fileURL: temporary.appendingPathComponent("pending.json"))
        destinationReady = true
        let before = runner.invocations.count
        let moved = try RecoverableMutationService(runner: runner, journal: resumedJournal).recheck(reader: reader)
        try check(state.accept(moved) && !state.needsGoogleSave && !state.needsMove(to: destination), "verified recheck must advance to local stage")
        try check(state.verifiedTask?.id == changedID && !resumedJournal.isBlocked, "recheck must retain changed destination ID")
        try check(runner.invocations.dropFirst(before).allSatisfy { $0.operation == .taskGet } &&
                  runner.invocations.filter { $0.operation == .taskPatch }.count == 1 && runner.invocations.filter { $0.operation == .taskMove }.count == 1,
                  "recheck/local continuation must not repeat patch or move")

        let future = Date().addingTimeInterval(1200)
        let backing = MemoryMetadataStore()
        try backing.set(LocalTaskMetadata(reminderAt: future, favorite: true), for: task.id)
        let failing = FailingMigrationMetadataStore(backing: backing, targetID: changedID, setFailures: 1, removeFailures: 1)
        let scheduler = RecordingScheduler(permission: .authorized)
        let defaults = UserDefaults(suiteName: "g-calendar-move-local-" + UUID().uuidString)!
        let coordinator = ReminderCoordinator(store: failing, scheduler: scheduler, defaults: defaults)
        let metadataJournal = MutationJournal(fileURL: temporary.appendingPathComponent("metadata-pending.json"))
        let metadataService = RecoverableMutationService(runner: runner, journal: metadataJournal, beforeCompletion: { result, pending in
            guard case .taskVerified(let verified) = result, let sourceID = pending.sourceTaskID else { throw GWSFailure.mutationNotVerified }
            try coordinator.prepareTaskMetadataMigration(from: sourceID, to: verified.id)
        })
        do {
            _ = try metadataService.perform(move, reader: reader)
            throw TestFailure(description: "metadata persistence failure must retain journal")
        } catch let failure as TestFailure { try check(failure.description == "Synthetic target persistence failure", "persist failure must propagate") }
        try check(metadataJournal.isBlocked && backing.metadata(for: task.id).favorite && backing.metadata(for: changedID).reminderAt == nil,
                  "target persistence failure must preserve source and durable read-only recovery")
        let unrelatedID = "synthetic-unrelated-deleted"
        try backing.set(LocalTaskMetadata(reminderAt: future, favorite: true), for: unrelatedID)
        let emptyRunner = FakeProcessRunner { invocation in
            guard invocation.operation == .taskListsList else { throw GWSFailure.forbiddenOperation }
            return response(Data("{\"items\":[]}".utf8))
        }
        let completeTasks = try GWSWorkspaceService(reader: GWSReadClient(factory: factory, runner: emptyRunner), cache: MemorySnapshotStore()).refreshTasks()
        try await ReminderCoordinator(store: backing, scheduler: scheduler, defaults: defaults)
            .reconcile(afterSuccessfulTasksSync: completeTasks, preservingTaskIDs: {
                let pending = metadataJournal.review().pending
                return pending?.operation == .taskMove ? Set([pending!.sourceTaskID!]) : []
            })
        try check(backing.metadata(for: task.id).reminderAt == future && backing.metadata(for: task.id).favorite,
                  "complete refresh during pending move must protect source metadata until target persists")
        try check(backing.metadata(for: unrelatedID).reminderAt == nil && scheduler.cancellations.contains(ReminderIdentity.identifier(taskID: task.id)),
                  "pending move protection must retain only its source metadata while cancelling absent notifications")
        let restored = MutationJournal(fileURL: temporary.appendingPathComponent("metadata-pending.json"))
        let beforeMetadataRetry = runner.invocations.count
        _ = try RecoverableMutationService(runner: runner, journal: restored, beforeCompletion: { result, pending in
            guard case .taskVerified(let verified) = result, let sourceID = pending.sourceTaskID else { throw GWSFailure.mutationNotVerified }
            try coordinator.prepareTaskMetadataMigration(from: sourceID, to: verified.id)
        }).recheck(reader: reader)
        try check(!restored.isBlocked && backing.metadata(for: changedID).reminderAt == future && backing.metadata(for: changedID).favorite,
                  "restart recheck must persist target metadata before journal release")
        try check(runner.invocations.dropFirst(beforeMetadataRetry).allSatisfy { $0.operation == .taskGet }, "metadata retry must not resubmit move")
        do {
            try await coordinator.migrateTaskMetadata(from: task.id, to: changedID)
            throw TestFailure(description: "source cleanup failure must propagate")
        } catch let failure as TestFailure { try check(failure.description == "Synthetic source removal failure", "cleanup failure must propagate") }
        try check(backing.metadata(for: changedID).favorite && backing.metadata(for: task.id).favorite, "failed cleanup must keep both persisted copies")
        try await coordinator.migrateTaskMetadata(from: task.id, to: changedID)
        let verifiedTask = state.verifiedTask!
        _ = try await coordinator.saveReminder(task: verifiedTask, title: verifiedTask.title, at: future, explicitEnableAction: true)
        try check(backing.metadata(for: changedID).favorite && backing.metadata(for: changedID).reminderAt == future && backing.metadata(for: task.id).reminderAt == nil,
                  "local retry must preserve favorite/time on changed ID and safely retire source")
        try check(scheduler.requests.last?.taskID == changedID && scheduler.cancellations.contains(ReminderIdentity.identifier(taskID: task.id)),
                  "changed-ID reminder must cancel source notification and schedule only target")

        let demo = DemoWorkspaceAdapter()
        let demoTask = demo.snapshot().tasks[0]
        let demoListInsert = try factory.taskListInsert(title: "Synthetic destination", authorization: .userSave)
        try demo.perform(demoListInsert)
        let demoDestination = demo.snapshot().taskLists.first { $0.title == "Synthetic destination" }!.id
        let demoMove = try factory.taskMove(task: demoTask, destinationTaskListID: demoDestination, authorization: .userSave)
        try demo.perform(demoMove)
        let demoMoved = demo.snapshot().tasks.first { $0.id == demoTask.id }!
        try check(demoMoved.taskListID == demoDestination && demoMoved.title == demoTask.title && demoMoved.due == demoTask.due && demoMoved.notes == demoTask.notes,
                  "demo move must preserve one native task and its fields")
        try check(demo.snapshot().tasks.filter { $0.id == demoTask.id }.count == 1, "demo move must never copy/delete task identity")
    }

    static func testVerifiedTaskReminderSave() async throws {
        let now = Date()
        let future = now.addingTimeInterval(600)
        let past = now.addingTimeInterval(-600)
        try check(TaskReminderSaveState.validationMessage(enabled: true, fireDate: past, now: now) != nil,
                  "new past reminder must be rejected before Google mutation")
        try check(TaskReminderSaveState.validationMessage(enabled: true, fireDate: past, unchangedDate: past, now: now) == nil,
                  "unchanged expired reminder must not block title editing")
        try check(TaskReminderSaveState.validationMessage(enabled: true, fireDate: past, completed: true, now: now) == nil,
                  "completed task edits must not demand a future reminder")
        try check(TaskReminderSaveState.validationMessage(enabled: false, fireDate: past, now: now) == nil &&
                  TaskReminderSaveState.validationMessage(enabled: true, fireDate: future, now: now) == nil,
                  "disabled and future reminders must validate")

        let factory = GWSCommandFactory(executableURL: executable)
        let task = GoogleTask(id: "verified-reminder-fixture", taskListID: "list-fixture", title: "Synthetic reminder",
                              notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let runner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskInsert:
                return ProcessResult(exitCode: 0, stdout: Data("{\"id\":\"verified-reminder-fixture\"}".utf8), stderr: Data())
            case .taskGet:
                return ProcessResult(exitCode: 0, stdout: Data("{\"id\":\"verified-reminder-fixture\",\"title\":\"Synthetic reminder\",\"status\":\"needsAction\"}".utf8), stderr: Data())
            default: throw TestFailure(description: "Unexpected synthetic operation")
            }
        }
        var state = TaskReminderSaveState()
        try check(!state.accept(.requestAccepted) && state.needsGoogleSave && state.verifiedTask == nil,
                  "unverified task cannot enter the local reminder stage")
        let insert = try factory.taskInsert(taskListID: task.taskListID, title: task.title, notes: nil, due: nil, authorization: .userSave)
        let verified = try GWSMutationService(runner: runner).perform(insert, reader: GWSReadClient(factory: factory, runner: runner))
        try check(state.accept(verified) && !state.needsGoogleSave && state.verifiedTask?.id == task.id,
                  "exact readback must preserve the confirmed task ID for local retries")
        let store = MemoryMetadataStore()
        let scheduler = RecordingScheduler(permission: .authorized, scheduleFailures: 1)
        let suite = "g-calendar-reminder-stage-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ReminderCoordinator(store: store, scheduler: scheduler, defaults: defaults)
        do {
            _ = try await coordinator.saveReminder(task: state.verifiedTask!, title: task.title, at: future, explicitEnableAction: true, now: now)
            throw TestFailure(description: "Synthetic scheduling failure should propagate")
        } catch let failure as TestFailure {
            try check(failure.description == "Synthetic scheduling failure", "scheduler failure must propagate without replacing confirmed task")
        }
        try check(store.metadata(for: task.id).reminderAt == future && !state.needsGoogleSave,
                  "local failure must retain metadata and never re-enter Google insert stage")
        _ = try await coordinator.saveReminder(task: state.verifiedTask!, title: task.title, at: future, explicitEnableAction: true, now: now)
        try check(scheduler.requests.count == 1 && scheduler.requests.first?.taskID == task.id,
                  "local retry must schedule the confirmed ID once")
        try check(runner.invocations.filter { $0.operation == .taskInsert }.count == 1 && runner.invocations.count == 2,
                  "local retry must not repeat Google insert or readback")
        let deniedStore = MemoryMetadataStore()
        let deniedScheduler = RecordingScheduler(permission: .denied)
        let denied = try await ReminderCoordinator(store: deniedStore, scheduler: deniedScheduler, defaults: defaults)
            .saveReminder(task: task, title: task.title, at: future, explicitEnableAction: true, now: now)
        try check(denied.status == .denied && deniedStore.metadata(for: task.id).reminderAt == future && deniedScheduler.requests.isEmpty,
                  "denied delivery must still preserve the local reminder time without claiming scheduling")
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
        try check(failedRequest.userMessage.contains("разрешение ещё не получено") &&
                  !failedRequest.userMessage.contains("UNErrorDomain") && !failedRequest.userMessage.contains("not_determined"),
                  "user feedback must describe actual permission without internal diagnostic identifiers")
        try check(NotificationAuthorizationResult(status: .authorized, requestFailure: schedulerError).userMessage.contains("уведомления разрешены"),
                  "request failure feedback must retain an authorized read-back")
        try check(NotificationAuthorizationResult(status: .denied).userMessage.contains("системных настройках") &&
                  !NotificationAuthorizationResult(status: .denied).userMessage.contains("нажал"),
                  "denied feedback must offer settings recovery without guessing a user action")

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
        let requestedRange = try DateRange(start: start, endExclusive: end)
        let completedSync = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner),
                                                    cache: MemorySnapshotStore())
            .refreshCompletedFullSync(range: requestedRange)
        try check(completedSync.snapshot.calendarCoverage?.covers(requestedRange) == true,
                  "completed full sync must record the exact calendar range and time zone it fetched")
        try await coordinator.reconcile(afterSuccessfulFullSync: completedSync, now: Date())
        try check(scheduler.cancellations.contains(identifier), "successful complete sync did not cancel removed task notification")
        try check(store.metadata(for: taskID).reminderAt == nil, "successful complete sync did not remove stale local reminder metadata")

        let taskOnlyID = "synthetic-task-only-deleted"
        let taskOnlyIdentifier = ReminderIdentity.identifier(taskID: taskOnlyID)
        try store.set(LocalTaskMetadata(reminderAt: reminderDate, favorite: true), for: taskOnlyID)
        try await scheduler.schedule(ReminderRequest(identifier: taskOnlyIdentifier, taskID: taskOnlyID,
                                                     title: "Synthetic task-only reminder", fireDate: reminderDate))
        let completedTasksSync = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner),
                                                         cache: MemorySnapshotStore(completedSync.snapshot))
            .refreshTasks()
        try await coordinator.reconcile(afterSuccessfulTasksSync: completedTasksSync, now: Date())
        try check(scheduler.cancellations.contains(taskOnlyIdentifier), "successful complete Tasks refresh did not cancel removed task notification")
        try check(store.metadata(for: taskOnlyID).reminderAt == nil, "successful complete Tasks refresh did not remove stale reminder metadata")
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

    static func testCalendarRangeRefreshSkipsTaskAPI() throws {
        let calendarJSON = Data(#"{"items":[{"id":"synthetic-calendar","summary":"Synthetic Calendar","accessRole":"owner","timeZone":"UTC"}]}"#.utf8)
        let taskListsJSON = Data(#"{"items":[{"id":"synthetic-list","title":"Synthetic Tasks"}]}"#.utf8)
        let tasksJSON = Data(#"{"items":[{"id":"synthetic-task","title":"Cached task","status":"needsAction"}]}"#.utf8)
        let emptyJSON = Data(#"{"items":[]}"#.utf8)
        let handler: FakeProcessRunner.Handler = { invocation in
            switch invocation.operation {
            case .calendarList: return response(calendarJSON)
            case .eventsList: return response(emptyJSON)
            case .taskListsList: return response(taskListsJSON)
            case .tasksList: return response(tasksJSON)
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let zone = TimeZone(secondsFromGMT: 0)!
        let start = DateOnly(rawValue: "2026-10-05")!.startOfDay(in: zone)!
        let end = DateOnly(rawValue: "2026-10-12")!.startOfDay(in: zone)!
        let range = try DateRange(start: start, endExclusive: end, timeZone: zone)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let baselineRunner = FakeProcessRunner(handler: handler)
        let baseline = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: baselineRunner),
                                               cache: MemorySnapshotStore())
            .refreshCompletedFullSync(range: range, now: now)
        try check(baselineRunner.invocations.map(\.operation) == [.calendarList, .eventsList, .taskListsList, .tasksList],
                  "full-sync baseline for one calendar and task list must make four process calls")

        let rangeRunner = FakeProcessRunner(handler: handler)
        let rangeResult = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: rangeRunner),
                                                  cache: MemorySnapshotStore(baseline.snapshot))
            .refreshCalendarRange(range: range, now: now.addingTimeInterval(60))
        try check(rangeRunner.invocations.map(\.operation) == [.calendarList, .eventsList],
                  "calendar range refresh must not fetch task lists or tasks")
        try check(rangeResult.tasks == baseline.snapshot.tasks && rangeResult.taskLists == baseline.snapshot.taskLists,
                  "calendar-only refresh must preserve cached task resources")
        try check(rangeResult.tasksFetchedAt == baseline.snapshot.fetchedAt && rangeResult.calendarFetchedAt == now.addingTimeInterval(60),
                  "calendar and Tasks freshness must remain independently visible")
        try check(rangeResult.calendarCoverage?.covers(range) == true,
                  "calendar-only refresh must record coverage only after loading succeeds")

        let updatedTaskListsJSON = Data(#"{"items":[{"id":"synthetic-list","title":"Updated Synthetic Tasks"}]}"#.utf8)
        let updatedTasksJSON = Data(#"{"items":[{"id":"synthetic-task","title":"Updated task","status":"needsAction"}]}"#.utf8)
        let taskRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskListsList: return response(updatedTaskListsJSON)
            case .tasksList: return response(updatedTasksJSON)
            default: throw GWSFailure.forbiddenOperation
            }
        }
        let taskSync = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: taskRunner),
                                                cache: MemorySnapshotStore(rangeResult))
            .refreshTasks(now: now.addingTimeInterval(90))
        let taskResult = taskSync.snapshot
        try check(taskRunner.invocations.map(\.operation) == [.taskListsList, .tasksList],
                  "Tasks-domain refresh must not fetch calendar resources")
        try check(taskResult.taskLists.first?.title == "Updated Synthetic Tasks" && taskResult.tasks.first?.title == "Updated task",
                  "Tasks-domain refresh must publish the fully refreshed task resources")
        try check(taskResult.calendars == rangeResult.calendars && taskResult.events == rangeResult.events &&
                  taskResult.calendarCoverage == rangeResult.calendarCoverage &&
                  taskResult.calendarFetchedAt == rangeResult.calendarFetchedAt,
                  "Tasks-domain refresh must preserve calendar data, coverage, and freshness")
        try check(taskResult.tasksFetchedAt == now.addingTimeInterval(90),
                  "Tasks-domain refresh must advance only Tasks freshness")

        let failedTaskStore = MemorySnapshotStore(rangeResult)
        let failedTaskRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .taskListsList: return response(updatedTaskListsJSON)
            case .tasksList: return response(Data(), code: 50, stderr: "synthetic Tasks list failure")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: failedTaskRunner),
                                        cache: failedTaskStore)
                .refreshTasks(now: now.addingTimeInterval(180))
            throw TestFailure(description: "failed Tasks refresh unexpectedly committed a partial snapshot")
        } catch let failure as GWSFailure {
            if case .processFailed(_, 50, _) = failure { try check(true, "Tasks refresh failure surfaced") }
            else { throw TestFailure(description: "Tasks refresh failure returned an unexpected error") }
        }
        try check(failedTaskStore.load() == rangeResult,
                  "failed Tasks refresh must preserve the last complete cache snapshot")

        let failedRangeStore = MemorySnapshotStore(baseline.snapshot)
        let failedRangeRunner = FakeProcessRunner { invocation in
            switch invocation.operation {
            case .calendarList: return response(calendarJSON)
            case .eventsList: return response(Data(), code: 49, stderr: "synthetic event range failure")
            default: throw GWSFailure.forbiddenOperation
            }
        }
        do {
            _ = try GWSWorkspaceService(reader: GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: failedRangeRunner),
                                        cache: failedRangeStore)
                .refreshCalendarRange(range: range, now: now.addingTimeInterval(120))
            throw TestFailure(description: "failed calendar range unexpectedly committed a partial snapshot")
        } catch let failure as GWSFailure {
            if case .processFailed(_, 49, _) = failure { try check(true, "calendar range event failure surfaced") }
            else { throw TestFailure(description: "calendar range failure returned an unexpected error") }
        }
        try check(failedRangeStore.load() == baseline.snapshot,
                  "failed calendar range refresh must preserve the last complete cache snapshot")
    }
}
