import Foundation

enum AppLaunchMode: Equatable {
    case normal
    case demo
    case notificationStatus
    case notificationTest
    case ledgerAcceptance
    case syntheticAcceptance

    static func parse(arguments: [String]) -> AppLaunchMode {
        if arguments.contains("--synthetic-lifecycle") { return .syntheticAcceptance }
        if arguments.contains("--notification-test") { return .notificationTest }
        if arguments.contains("--notification-status") { return .notificationStatus }
        if arguments.contains("--demo") { return .demo }
        if arguments.contains("--ledger-acceptance") { return .ledgerAcceptance }
        return .normal
    }
}

enum DemoScenario: String {
    case ready, loading, setup, offline, stale, failed, empty, recovery, busy

    static func parse(arguments: [String]) -> DemoScenario {
        guard AppLaunchMode.parse(arguments: arguments) == .demo,
              let index = arguments.firstIndex(of: "--demo-state"), arguments.indices.contains(index + 1) else { return .ready }
        return DemoScenario(rawValue: arguments[index + 1]) ?? .ready
    }
}

struct RuntimeProcessBoundary {
    static func runner(for mode: AppLaunchMode, liveFactory: () -> GWSProcessRunning) -> GWSProcessRunning? {
        mode == .normal ? liveFactory() : nil
    }
}

enum ReminderLifecycleTrigger: CaseIterable {
    case appActivation
    case systemWake
}

enum ReminderLifecycleReconciliation {
    static func perform(for trigger: ReminderLifecycleTrigger, action: () async -> Void) async {
        switch trigger {
        case .appActivation, .systemWake:
            await action()
        }
    }
}

