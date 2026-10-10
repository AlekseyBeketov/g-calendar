import Darwin
import Foundation

struct SyntheticAcceptanceManifest: Equatable {
    let runMarker: String
    let calendarID: String
    let eventID: String
    let taskListID: String
    let taskID: String
}

final class SyntheticLedgerAcceptanceSession: @unchecked Sendable {
    private struct Ledger: Decodable {
        struct Record: Decodable {
            let kind: String
            let id: String
            let title: String
            let taskListID: String?
            let calendarID: String?

            enum CodingKeys: String, CodingKey {
                case kind, id, title
                case taskListID = "task_list_id"
                case calendarID = "calendar_id"
            }
        }

        let runMarker: String
        let created: [Record]

        enum CodingKeys: String, CodingKey {
            case runMarker = "run_marker"
            case created
        }
    }

    static func explicitLedgerURL(arguments: [String]) throws -> URL {
        guard arguments.filter({ $0 == "--acceptance-ledger" }).count == 1,
              let index = arguments.firstIndex(of: "--acceptance-ledger"),
              arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/"),
              !arguments[index + 1].hasSuffix("/") else {
            throw GWSFailure.forbiddenOperation
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    let manifest: SyntheticAcceptanceManifest
    let factory: GWSCommandFactory
    let runner: SyntheticLedgerAcceptanceRunner

    convenience init() throws {
        try self.init(ledgerURL: Self.explicitLedgerURL(arguments: ProcessInfo.processInfo.arguments))
    }

    init(ledgerURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: ledgerURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o077 == 0 else { throw GWSFailure.forbiddenOperation }
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: ledgerURL))
        guard !ledger.runMarker.isEmpty, ledger.runMarker.count >= 24 else { throw GWSFailure.invalidInput("test_ledger") }
        guard let list = ledger.created.first(where: { $0.kind == "task_list" }),
              let task = ledger.created.first(where: { $0.kind == "task" }),
              let event = ledger.created.first(where: { $0.kind == "event" }),
              let taskListID = task.taskListID, !taskListID.isEmpty,
              let calendarID = event.calendarID, !calendarID.isEmpty,
              list.id == taskListID,
              [list.id, task.id, event.id, calendarID].allSatisfy({ !$0.isEmpty }),
              [list.title, task.title, event.title].allSatisfy({ $0.contains(ledger.runMarker) }),
              Set([list.id, task.id, event.id]).count == 3 else {
            throw GWSFailure.invalidInput("test_ledger")
        }

        let executable = try GWSExecutableResolver().resolve(configuredPath: nil)
        let factory = GWSCommandFactory(executableURL: executable)
        manifest = SyntheticAcceptanceManifest(runMarker: ledger.runMarker,
                                               calendarID: calendarID,
                                               eventID: event.id,
                                               taskListID: list.id,
                                               taskID: task.id)
        self.factory = factory
        runner = SyntheticLedgerAcceptanceRunner(manifest: manifest, factory: factory, base: FoundationProcessRunner())
    }

    func loadSnapshot(requireAll: Bool) throws -> WorkspaceSnapshot {
        let reader = GWSReadClient(factory: factory, runner: runner)
        let remoteCalendar = try reader.readCalendar(id: manifest.calendarID)
        guard remoteCalendar.isWritable else { throw GWSFailure.forbiddenOperation }
        let list = try reader.taskList(id: manifest.taskListID)
        let task = try list == nil ? nil : reader.task(taskListID: manifest.taskListID, taskID: manifest.taskID)
        let event = try reader.event(identity: CalendarEventIdentity(calendarID: manifest.calendarID, eventID: manifest.eventID))

        if let list, !list.title.contains(manifest.runMarker) { throw GWSFailure.forbiddenOperation }
        if let task, !task.title.contains(manifest.runMarker) { throw GWSFailure.forbiddenOperation }
        if let event, !event.title.contains(manifest.runMarker) { throw GWSFailure.forbiddenOperation }
        if requireAll && (list == nil || task == nil || event == nil) { throw GWSFailure.resourceNotFound }

        // Do not display the user's real calendar name in this isolated acceptance surface.
        let calendar = CalendarInfo(id: remoteCalendar.id,
                                    title: "Синтетический календарь проверки",
                                    accessRole: remoteCalendar.accessRole,
                                    timeZoneID: remoteCalendar.timeZoneID,
                                    colorHex: remoteCalendar.colorHex)
        return WorkspaceSnapshot(calendars: [calendar],
                                 events: event.map { [$0] } ?? [],
                                 taskLists: list.map { [$0] } ?? [],
                                 tasks: task.map { [$0] } ?? [],
                                 fetchedAt: Date())
    }
}

final class SyntheticLedgerAcceptanceRunner: GWSProcessRunning, @unchecked Sendable {
    private let manifest: SyntheticAcceptanceManifest
    private let factory: GWSCommandFactory
    private let base: GWSProcessRunning
    private let reader: GWSReadClient

