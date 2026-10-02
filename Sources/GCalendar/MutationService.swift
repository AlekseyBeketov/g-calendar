import Foundation

struct GWSMutationService {
    let runner: GWSProcessRunning

    func perform(_ invocation: ProcessInvocation, reader: GWSReadClient? = nil) throws -> GWSMutationResult {
        let result = try runner.run(invocation)
        guard result.exitCode == 0 else {
            throw GWSFailure.processFailed(invocation.operation.rawValue, result.exitCode, "command_failure")
        }

        let params = dictionaryArgument(named: "--params", in: invocation) ?? [:]
        let body = dictionaryArgument(named: "--json", in: invocation) ?? [:]
        switch invocation.operation {
        case .eventInsert:
            guard let reader, let calendarID = params["calendarId"] as? String,
                  let resourceID = resourceID(from: result.stdout) else { throw GWSFailure.mutationNotVerified }
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
            guard let reader, let resourceID = resourceID(from: result.stdout),
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
                  let resourceID = resourceID(from: result.stdout) else { throw GWSFailure.mutationNotVerified }
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
        if let notes = body["notes"] as? String, task.notes != notes { throw GWSFailure.mutationNotVerified }
        if let due = body["due"] as? String, task.due != DateOnly(rawValue: String(due.prefix(10))) { throw GWSFailure.mutationNotVerified }
        if body["due"] is NSNull, task.due != nil { throw GWSFailure.mutationNotVerified }
        if let status = body["status"] as? String, task.completed != (status == "completed") { throw GWSFailure.mutationNotVerified }
    }

    private func verify(taskList: TaskList, against body: [String: Any]) throws {
        if let title = body["title"] as? String, taskList.title != title { throw GWSFailure.mutationNotVerified }
    }
}

enum GWSMutationResult: Equatable {
    case eventVerified(CalendarEvent)
    case taskListVerified(TaskList)
    case taskVerified(GoogleTask)
    case resourceDeleted
    case requestAccepted

    var isReadBackVerified: Bool {
        switch self { case .eventVerified, .taskListVerified, .taskVerified, .resourceDeleted: return true; case .requestAccepted: return false }
    }
}
