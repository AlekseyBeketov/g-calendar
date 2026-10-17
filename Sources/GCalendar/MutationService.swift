import Foundation

struct GWSMutationService {
    let runner: GWSProcessRunning

    func perform(_ invocation: ProcessInvocation, reader: GWSReadClient? = nil) throws -> GWSMutationResult {
        let result = try runner.run(invocation)
        guard result.exitCode == 0 else {
            throw GWSFailure.processFailed(invocation.operation.rawValue, result.exitCode, "command_failure")
        }

        return try verifyAccepted(invocation, response: result.stdout, reader: reader)
    }

    // This path never invokes the write runner. It is also used for recovery after restart.
    func verifyAccepted(_ invocation: ProcessInvocation, response: Data, reader: GWSReadClient?) throws -> GWSMutationResult {

        let params = dictionaryArgument(named: "--params", in: invocation) ?? [:]
        let body = dictionaryArgument(named: "--json", in: invocation) ?? [:]
        switch invocation.operation {
        case .calendarInsert:
            guard let reader, let resourceID = resourceID(from: response) else { throw GWSFailure.mutationNotVerified }
            let calendar = try reader.readCalendar(id: resourceID)
            guard calendar.id == resourceID, calendar.accessRole == "owner",
                  calendar.title == body["summary"] as? String,
                  calendar.timeZoneID == body["timeZone"] as? String else { throw GWSFailure.mutationNotVerified }
            return .calendarVerified(calendar)
        case .eventInsert:
            guard let reader, let calendarID = params["calendarId"] as? String,
                  let resourceID = resourceID(from: response) else { throw GWSFailure.mutationNotVerified }
            guard let event = try reader.event(identity: CalendarEventIdentity(calendarID: calendarID, eventID: resourceID)),
                  event.id == resourceID, event.calendarID == calendarID else {
                throw GWSFailure.mutationNotVerified
            }
            try verify(event: event, against: body)
            return .eventVerified(event)
        case .eventPatch:
            guard let reader, let calendarID = params["calendarId"] as? String, let resourceID = params["eventId"] as? String,
                  let event = try reader.event(identity: CalendarEventIdentity(calendarID: calendarID, eventID: resourceID)),
                  event.id == resourceID, event.calendarID == calendarID else {
                throw GWSFailure.mutationNotVerified
            }
            try verify(event: event, against: body)
            return .eventVerified(event)
        case .taskListInsert:
            guard let reader, let resourceID = resourceID(from: response),
                  let taskList = try reader.taskList(id: resourceID), taskList.id == resourceID else {
                throw GWSFailure.mutationNotVerified
            }
            try verify(taskList: taskList, against: body)
            return .taskListVerified(taskList)
        case .taskListPatch:
            guard let reader, let resourceID = params["tasklist"] as? String,
                  let taskList = try reader.taskList(id: resourceID), taskList.id == resourceID else {
                throw GWSFailure.mutationNotVerified
            }
            try verify(taskList: taskList, against: body)
            return .taskListVerified(taskList)
        case .taskListDelete:
            guard let reader, let resourceID = params["tasklist"] as? String,
                  try reader.taskList(id: resourceID) == nil else { throw GWSFailure.mutationNotVerified }
            return .resourceDeleted
        case .taskInsert:
            guard let reader, let taskListID = params["tasklist"] as? String,
                  let resourceID = resourceID(from: response) else { throw GWSFailure.mutationNotVerified }
            guard let task = try reader.task(taskListID: taskListID, taskID: resourceID),
                  task.id == resourceID, task.taskListID == taskListID else { throw GWSFailure.mutationNotVerified }
            try verify(task: task, against: body)
            return .taskVerified(task)
        case .taskPatch:
            guard let reader, let taskListID = params["tasklist"] as? String, let resourceID = params["task"] as? String,
                  let task = try reader.task(taskListID: taskListID, taskID: resourceID),
                  task.id == resourceID, task.taskListID == taskListID else { throw GWSFailure.mutationNotVerified }
            try verify(task: task, against: body)
            return .taskVerified(task)
        case .taskMove:
            guard let reader, let source = params["tasklist"] as? String, let sourceID = params["task"] as? String,
                  let destination = params["destinationTasklist"] as? String, !destination.isEmpty, source != destination,
                  let expected = invocation.expectedTask, expected.id == sourceID, expected.taskListID == source,
                  !invocation.arguments.contains("--json") else { throw GWSFailure.mutationNotVerified }
            let destinationID = resourceID(from: response) ?? sourceID
            guard let moved = try reader.task(taskListID: destination, taskID: destinationID),
                  moved.id == destinationID, moved.taskListID == destination, !moved.deleted,
                  moved.title == expected.title, (moved.notes ?? "") == (expected.notes ?? ""),
                  moved.due == expected.due, moved.completed == expected.completed else { throw GWSFailure.mutationNotVerified }
            let remainingSource = try reader.task(taskListID: source, taskID: sourceID)
            guard remainingSource == nil || remainingSource?.deleted == true else { throw GWSFailure.mutationNotVerified }
            return .taskVerified(moved)
        case .taskReorder:
            guard let reader, let listID = params["tasklist"] as? String, let taskID = params["task"] as? String,
                  let expected = invocation.expectedTask, expected.id == taskID, expected.taskListID == listID,
                  !expected.completed, !expected.deleted, !invocation.arguments.contains("--json"),
                  params["destinationTasklist"] == nil, (params["parent"] as? String) == expected.parent else {
                throw GWSFailure.mutationNotVerified
            }
            // Complete pagination is mandatory: a filtered/partial board cannot prove adjacency.
            let allTasks = try reader.tasks(taskListID: listID)
            guard let task = allTasks.first(where: { $0.id == taskID && $0.taskListID == listID }),
                  !task.deleted, task.parent == expected.parent, task.completed == expected.completed,
                  task.title == expected.title, (task.notes ?? "") == (expected.notes ?? ""), task.due == expected.due else {
                throw GWSFailure.mutationNotVerified
            }
            let siblings = allTasks.filter { $0.taskListID == listID && $0.parent == expected.parent && !$0.deleted }
            guard siblings.allSatisfy({ !($0.position ?? "").isEmpty }),
                  Set(siblings.compactMap(\.position)).count == siblings.count else { throw GWSFailure.mutationNotVerified }
            let ordered = siblings.sorted { $0.position! < $1.position! }
            guard let index = ordered.firstIndex(where: { $0.id == taskID }) else { throw GWSFailure.mutationNotVerified }
            if let previous = params["previous"] as? String {
                guard index > 0, ordered[index - 1].id == previous else { throw GWSFailure.mutationNotVerified }
            } else {
                guard index == 0 else { throw GWSFailure.mutationNotVerified }
            }
            return .taskVerified(task)
        case .eventDelete:
            guard let reader, let calendarID = params["calendarId"] as? String, let resourceID = params["eventId"] as? String,
                  try reader.event(identity: CalendarEventIdentity(calendarID: calendarID, eventID: resourceID)) == nil else {
                throw GWSFailure.mutationNotVerified
            }
            return .resourceDeleted
        case .taskDelete:
            guard let reader, let taskListID = params["tasklist"] as? String, let resourceID = params["task"] as? String,
                  try reader.task(taskListID: taskListID, taskID: resourceID) == nil else { throw GWSFailure.mutationNotVerified }
            return .resourceDeleted
        default:
            return .requestAccepted
        }
    }