final class DemoWorkspaceAdapter {
    private let store: MemorySnapshotStore
    private(set) var simulatedMutationCount = 0
    private var createdEventCount = 0
    private var createdTaskListCount = 0
    private var createdTaskCount = 0

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        store = MemorySnapshotStore(Self.syntheticSnapshot(now: now, timeZone: timeZone))
    }

    func snapshot() -> WorkspaceSnapshot { store.load() ?? .empty }

    /// Accepts only an allowlisted synthetic UI action. This adapter has no process runner or network capability.
    func perform(_ invocation: ProcessInvocation) throws {
        guard let command = Self.commandPrefix(for: invocation.operation),
              Array(invocation.arguments.prefix(command.count)) == command else {
            throw GWSFailure.forbiddenOperation
        }

        var updated = snapshot()
        switch invocation.operation {
        case .eventInsert:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let body = try Self.dictionaryArgument("--json", in: invocation)
            try Self.requireNoAttendees(in: body)
            let calendarID = try Self.requiredString("calendarId", in: parameters)
            guard updated.calendars.contains(where: { $0.id == calendarID && $0.isWritable }) else {
                throw GWSFailure.forbiddenOperation
            }
            let title = try Self.requiredTitle(in: body, key: "summary")
            guard body["start"] is [String: Any], body["end"] is [String: Any] else {
                throw GWSFailure.invalidInput("event_time")
            }
            createdEventCount += 1
            var resource = body
            resource["id"] = "demo-created-event-\(createdEventCount)"
            resource["summary"] = title
            updated.events.append(try CalendarEvent.decode(resource, calendarID: calendarID))
        case .eventPatch:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let body = try Self.dictionaryArgument("--json", in: invocation)
            try Self.requireNoAttendees(in: body)
            let calendarID = try Self.requiredString("calendarId", in: parameters)
            let eventID = try Self.requiredString("eventId", in: parameters)
            guard let index = updated.events.firstIndex(where: { $0.id == eventID && $0.calendarID == calendarID }),
                  updated.calendars.contains(where: { $0.id == calendarID && $0.isWritable }),
                  !updated.events[index].recurring else { throw GWSFailure.forbiddenOperation }
            if body["summary"] != nil { updated.events[index].title = try Self.requiredTitle(in: body, key: "summary") }
            if let start = body["start"] as? [String: Any] { updated.events[index].start = try EventTime.decode(start) }
            if let end = body["end"] as? [String: Any] { updated.events[index].end = try EventTime.decode(end) }
            guard body["summary"] != nil || body["start"] != nil || body["end"] != nil else {
                throw GWSFailure.invalidInput("event_patch")
            }
        case .eventDelete:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let calendarID = try Self.requiredString("calendarId", in: parameters)
            let eventID = try Self.requiredString("eventId", in: parameters)
            guard let event = updated.events.first(where: { $0.id == eventID && $0.calendarID == calendarID }),
                  updated.calendars.contains(where: { $0.id == calendarID && $0.isWritable }),
                  !event.recurring else { throw GWSFailure.forbiddenOperation }
            updated.events.removeAll { $0.id == eventID && $0.calendarID == calendarID }
        case .taskListInsert:
            let body = try Self.dictionaryArgument("--json", in: invocation)
            let title = try Self.requiredTitle(in: body, key: "title")
            createdTaskListCount += 1
            updated.taskLists.append(TaskList(id: "demo-created-task-list-\(createdTaskListCount)", title: title, updated: Date()))
        case .taskListPatch:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let body = try Self.dictionaryArgument("--json", in: invocation)
            let listID = try Self.requiredString("tasklist", in: parameters)
            guard let index = updated.taskLists.firstIndex(where: { $0.id == listID }) else { throw GWSFailure.resourceNotFound }
            updated.taskLists[index].title = try Self.requiredTitle(in: body, key: "title")
            updated.taskLists[index].updated = Date()
        case .taskListDelete:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let listID = try Self.requiredString("tasklist", in: parameters)
            guard updated.taskLists.contains(where: { $0.id == listID }) else { throw GWSFailure.resourceNotFound }
            updated.taskLists.removeAll { $0.id == listID }
            updated.tasks.removeAll { $0.taskListID == listID }
        case .taskInsert:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let body = try Self.dictionaryArgument("--json", in: invocation)
            let listID = try Self.requiredString("tasklist", in: parameters)
            guard updated.taskLists.contains(where: { $0.id == listID }) else { throw GWSFailure.resourceNotFound }
            createdTaskCount += 1
            updated.tasks.append(GoogleTask(id: "demo-created-task-\(createdTaskCount)", taskListID: listID,
                                            title: try Self.requiredTitle(in: body, key: "title"),
                                            notes: try Self.optionalString("notes", in: body),
                                            due: try Self.dueDate(in: body), completed: false, deleted: false, updated: Date()))
        case .taskPatch:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let body = try Self.dictionaryArgument("--json", in: invocation)
            let listID = try Self.requiredString("tasklist", in: parameters)
            let taskID = try Self.requiredString("task", in: parameters)
            guard let index = updated.tasks.firstIndex(where: { $0.id == taskID && $0.taskListID == listID }) else {
                throw GWSFailure.resourceNotFound
            }
            if body["title"] != nil { updated.tasks[index].title = try Self.requiredTitle(in: body, key: "title") }
            if body["notes"] != nil { updated.tasks[index].notes = try Self.optionalString("notes", in: body) }
            if body["due"] != nil { updated.tasks[index].due = try Self.dueDate(in: body) }
            if let status = body["status"] as? String {
                guard status == "completed" || status == "needsAction" else { throw GWSFailure.invalidInput("task_status") }
                updated.tasks[index].completed = status == "completed"
            }
            guard body["title"] != nil || body["notes"] != nil || body["due"] != nil || body["status"] != nil else {
                throw GWSFailure.invalidInput("task_patch")
            }
            updated.tasks[index].updated = Date()
        case .taskMove:
            guard !invocation.arguments.contains("--json") else { throw GWSFailure.forbiddenOperation }
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let source = try Self.requiredString("tasklist", in: parameters)
            let taskID = try Self.requiredString("task", in: parameters)
            let destination = try Self.requiredString("destinationTasklist", in: parameters)
            guard source != destination, updated.taskLists.contains(where: { $0.id == destination }),
                  let index = updated.tasks.firstIndex(where: { $0.id == taskID && $0.taskListID == source }) else {
                throw GWSFailure.resourceNotFound
            }
            let task = updated.tasks[index]
            updated.tasks[index] = GoogleTask(id: task.id, taskListID: destination, title: task.title, notes: task.notes,
                                              due: task.due, completed: task.completed, deleted: task.deleted, updated: Date())
        case .taskDelete:
            let parameters = try Self.dictionaryArgument("--params", in: invocation)
            let listID = try Self.requiredString("tasklist", in: parameters)
            let taskID = try Self.requiredString("task", in: parameters)
            guard updated.tasks.contains(where: { $0.id == taskID && $0.taskListID == listID }) else {
                throw GWSFailure.resourceNotFound
            }
            updated.tasks.removeAll { $0.id == taskID && $0.taskListID == listID }
        default:
            throw GWSFailure.forbiddenOperation
        }
        updated.fetchedAt = Date()
        try store.commit(updated)
        simulatedMutationCount += 1
    }

    private static func commandPrefix(for operation: GWSOperation) -> [String]? {
        switch operation {
        case .eventInsert: return ["calendar", "events", "insert"]
        case .eventPatch: return ["calendar", "events", "patch"]
        case .eventDelete: return ["calendar", "events", "delete"]
        case .taskListInsert: return ["tasks", "tasklists", "insert"]
        case .taskListPatch: return ["tasks", "tasklists", "patch"]
        case .taskListDelete: return ["tasks", "tasklists", "delete"]
        case .taskInsert: return ["tasks", "tasks", "insert"]
        case .taskPatch: return ["tasks", "tasks", "patch"]
        case .taskMove: return ["tasks", "tasks", "move"]
        case .taskDelete: return ["tasks", "tasks", "delete"]
        default: return nil
        }
    }

    private static func dictionaryArgument(_ flag: String, in invocation: ProcessInvocation) throws -> [String: Any] {
        guard let index = invocation.arguments.firstIndex(of: flag), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dictionary = value as? [String: Any] else { throw GWSFailure.invalidInput("demo_arguments") }
        return dictionary
    }

    private static func requiredString(_ key: String, in values: [String: Any]) throws -> String {
        guard let value = values[key] as? String, !value.isEmpty else { throw GWSFailure.invalidInput("demo_\(key)") }
        return value
    }

    private static func requiredTitle(in values: [String: Any], key: String) throws -> String {
        let title = try requiredString(key, in: values)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GWSFailure.invalidInput("demo_title") }
        return title
    }

    private static func optionalString(_ key: String, in values: [String: Any]) throws -> String? {
        guard let value = values[key] else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else { throw GWSFailure.invalidInput("demo_\(key)") }
        return string
    }

    private static func dueDate(in values: [String: Any]) throws -> DateOnly? {
        guard let value = values["due"] else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String, let date = DateOnly(rawValue: String(string.prefix(10))) else {
            throw GWSFailure.invalidInput("demo_due")
        }
        return date
    }

    private static func requireNoAttendees(in body: [String: Any]) throws {
        guard body["attendees"] == nil, body["attendeeEmails"] == nil else { throw GWSFailure.forbiddenOperation }
    }

    private static func syntheticSnapshot(now: Date, timeZone: TimeZone) -> WorkspaceSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? now.addingTimeInterval(900)
        let end = start.addingTimeInterval(60 * 60)
        let calendarID = "demo-calendar"
        let listID = "demo-task-list"
        let todayDue = DateOnly(date: today, timeZone: timeZone)
        let yesterdayDue = calendar.date(byAdding: .day, value: -1, to: today).map { DateOnly(date: $0, timeZone: timeZone) }
        let tomorrowDue = calendar.date(byAdding: .day, value: 1, to: today).map { DateOnly(date: $0, timeZone: timeZone) }
        let event = CalendarEvent(id: "demo-event", calendarID: calendarID, title: "Демо: встреча",
                                  start: EventTime(rawValue: ISO8601.format(start), instant: start, dateOnly: nil, timeZoneID: timeZone.identifier),
                                  end: EventTime(rawValue: ISO8601.format(end), instant: end, dateOnly: nil, timeZoneID: timeZone.identifier),
                                  recurring: false, status: "confirmed")
        let datedTask = GoogleTask(id: "demo-task-dated", taskListID: listID, title: "Демо: задача на сегодня",
                                   notes: nil, due: DateOnly(date: now, timeZone: timeZone), completed: false, deleted: false, updated: nil)
        let timelessTask = GoogleTask(id: "demo-task-undated", taskListID: listID, title: "Демо: задача без срока",
                                      notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let overflowTasks = (1...48).map { index -> GoogleTask in
            let due: DateOnly?
            switch index % 4 {
            case 0: due = yesterdayDue
            case 1: due = todayDue
            case 2: due = tomorrowDue
            default: due = nil
            }
            return GoogleTask(id: "demo-task-scroll-\(index)", taskListID: listID,
                              title: "Демо: пункт списка \(index)", notes: nil, due: due,
                              completed: index.isMultiple(of: 7), deleted: false, updated: nil)
        }
        let readOnlyID = "demo-readonly-calendar"
        let readOnlyEvent = CalendarEvent(id: "demo-recurring-event", calendarID: readOnlyID, title: "Демо: повторяющийся обзор",
                                         start: event.start, end: event.end, recurring: true, status: "confirmed")
        let allDayEvents = (1...8).compactMap { index -> CalendarEvent? in
            guard let endDay = todayDue.adding(days: 1) else { return nil }
            return CalendarEvent(id: "demo-all-day-\(index)", calendarID: calendarID,
                                 title: "Демо: событие на весь день \(index) с длинным названием для проверки переноса",
                                 start: EventTime(rawValue: todayDue.description, instant: nil, dateOnly: todayDue, timeZoneID: nil),
                                 end: EventTime(rawValue: endDay.description, instant: nil, dateOnly: endDay, timeZoneID: nil),
                                 recurring: false, status: "confirmed")
        }
        let alternateTask = GoogleTask(id: "demo-task-alternate", taskListID: "demo-second-list", title: "Демо: проверить другой список",
                                       notes: "Синтетические заметки для проверки редактора", due: tomorrowDue, completed: false, deleted: false, updated: nil)
        let readabilityEvents = [1, 5, 10, 15, 30, 60, 120].enumerated().map { index, minutes -> CalendarEvent in
            let instant = start.addingTimeInterval(Double(index * 90) * 60)
            let finish = instant.addingTimeInterval(Double(minutes) * 60)
            return CalendarEvent(id: "demo-readable-\(minutes)", calendarID: calendarID,
                                 title: index.isMultiple(of: 2) ? "Короткая встреча · \(minutes) мин" : "Длинное нейтральное название события для проверки переноса и многоточия · \(minutes) мин",
                                 start: EventTime(rawValue: ISO8601.format(instant), instant: instant, dateOnly: nil, timeZoneID: timeZone.identifier),
                                 end: EventTime(rawValue: ISO8601.format(finish), instant: finish, dateOnly: nil, timeZoneID: timeZone.identifier),
                                 recurring: false, status: "confirmed")
        }
        let closeStart = start.addingTimeInterval(10 * 60)
        let closeEnd = closeStart.addingTimeInterval(5 * 60)
        let closeEvent = CalendarEvent(id: "demo-readable-near", calendarID: readOnlyID, title: "Короткий повторяющийся обзор",
                                      start: EventTime(rawValue: ISO8601.format(closeStart), instant: closeStart, dateOnly: nil, timeZoneID: timeZone.identifier),
                                      end: EventTime(rawValue: ISO8601.format(closeEnd), instant: closeEnd, dateOnly: nil, timeZoneID: timeZone.identifier),
                                      recurring: true, status: "confirmed")
        let lateStart = calendar.date(bySettingHour: 23, minute: 55, second: 0, of: today)!
        let lateEnd = lateStart.addingTimeInterval(4 * 60)
        let lateEvent = CalendarEvent(id: "demo-readable-late", calendarID: readOnlyID, title: "Завершение дня",
                                     start: EventTime(rawValue: ISO8601.format(lateStart), instant: lateStart, dateOnly: nil, timeZoneID: timeZone.identifier),
                                     end: EventTime(rawValue: ISO8601.format(lateEnd), instant: lateEnd, dateOnly: nil, timeZoneID: timeZone.identifier),
                                     recurring: false, status: "confirmed")
        var snapshot = WorkspaceSnapshot(calendars: [CalendarInfo(id: calendarID, title: "Демо-календарь", accessRole: "writer",
                                                                    timeZoneID: timeZone.identifier, colorHex: "#0B57D0"),
                                                    CalendarInfo(id: readOnlyID, title: "Демо: календарь только для просмотра с длинным названием",
                                                                 accessRole: "reader", timeZoneID: timeZone.identifier, colorHex: "#188038")],
                                         events: [event, readOnlyEvent] + allDayEvents + readabilityEvents + [closeEvent, lateEvent],
                                         taskLists: [TaskList(id: listID, title: "Демо-список", updated: nil),
                                                     TaskList(id: "demo-second-list", title: "Демо: второй список с длинным названием", updated: nil)],
                                         tasks: [datedTask, timelessTask] + overflowTasks + [alternateTask],
                                         fetchedAt: now)
        if let interval = calendar.dateInterval(of: .weekOfYear, for: today),
           let range = try? DateRange(start: interval.start, endExclusive: interval.end, timeZone: timeZone) {
            snapshot.calendarCoverage = CalendarRangeCoverage(range: range)
        }
        return snapshot
    }
}
