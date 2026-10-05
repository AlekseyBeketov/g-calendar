import Foundation
import Darwin

struct ProcessInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
    let operation: GWSOperation
    let timeout: TimeInterval
    let outputLimit: Int
}

struct ProcessResult: Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

protocol GWSProcessRunning: Sendable {
    func run(_ invocation: ProcessInvocation) throws -> ProcessResult
}

enum GWSFailure: Error, Equatable, LocalizedError {
    case executableUnavailable
    case invalidExecutablePath
    case timedOut(String)
    case outputTooLarge(String)
    case processFailed(String, Int32, String)
    case invalidResponse(String)
    case paginationLoop(String)
    case forbiddenOperation
    case invalidInput(String)
    case cacheFailure
    case permissionDenied
    case resourceNotFound
    case mutationNotVerified

    var errorDescription: String? {
        switch self {
        case .executableUnavailable: return "gws не найден. Укажите абсолютный путь к исполняемому файлу в настройках."
        case .invalidExecutablePath: return "Путь к gws должен быть абсолютным и указывать на исполняемый файл."
        case .timedOut(let operation): return "Операция \(operation) превысила лимит времени. Кэшированные данные сохранены."
        case .outputTooLarge(let operation): return "Ответ \(operation) превышает безопасный лимит."
        case .processFailed(let operation, let code, let category): return "gws: \(operation), exit \(code) (\(category)). Кэшированные данные сохранены."
        case .invalidResponse(let safeField): return "gws вернул некорректный ответ (\(safeField)). Кэшированные данные сохранены."
        case .paginationLoop(let operation): return "gws вернул повторяющийся page token в операции \(operation)."
        case .forbiddenOperation: return "Операция запрещена политикой приложения."
        case .invalidInput(let safeField): return "Некорректное значение поля \(safeField)."
        case .cacheFailure: return "Не удалось атомарно сохранить локальный кэш."
        case .permissionDenied: return "macOS не разрешила локальные уведомления."
        case .resourceNotFound: return "Запрошенный ресурс не найден."
        case .mutationNotVerified: return "Google принял запрос, но точное чтение не подтвердило ожидаемое состояние."
        }
    }
}

enum GWSOperation: String, Equatable, Codable {
    case calendarList = "calendar.calendarList.list"
    case calendarGet = "calendar.calendarList.get"
    case eventsList = "calendar.events.list"
    case eventGet = "calendar.events.get"
    case taskListsList = "tasks.tasklists.list"
    case taskListGet = "tasks.tasklists.get"
    case tasksList = "tasks.tasks.list"
    case taskGet = "tasks.tasks.get"
    case eventInsert = "calendar.events.insert"
    case eventPatch = "calendar.events.patch"
    case eventDelete = "calendar.events.delete"
    case taskListInsert = "tasks.tasklists.insert"
    case taskListPatch = "tasks.tasklists.patch"
    case taskListDelete = "tasks.tasklists.delete"
    case taskInsert = "tasks.tasks.insert"
    case taskPatch = "tasks.tasks.patch"
    case taskDelete = "tasks.tasks.delete"
}

struct GWSCommandFactory {
    let executableURL: URL
    var timeout: TimeInterval = 20
    var outputLimit: Int = 2 * 1_024 * 1_024

    func readCalendars(pageToken: String?) throws -> ProcessInvocation {
        try read(.calendarList, command: ["calendar", "calendarList", "list"], params: pageParams(pageToken, maxResults: 250))
    }

    func readCalendar(id: String) throws -> ProcessInvocation {
        guard !id.isEmpty else { throw GWSFailure.invalidInput("calendar_id") }
        return try read(.calendarGet, command: ["calendar", "calendarList", "get"], params: ["calendarId": id])
    }

    func readTaskLists(pageToken: String?) throws -> ProcessInvocation {
        try read(.taskListsList, command: ["tasks", "tasklists", "list"], params: pageParams(pageToken, maxResults: 100))
    }

    func readTaskList(id: String) throws -> ProcessInvocation {
        guard !id.isEmpty else { throw GWSFailure.invalidInput("task_list_id") }
        return try read(.taskListGet, command: ["tasks", "tasklists", "get"], params: ["tasklist": id])
    }