    init(manifest: SyntheticAcceptanceManifest, factory: GWSCommandFactory, base: GWSProcessRunning) {
        self.manifest = manifest
        self.factory = factory
        self.base = base
        reader = GWSReadClient(factory: factory, runner: base)
    }

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
        switch invocation.operation {
        case .calendarGet:
            try requireRead(invocation, command: ["calendar", "calendarList", "get"], parameters: ["calendarId": manifest.calendarID])
        case .eventGet:
            try requireRead(invocation, command: ["calendar", "events", "get"],
                            parameters: ["calendarId": manifest.calendarID, "eventId": manifest.eventID])
        case .taskListGet:
            try requireRead(invocation, command: ["tasks", "tasklists", "get"], parameters: ["tasklist": manifest.taskListID])
        case .taskGet:
            try requireRead(invocation, command: ["tasks", "tasks", "get"],
                            parameters: ["tasklist": manifest.taskListID, "task": manifest.taskID])
        case .eventPatch:
            let body = try requireMutation(invocation, command: ["calendar", "events", "patch"],
                                            parameters: ["calendarId": manifest.calendarID, "eventId": manifest.eventID],
                                            allowedBodyKeys: ["summary", "start", "end"])
            try requireMarkedEvent()
            if let summary = body["summary"] as? String, !summary.contains(manifest.runMarker) { throw GWSFailure.forbiddenOperation }
            return try base.run(invocation)
        case .eventDelete:
            _ = try requireMutation(invocation, command: ["calendar", "events", "delete"],
                                    parameters: ["calendarId": manifest.calendarID, "eventId": manifest.eventID],
                                    allowedBodyKeys: [])
            try requireMarkedEvent()
            return try base.run(invocation)
        case .taskPatch:
            let body = try requireMutation(invocation, command: ["tasks", "tasks", "patch"],
                                            parameters: ["tasklist": manifest.taskListID, "task": manifest.taskID],
                                            allowedBodyKeys: ["title", "status"])
            try requireMarkedTask()
            if let title = body["title"] as? String, !title.contains(manifest.runMarker) { throw GWSFailure.forbiddenOperation }
            if let status = body["status"] as? String, status != "completed" && status != "needsAction" { throw GWSFailure.forbiddenOperation }
            return try base.run(invocation)
        case .taskDelete:
            _ = try requireMutation(invocation, command: ["tasks", "tasks", "delete"],
                                    parameters: ["tasklist": manifest.taskListID, "task": manifest.taskID],
                                    allowedBodyKeys: [])
            try requireMarkedTask()
            return try base.run(invocation)
        case .taskListPatch:
            let body = try requireMutation(invocation, command: ["tasks", "tasklists", "patch"],
                                            parameters: ["tasklist": manifest.taskListID], allowedBodyKeys: ["title"])
            try requireMarkedTaskList()
            guard let title = body["title"] as? String, title.contains(manifest.runMarker) else { throw GWSFailure.forbiddenOperation }
            return try base.run(invocation)
        case .taskListDelete:
            _ = try requireMutation(invocation, command: ["tasks", "tasklists", "delete"],
                                    parameters: ["tasklist": manifest.taskListID], allowedBodyKeys: [])
            try requireMarkedTaskList()
            return try base.run(invocation)
        case .calendarList, .eventsList, .taskListsList, .tasksList,
             .eventInsert, .taskListInsert, .taskInsert, .taskMove:
            throw GWSFailure.forbiddenOperation
        }
        return try base.run(invocation)
    }

    private func requireMarkedEvent() throws {
        let event = try reader.readEvent(calendarID: manifest.calendarID, eventID: manifest.eventID)
        guard event.id == manifest.eventID, event.calendarID == manifest.calendarID,
              event.title.contains(manifest.runMarker), !event.recurring else { throw GWSFailure.forbiddenOperation }
    }

    private func requireMarkedTask() throws {
        let task = try reader.readTask(taskListID: manifest.taskListID, taskID: manifest.taskID)
        guard task.id == manifest.taskID, task.taskListID == manifest.taskListID,
              task.title.contains(manifest.runMarker), !task.deleted else { throw GWSFailure.forbiddenOperation }
    }

    private func requireMarkedTaskList() throws {
        let list = try reader.readTaskList(id: manifest.taskListID)
        guard list.id == manifest.taskListID, list.title.contains(manifest.runMarker) else { throw GWSFailure.forbiddenOperation }
    }

    private func requireRead(_ invocation: ProcessInvocation, command: [String], parameters expected: [String: String]) throws {
        let (parameters, body) = try parse(invocation, command: command, hasBody: false)
        guard body == nil, parameters.count == expected.count,
              expected.allSatisfy({ parameters[$0.key] as? String == $0.value }) else { throw GWSFailure.forbiddenOperation }
    }

    private func requireMutation(_ invocation: ProcessInvocation, command: [String], parameters expected: [String: String],
                                 allowedBodyKeys: Set<String>) throws -> [String: Any] {
        let (parameters, parsedBody) = try parse(invocation, command: command, hasBody: !allowedBodyKeys.isEmpty)
        let body = parsedBody ?? [:]
        guard parameters.count == expected.count,
              expected.allSatisfy({ parameters[$0.key] as? String == $0.value }),
              Set(body.keys).isSubset(of: allowedBodyKeys),
              (allowedBodyKeys.isEmpty ? body.isEmpty : !body.isEmpty) else { throw GWSFailure.forbiddenOperation }
        return body
    }

    private func parse(_ invocation: ProcessInvocation, command: [String], hasBody: Bool) throws -> ([String: Any], [String: Any]?) {
        let arguments = invocation.arguments
        let baseIndex = command.count
        guard Array(arguments.prefix(baseIndex)) == command,
              arguments.count == baseIndex + (hasBody ? 4 : 2),
              arguments[baseIndex] == "--params",
              let parameters = jsonDictionary(arguments[baseIndex + 1]) else { throw GWSFailure.forbiddenOperation }
        if hasBody {
            guard arguments[baseIndex + 2] == "--json",
                  let body = jsonDictionary(arguments[baseIndex + 3]) else { throw GWSFailure.forbiddenOperation }
            return (parameters, body)
        }
        return (parameters, nil)
    }

    private func jsonDictionary(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }
}
