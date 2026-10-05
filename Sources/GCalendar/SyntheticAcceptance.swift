import Foundation

/// Explicit opt-in native-app adapter acceptance. It never opens the user's cache,
/// edits existing objects, finds objects by title, or repeats an unresolved INSERT.
final class SyntheticAcceptanceRun {
    private struct Record: Codable {
        let kind: String
        let id: String
        let parentID: String?
        var deleted = false
    }
    private struct Ledger: Codable {
        let runMarker: String
        var created: [Record] = []
        var verifiedSteps = 0
        var complete = false
    }

    let directory: URL
    private let reader: GWSReadClient
    private let factory: GWSCommandFactory
    private let runner: GWSProcessRunning
    private let journal: MutationJournal
    private lazy var service = RecoverableMutationService(runner: runner, journal: journal, onAccepted: { [weak self] pending in
        guard let self, let id = pending.resourceID else { return }
        switch pending.operation {
        case .eventInsert:
            let parameters = self.parameters(pending.arguments)
            try self.remember("event", id: id, parentID: parameters["calendarId"] as? String)
        case .taskListInsert: try self.remember("task_list", id: id, parentID: nil)
        case .taskInsert:
            let parameters = self.parameters(pending.arguments)
            try self.remember("task", id: id, parentID: parameters["tasklist"] as? String)
        default: break
        }
    })
    private var ledger: Ledger
    private(set) var stepMilliseconds: [Double] = []