    func readEvent(calendarID: String, eventID: String) throws -> ProcessInvocation {
        guard !calendarID.isEmpty, !eventID.isEmpty else { throw GWSFailure.invalidInput("event_identity") }
        return try read(.eventGet, command: ["calendar", "events", "get"], params: ["calendarId": calendarID, "eventId": eventID])
    }

    func readTask(taskListID: String, taskID: String) throws -> ProcessInvocation {
        guard !taskListID.isEmpty, !taskID.isEmpty else { throw GWSFailure.invalidInput("task_identity") }
        return try read(.taskGet, command: ["tasks", "tasks", "get"], params: ["tasklist": taskListID, "task": taskID])
    }

    func readEvents(calendarID: String, range: DateRange, pageToken: String?) throws -> ProcessInvocation {
        guard !calendarID.isEmpty else { throw GWSFailure.invalidInput("calendar_id") }
        var params: [String: Any] = ["calendarId": calendarID, "timeMin": range.startISO8601, "timeMax": range.endISO8601,
                                     "timeZone": range.timeZone.identifier, "singleEvents": true, "orderBy": "startTime", "maxResults": 250]
        if let pageToken { params["pageToken"] = pageToken }
        return try read(.eventsList, command: ["calendar", "events", "list"], params: params)
    }

    func readTasks(taskListID: String, pageToken: String?) throws -> ProcessInvocation {
        guard !taskListID.isEmpty else { throw GWSFailure.invalidInput("task_list_id") }
        var params: [String: Any] = ["tasklist": taskListID, "showCompleted": true, "showHidden": true, "showDeleted": false, "maxResults": 100]
        if let pageToken { params["pageToken"] = pageToken }
        return try read(.tasksList, command: ["tasks", "tasks", "list"], params: params)
    }

    func eventInsert(calendar: CalendarInfo, body: [String: Any], authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .userSave, calendar.isWritable else { throw GWSFailure.forbiddenOperation }
        try ensureNoAttendees(body)
        return try mutation(.eventInsert, command: ["calendar", "events", "insert"], params: ["calendarId": calendar.id, "sendUpdates": "none"], body: eventBodyAtSecondPrecision(body))
    }

    func eventPatch(event: CalendarEvent, calendar: CalendarInfo, body: [String: Any], authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .userSave, calendar.isWritable, !event.recurring, event.calendarID == calendar.id else { throw GWSFailure.forbiddenOperation }
        try ensureNoAttendees(body)
        return try mutation(.eventPatch, command: ["calendar", "events", "patch"], params: ["calendarId": calendar.id, "eventId": event.id], body: eventBodyAtSecondPrecision(body))
    }

    // Google Calendar stores event instants at second precision. Canonicalize the
    // submitted draft before journaling; exact read-back remains strict.
    private func eventBodyAtSecondPrecision(_ body: [String: Any]) throws -> [String: Any] {
        var result = body
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for key in ["start", "end"] {
            guard var value = body[key] as? [String: Any], let timestamp = value["dateTime"] as? String else { continue }
            guard let instant = ISO8601.parse(timestamp) else { throw GWSFailure.invalidInput("event_time") }
            value["dateTime"] = formatter.string(from: instant)
            result[key] = value
        }
        return result
    }

    func eventDelete(event: CalendarEvent, calendar: CalendarInfo, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .confirmedDelete, calendar.isWritable, !event.recurring, event.calendarID == calendar.id else { throw GWSFailure.forbiddenOperation }
        return try mutation(.eventDelete, command: ["calendar", "events", "delete"], params: ["calendarId": calendar.id, "eventId": event.id])
    }