    private func dictionaryArgument(named flag: String, in invocation: ProcessInvocation) -> [String: Any]? {
        guard let index = invocation.arguments.firstIndex(of: flag), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func resourceID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return id
    }

    private func verify(event: CalendarEvent, against body: [String: Any]) throws {
        if let summary = body["summary"] as? String, event.title != summary { throw GWSFailure.mutationNotVerified }
        for key in ["start", "end"] {
            guard let expected = body[key] as? [String: Any] else { continue }
            if let expectedDate = expected["date"] as? String {
                guard event.isAllDay, (key == "start" ? event.start.dateOnly?.description : event.end.dateOnly?.description) == expectedDate else {
                    throw GWSFailure.mutationNotVerified
                }
            }
            if let expectedDateTime = expected["dateTime"] as? String {
                guard let expectedInstant = ISO8601.parse(expectedDateTime),
                      (key == "start" ? event.start.instant : event.end.instant) == expectedInstant else {
                    throw GWSFailure.mutationNotVerified
                }
            }
            if let expectedTimeZone = expected["timeZone"] as? String {
                guard (key == "start" ? event.start.timeZoneID : event.end.timeZoneID) == expectedTimeZone else {
                    throw GWSFailure.mutationNotVerified
                }
            }
        }
    }

    private func verify(task: GoogleTask, against body: [String: Any]) throws {
        if let title = body["title"] as? String, task.title != title { throw GWSFailure.mutationNotVerified }
        if let notes = body["notes"] as? String, (task.notes ?? "") != notes { throw GWSFailure.mutationNotVerified }
        if let due = body["due"] as? String, task.due != DateOnly(rawValue: String(due.prefix(10))) { throw GWSFailure.mutationNotVerified }
        if body["due"] is NSNull, task.due != nil { throw GWSFailure.mutationNotVerified }
        if let status = body["status"] as? String, task.completed != (status == "completed") { throw GWSFailure.mutationNotVerified }
    }

    private func verify(taskList: TaskList, against body: [String: Any]) throws {
        if let title = body["title"] as? String, taskList.title != title { throw GWSFailure.mutationNotVerified }
    }
}

enum GWSMutationResult: Equatable {
    case calendarVerified(CalendarInfo)
    case eventVerified(CalendarEvent)
    case taskListVerified(TaskList)
    case taskVerified(GoogleTask)
    case resourceDeleted
    case requestAccepted

    var isReadBackVerified: Bool {
        switch self { case .calendarVerified, .eventVerified, .taskListVerified, .taskVerified, .resourceDeleted: return true; case .requestAccepted: return false }
    }
}