    init(directory: URL, factory: GWSCommandFactory, runner: GWSProcessRunning, finishExistingCleanup: Bool = false) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw GWSFailure.invalidInput("acceptance_directory") }
        if finishExistingCleanup {
            let saved = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: directory.appendingPathComponent("ledger.json")))
            let prefix = "g-calendar-acceptance-"
            guard saved.runMarker.hasPrefix(prefix), UUID(uuidString: String(saved.runMarker.dropFirst(prefix.count))) != nil,
                  saved.created.count == 3, Set(saved.created.map(\.kind)) == Set(["event", "task_list", "task"]),
                  saved.created.allSatisfy({ !$0.id.isEmpty }), (8...10).contains(saved.verifiedSteps), !saved.complete else {
                throw GWSFailure.forbiddenOperation
            }
            ledger = saved
        } else {
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw GWSFailure.invalidInput("fresh_acceptance_directory") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            ledger = Ledger(runMarker: "g-calendar-acceptance-\(UUID().uuidString)")
        }
        self.directory = directory
        self.factory = factory
        reader = GWSReadClient(factory: factory, runner: runner)
        self.runner = runner
        journal = MutationJournal(fileURL: directory.appendingPathComponent("pending.json"))
        try saveLedger()
    }

    func run(now: Date = Date()) throws -> Int {
        guard ledger.created.isEmpty, !journal.isBlocked else { throw GWSFailure.forbiddenOperation }
        guard let owner = try reader.calendars().first(where: { $0.accessRole == "owner" }) else { throw GWSFailure.forbiddenOperation }
        let calendar = try reader.readCalendar(id: owner.id)
        guard calendar.accessRole == "owner", calendar.isWritable else { throw GWSFailure.forbiddenOperation }
        let marker = ledger.runMarker
        let start = now.addingTimeInterval(86_400)
        let eventBody: [String: Any] = ["summary": "\(marker) event",
                                       "start": ["dateTime": ISO8601.format(start), "timeZone": "UTC"],
                                       "end": ["dateTime": ISO8601.format(start.addingTimeInterval(3_600)), "timeZone": "UTC"],
                                       "reminders": ["useDefault": false]]
        guard case .eventVerified(let createdEvent) = try execute(factory.eventInsert(calendar: calendar, body: eventBody, authorization: .userSave)) else {
            throw GWSFailure.mutationNotVerified
        }
        try remember("event", id: createdEvent.id, parentID: calendar.id)
        guard case .taskListVerified(let createdList) = try execute(factory.taskListInsert(title: "\(marker) list", authorization: .userSave)) else {
            throw GWSFailure.mutationNotVerified
        }
        try remember("task_list", id: createdList.id, parentID: nil)
        guard case .taskVerified(let createdTask) = try execute(factory.taskInsert(taskListID: createdList.id, title: "\(marker) task", notes: "", due: DateOnly(date: start), authorization: .userSave)) else {
            throw GWSFailure.mutationNotVerified
        }
        try remember("task", id: createdTask.id, parentID: createdList.id)

        let event = try markedEvent(calendarID: calendar.id, id: createdEvent.id)
        _ = try execute(factory.eventPatch(event: event, calendar: calendar, body: ["summary": "\(marker) event edited"], authorization: .userSave))
        let list = try markedList(id: createdList.id)
        _ = try execute(factory.taskListPatch(id: list.id, title: "\(marker) list edited", authorization: .userSave))
        let task = try markedTask(listID: createdList.id, id: createdTask.id)
        _ = try execute(factory.taskPatch(task: task, title: "\(marker) task edited", notes: "Synthetic notes", due: task.due, authorization: .userSave))
        let edited = try markedTask(listID: createdList.id, id: createdTask.id)
        _ = try execute(factory.taskPatch(task: edited, title: edited.title, notes: edited.notes, due: edited.due, completed: true, authorization: .userCompletionToggle))
        let completed = try markedTask(listID: createdList.id, id: createdTask.id)
        _ = try execute(factory.taskPatch(task: completed, title: completed.title, notes: completed.notes, due: completed.due, completed: false, authorization: .userCompletionToggle))

        let reopened = try markedTask(listID: createdList.id, id: createdTask.id)
        _ = try execute(factory.taskDelete(task: reopened, authorization: .confirmedDelete))
        try markDeleted(createdTask.id)
        let editedEvent = try markedEvent(calendarID: calendar.id, id: createdEvent.id)
        _ = try execute(factory.eventDelete(event: editedEvent, calendar: calendar, authorization: .confirmedDelete))
        try markDeleted(createdEvent.id)
        let editedList = try markedList(id: createdList.id)
        // Only this run's task has been created here and its exact deletion is already verified.
        _ = try execute(factory.taskListDelete(id: editedList.id, authorization: .confirmedDelete))
        try markDeleted(createdList.id)
        ledger.complete = ledger.created.count == 3 && ledger.created.allSatisfy(\.deleted)
        try saveLedger()
        return ledger.verifiedSteps
    }

    /// Resume only the deletion phase. An unresolved DELETE is checked with GET
    /// before continuing; this path cannot repeat INSERT or edit an existing object.
    func finishExistingCleanup() throws -> Int {
        guard (8...10).contains(ledger.verifiedSteps), ledger.created.count == 3 else { throw GWSFailure.forbiddenOperation }
        if let pending = journal.pending {
            let kind: String
            switch pending.operation {
            case .taskDelete: kind = "task"
            case .eventDelete: kind = "event"
            case .taskListDelete: kind = "task_list"
            default: throw GWSFailure.forbiddenOperation
            }
            let params = parameters(pending.arguments)
            guard let id = pending.resourceID,
                  let owned = ledger.created.first(where: { $0.kind == kind && $0.id == id && !$0.deleted }),
                  (kind != "task" || (params["tasklist"] as? String == owned.parentID && params["task"] as? String == id)),
                  (kind != "event" || (params["calendarId"] as? String == owned.parentID && params["eventId"] as? String == id)),
                  (kind != "task_list" || params["tasklist"] as? String == id) else { throw GWSFailure.forbiddenOperation }
            _ = try service.recheck(reader: reader)
            ledger.verifiedSteps += 1
            try markDeleted(id)
        }
        for kind in ["task", "event", "task_list"] {
            guard let owned = ledger.created.first(where: { $0.kind == kind && !$0.deleted }) else { continue }
            let invocation: ProcessInvocation
            switch kind {
            case "task":
                guard let parent = owned.parentID else { throw GWSFailure.forbiddenOperation }
                invocation = try factory.taskDelete(task: markedTask(listID: parent, id: owned.id), authorization: .confirmedDelete)
            case "event":
                guard let parent = owned.parentID else { throw GWSFailure.forbiddenOperation }
                let calendar = try reader.readCalendar(id: parent)
                guard calendar.accessRole == "owner" else { throw GWSFailure.forbiddenOperation }
                invocation = try factory.eventDelete(event: markedEvent(calendarID: parent, id: owned.id), calendar: calendar, authorization: .confirmedDelete)
            default:
                invocation = try factory.taskListDelete(id: markedList(id: owned.id).id, authorization: .confirmedDelete)
            }
            _ = try execute(invocation)
            try markDeleted(owned.id)
        }
        ledger.complete = ledger.verifiedSteps == 11 && ledger.created.allSatisfy(\.deleted)
        try saveLedger()
        guard ledger.complete else { throw GWSFailure.mutationNotVerified }
        return ledger.verifiedSteps
    }

    private func execute(_ invocation: ProcessInvocation) throws -> GWSMutationResult {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try service.perform(invocation, reader: reader)
        stepMilliseconds.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        guard result.isReadBackVerified else { throw GWSFailure.mutationNotVerified }
        ledger.verifiedSteps += 1
        try saveLedger()
        return result
    }

    private func markedEvent(calendarID: String, id: String) throws -> CalendarEvent {
        guard ledger.created.contains(where: { $0.kind == "event" && $0.id == id && $0.parentID == calendarID && !$0.deleted }) else { throw GWSFailure.forbiddenOperation }
        let value = try reader.readEvent(calendarID: calendarID, eventID: id)
        guard value.title.contains(ledger.runMarker), !value.recurring else { throw GWSFailure.forbiddenOperation }
        return value
    }

    private func markedTask(listID: String, id: String) throws -> GoogleTask {
        guard ledger.created.contains(where: { $0.kind == "task" && $0.id == id && $0.parentID == listID && !$0.deleted }) else { throw GWSFailure.forbiddenOperation }
        let value = try reader.readTask(taskListID: listID, taskID: id)
        guard value.title.contains(ledger.runMarker), !value.deleted else { throw GWSFailure.forbiddenOperation }
        return value
    }

    private func markedList(id: String) throws -> TaskList {
        guard ledger.created.contains(where: { $0.kind == "task_list" && $0.id == id && !$0.deleted }) else { throw GWSFailure.forbiddenOperation }
        let value = try reader.readTaskList(id: id)
        guard value.title.contains(ledger.runMarker) else { throw GWSFailure.forbiddenOperation }
        return value
    }

    private func remember(_ kind: String, id: String, parentID: String?) throws {
        if ledger.created.contains(where: { $0.kind == kind && $0.id == id && $0.parentID == parentID }) { return }
        ledger.created.append(Record(kind: kind, id: id, parentID: parentID))
        try saveLedger()
    }

    private func parameters(_ arguments: [String]) -> [String: Any] {
        guard let index = arguments.firstIndex(of: "--params"), arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }

    private func markDeleted(_ id: String) throws {
        guard let index = ledger.created.firstIndex(where: { $0.id == id }) else { throw GWSFailure.forbiddenOperation }
        ledger.created[index].deleted = true
        try saveLedger()
    }

    private func saveLedger() throws {
        let path = directory.appendingPathComponent("ledger.json")
        try JSONEncoder().encode(ledger).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