    func taskListInsert(title: String, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .userSave, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GWSFailure.forbiddenOperation }
        return try mutation(.taskListInsert, command: ["tasks", "tasklists", "insert"], params: [:], body: ["title": title])
    }

    func taskListPatch(id: String, title: String, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .userSave, !id.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GWSFailure.forbiddenOperation }
        return try mutation(.taskListPatch, command: ["tasks", "tasklists", "patch"], params: ["tasklist": id], body: ["title": title])
    }

    func taskListDelete(id: String, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .confirmedDelete, !id.isEmpty else { throw GWSFailure.forbiddenOperation }
        return try mutation(.taskListDelete, command: ["tasks", "tasklists", "delete"], params: ["tasklist": id])
    }

    func taskInsert(taskListID: String, title: String, notes: String?, due: DateOnly?, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .userSave, !taskListID.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GWSFailure.forbiddenOperation }
        return try mutation(.taskInsert, command: ["tasks", "tasks", "insert"], params: ["tasklist": taskListID], body: taskBody(title: title, notes: notes, due: due, completed: false))
    }

    func taskPatch(task: GoogleTask, title: String, notes: String?, due: DateOnly?, completed: Bool? = nil, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard !task.taskListID.isEmpty, !task.id.isEmpty else { throw GWSFailure.forbiddenOperation }
        switch authorization {
        case .userSave: break
        case .userCompletionToggle: guard completed != nil else { throw GWSFailure.forbiddenOperation }
        case .confirmedDelete, .cancelled: throw GWSFailure.forbiddenOperation
        }
        var body: [String: Any]
        switch authorization {
        case .userSave:
            body = taskBody(title: title, notes: notes, due: due, completed: completed ?? task.completed)
            if due == nil { body["due"] = NSNull() }
        case .userCompletionToggle:
            body = ["status": completed == true ? "completed" : "needsAction"]
        case .confirmedDelete, .cancelled:
            throw GWSFailure.forbiddenOperation
        }
        return try mutation(.taskPatch, command: ["tasks", "tasks", "patch"], params: ["tasklist": task.taskListID, "task": task.id], body: body)
    }

    func taskDelete(task: GoogleTask, authorization: MutationAuthorization) throws -> ProcessInvocation {
        guard authorization == .confirmedDelete, !task.id.isEmpty, !task.taskListID.isEmpty else { throw GWSFailure.forbiddenOperation }
        return try mutation(.taskDelete, command: ["tasks", "tasks", "delete"], params: ["tasklist": task.taskListID, "task": task.id])
    }

    private func read(_ operation: GWSOperation, command: [String], params: [String: Any]) throws -> ProcessInvocation {
        try invocation(operation, command: command, params: params, body: nil)
    }

    private func mutation(_ operation: GWSOperation, command: [String], params: [String: Any], body: [String: Any]? = nil) throws -> ProcessInvocation {
        try invocation(operation, command: command, params: params, body: body)
    }

    private func invocation(_ operation: GWSOperation, command: [String], params: [String: Any], body: [String: Any]?) throws -> ProcessInvocation {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw GWSFailure.invalidExecutablePath }
        var args = command
        if !params.isEmpty { args += ["--params", try jsonArgument(params)] }
        if let body { args += ["--json", try jsonArgument(body)] }
        return ProcessInvocation(executableURL: executableURL, arguments: args, operation: operation, timeout: timeout, outputLimit: outputLimit)
    }

    private func jsonArgument(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]),
              let string = String(data: data, encoding: .utf8) else { throw GWSFailure.invalidInput("json") }
        return string
    }

    private func pageParams(_ pageToken: String?, maxResults: Int) -> [String: Any] {
        var params: [String: Any] = ["maxResults": maxResults]
        if let pageToken { params["pageToken"] = pageToken }
        return params
    }

    private func ensureNoAttendees(_ body: [String: Any]) throws {
        guard body["attendees"] == nil, body["attendeeEmails"] == nil else { throw GWSFailure.forbiddenOperation }
    }

    private func taskBody(title: String, notes: String?, due: DateOnly?, completed: Bool) -> [String: Any] {
        var body: [String: Any] = ["title": title, "status": completed ? "completed" : "needsAction"]
        if let notes { body["notes"] = notes }
        if let due { body["due"] = due.description + "T00:00:00.000Z" }
        return body
    }
}

enum MutationAuthorization: Equatable {
    case userSave
    case userCompletionToggle
    case confirmedDelete
    case cancelled
}

final class FoundationProcessRunner: GWSProcessRunning, @unchecked Sendable {
    private let pollInterval: TimeInterval = 0.01
    private let terminationGrace: TimeInterval = 0.25
    private let environment: [String: String]
    private let homeDirectory: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
        guard invocation.executableURL.isFileURL, invocation.executableURL.path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: invocation.executableURL.path) else { throw GWSFailure.invalidExecutablePath }
        let process = Process()
        let stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = GWSProcessEnvironment.withStandardExecutablePaths(in: environment, homeDirectory: homeDirectory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let output = BoundedCapture(limit: invocation.outputLimit)
        let error = BoundedCapture(limit: min(invocation.outputLimit, 256 * 1024))
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async { output.drain(stdoutPipe.fileHandleForReading); group.leave() }
        group.enter()
        DispatchQueue.global(qos: .utility).async { error.drain(stderrPipe.fileHandleForReading); group.leave() }
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForWriting.closeFile(); stderrPipe.fileHandleForWriting.closeFile()
            _ = group.wait(timeout: .now() + 1)
            throw GWSFailure.executableUnavailable
        }
        let deadline = Date().addingTimeInterval(max(0.05, invocation.timeout))
        var timedOut = false
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: pollInterval) }
        if process.isRunning {
            timedOut = true
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(terminationGrace)
            while process.isRunning && Date() < graceDeadline { Thread.sleep(forTimeInterval: pollInterval) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 2)
        if timedOut { throw GWSFailure.timedOut(invocation.operation.rawValue) }
        guard !output.exceededLimit, !error.exceededLimit else { throw GWSFailure.outputTooLarge(invocation.operation.rawValue) }
        return ProcessResult(exitCode: process.terminationStatus, stdout: output.data, stderr: error.data)
    }
}

enum GWSProcessEnvironment {
    static func withStandardExecutablePaths(in environment: [String: String], homeDirectory: URL) -> [String: String] {
        var updated = environment
        let currentPaths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let standardPaths = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        updated["PATH"] = (currentPaths + standardPaths).reduce(into: [String]()) { paths, path in
            if !path.isEmpty && !paths.contains(path) { paths.append(path) }
        }.joined(separator: ":")
        return updated
    }
}

private final class BoundedCapture {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    private(set) var exceededLimit = false
    init(limit: Int) { self.limit = max(1, limit) }
    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 16 * 1024)
            if chunk.isEmpty { break }
            lock.lock()
            if buffer.count + chunk.count <= limit { buffer.append(chunk) }
            else {
                exceededLimit = true
                let remaining = max(0, limit - buffer.count)
                if remaining > 0 { buffer.append(chunk.prefix(remaining)) }
            }
            lock.unlock()
        }
        try? handle.close()
    }
}

struct GWSReadClient: ExactCalendarEventReading {
    let factory: GWSCommandFactory
    let runner: GWSProcessRunning

    func calendars() throws -> [CalendarInfo] {
        try collect(operation: .calendarList, makeInvocation: factory.readCalendars) { items in
            try items.map { item in
                guard let id = item["id"] as? String,
                      let title = (item["summaryOverride"] as? String) ?? (item["summary"] as? String),
                      let role = item["accessRole"] as? String else { throw GWSFailure.invalidResponse("calendar_shape") }
                return CalendarInfo(id: id, title: title, accessRole: role, timeZoneID: item["timeZone"] as? String, colorHex: item["backgroundColor"] as? String)
            }
        }
    }

    func readCalendar(id: String) throws -> CalendarInfo {
        let object = try exactObject(factory.readCalendar(id: id))
        guard let returnedID = object["id"] as? String, returnedID == id,
              let title = (object["summaryOverride"] as? String) ?? (object["summary"] as? String),
              let role = object["accessRole"] as? String else { throw GWSFailure.invalidResponse("calendar_identity") }
        return CalendarInfo(id: returnedID,
                            title: title,
                            accessRole: role,
                            timeZoneID: object["timeZone"] as? String,
                            colorHex: object["backgroundColor"] as? String)
    }

    func events(calendarID: String, range: DateRange) throws -> [CalendarEvent] {
        try collect(operation: .eventsList, makeInvocation: { token in try factory.readEvents(calendarID: calendarID, range: range, pageToken: token) }) { items in
            try items.map { try CalendarEvent.decode($0, calendarID: calendarID) }
        }
    }

    func readEvent(calendarID: String, eventID: String) throws -> CalendarEvent {
        let object = try exactObject(factory.readEvent(calendarID: calendarID, eventID: eventID))
        let event = try CalendarEvent.decode(object, calendarID: calendarID)
        guard event.id == eventID else { throw GWSFailure.invalidResponse("event_identity") }
        return event
    }

    func event(identity: CalendarEventIdentity) throws -> CalendarEvent? {
        do {
            let object = try exactObject(factory.readEvent(calendarID: identity.calendarID, eventID: identity.eventID))
            guard object["id"] as? String == identity.eventID else { throw GWSFailure.invalidResponse("event_identity") }
            // Deleted events are only guaranteed to retain their ID, not times/title.
            if object["status"] as? String == "cancelled" { return nil }
            return try CalendarEvent.decode(object, calendarID: identity.calendarID)
        }
        catch GWSFailure.resourceNotFound { return nil }
    }

    func taskLists() throws -> [TaskList] {
        try collect(operation: .taskListsList, makeInvocation: factory.readTaskLists) { items in try items.map(TaskList.decode) }
    }

    func readTaskList(id: String) throws -> TaskList {
        let object = try exactObject(factory.readTaskList(id: id))
        let taskList = try TaskList.decode(object)
        guard taskList.id == id else { throw GWSFailure.invalidResponse("task_list_identity") }
        return taskList
    }

    func taskList(id: String) throws -> TaskList? {
        do { return try readTaskList(id: id) }
        catch GWSFailure.resourceNotFound { return nil }
    }

    func tasks(taskListID: String) throws -> [GoogleTask] {
        try collect(operation: .tasksList, makeInvocation: { token in try factory.readTasks(taskListID: taskListID, pageToken: token) }) { items in
            try items.map { try GoogleTask.decode($0, taskListID: taskListID) }
        }
    }

    func readTask(taskListID: String, taskID: String) throws -> GoogleTask {
        let object = try exactObject(factory.readTask(taskListID: taskListID, taskID: taskID))
        let task = try GoogleTask.decode(object, taskListID: taskListID)
        guard task.id == taskID else { throw GWSFailure.invalidResponse("task_identity") }
        return task
    }

    func task(taskListID: String, taskID: String) throws -> GoogleTask? {
        do {
            let object = try exactObject(factory.readTask(taskListID: taskListID, taskID: taskID))
            guard object["id"] as? String == taskID else { throw GWSFailure.invalidResponse("task_identity") }
            // An exact GET can return a deletion tombstone instead of 404.
            if object["deleted"] as? Bool == true { return nil }
            return try GoogleTask.decode(object, taskListID: taskListID)
        }
        catch GWSFailure.resourceNotFound { return nil }
    }

    private func exactObject(_ invocation: ProcessInvocation) throws -> [String: Any] {
        let result = try runner.run(invocation)
        guard result.exitCode == 0 else {
            let category = Self.safeCategory(result.stderr)
            if Self.isMissingResource(result) { throw GWSFailure.resourceNotFound }
            throw GWSFailure.processFailed(invocation.operation.rawValue, result.exitCode, category)
        }
        guard let json = try? JSONSerialization.jsonObject(with: result.stdout), let object = json as? [String: Any] else {
            throw GWSFailure.invalidResponse("json_" + invocation.operation.rawValue)
        }
        return object
    }

    private static func isMissingResource(_ result: ProcessResult) -> Bool {
        for data in [result.stdout, result.stderr] where !data.isEmpty {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any] {
                if let code = error["code"] as? Int, code == 404 || code == 410 { return true }
                continue // Never infer a 404 from an unrelated identifier/message.
            }
            let message = String(data: data.prefix(16_384), encoding: .utf8) ?? ""
            let pattern = #"(?i)\b(?:404\s+not\s+found|410\s+gone|http\s+(?:404|410))\b"#
            if message.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

    private func collect<T>(operation: GWSOperation, makeInvocation: (String?) throws -> ProcessInvocation, decode: ([[String: Any]]) throws -> [T]) throws -> [T] {
        var result: [T] = [], nextToken: String?
        var seenTokens = Set<String>()
        repeat {
            let invocation = try makeInvocation(nextToken)
            let processResult = try runner.run(invocation)
            guard processResult.exitCode == 0 else { throw GWSFailure.processFailed(operation.rawValue, processResult.exitCode, Self.safeCategory(processResult.stderr)) }
            guard let json = try? JSONSerialization.jsonObject(with: processResult.stdout), let object = json as? [String: Any] else {
                throw GWSFailure.invalidResponse("json_" + operation.rawValue)
            }
            guard let rawItems = object["items"] as? [[String: Any]] else { throw GWSFailure.invalidResponse("items_" + operation.rawValue) }
            result.append(contentsOf: try decode(rawItems))
            let token = object["nextPageToken"] as? String
            if let token, !token.isEmpty {
                guard seenTokens.insert(token).inserted else { throw GWSFailure.paginationLoop(operation.rawValue) }
                nextToken = token
            } else { nextToken = nil }
        } while nextToken != nil
        return result
    }

    private static func safeCategory(_ stderr: Data) -> String {
        let text = String(data: stderr.prefix(16_384), encoding: .utf8)?.lowercased() ?? ""
        if text.contains("404") || text.contains("410") || text.contains("not found") || text.contains("not_found") { return "not_found" }
        if text.contains("429") || text.contains("quota") || text.contains("rate limit") { return "quota" }
        if text.contains("401") || text.contains("unauth") || text.contains("permission denied") { return "auth_or_permission" }
        if text.contains("timeout") || text.contains("timed out") || text.contains("network") { return "network" }
        return "command_failure"
    }
}

struct GWSCompletedFullSync {
    let snapshot: WorkspaceSnapshot

    fileprivate init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
    }
}

struct GWSCompletedTasksSync {
    let snapshot: WorkspaceSnapshot

    fileprivate init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
    }
}

struct GWSWorkspaceService {
    let reader: GWSReadClient
    let cache: SnapshotStoring

    func refresh(range: DateRange, now: Date = Date()) throws -> WorkspaceSnapshot {
        try refreshCompletedFullSync(range: range, now: now).snapshot
    }

    func refreshCompletedFullSync(range: DateRange, now: Date = Date()) throws -> GWSCompletedFullSync {
        let calendars = try reader.calendars()
        let events = try calendars.flatMap { try reader.events(calendarID: $0.id, range: range) }
        let lists = try reader.taskLists()
        let tasks = try lists.flatMap { try reader.tasks(taskListID: $0.id) }
        var snapshot = WorkspaceSnapshot(calendars: calendars, events: events, taskLists: lists, tasks: tasks, fetchedAt: now)
        snapshot.calendarCoverage = CalendarRangeCoverage(range: range)
        snapshot.calendarFetchedAt = now
        snapshot.tasksFetchedAt = now
        try cache.commit(snapshot)
        return GWSCompletedFullSync(snapshot: snapshot)
    }

    func refreshCalendarRange(range: DateRange, now: Date = Date()) throws -> WorkspaceSnapshot {
        let calendars = try reader.calendars()
        let events = try calendars.flatMap { try reader.events(calendarID: $0.id, range: range) }
        var snapshot = cache.load() ?? .empty
        let previousSnapshotDate = snapshot.fetchedAt
        snapshot.calendars = calendars
        snapshot.events = events
        snapshot.fetchedAt = now
        snapshot.calendarCoverage = CalendarRangeCoverage(range: range)
        snapshot.calendarFetchedAt = now
        if snapshot.tasksFetchedAt == nil, previousSnapshotDate != .distantPast {
            snapshot.tasksFetchedAt = previousSnapshotDate
        }
        try cache.commit(snapshot)
        return snapshot
    }

    func refreshTasks(now: Date = Date()) throws -> GWSCompletedTasksSync {
        let lists = try reader.taskLists()
        let tasks = try lists.flatMap { try reader.tasks(taskListID: $0.id) }
        var snapshot = cache.load() ?? .empty
        snapshot.taskLists = lists
        snapshot.tasks = tasks
        snapshot.fetchedAt = now
        snapshot.tasksFetchedAt = now
        try cache.commit(snapshot)
        return GWSCompletedTasksSync(snapshot: snapshot)
    }
}
