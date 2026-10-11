import Foundation
import CoreFoundation

protocol GWSReadProcessRunning: GWSProcessRunning {
    func run(_ invocation: ProcessInvocation, cancellation: GWSReadCancellation?) throws -> ProcessResult
}

struct GoogleHTTPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

protocol GoogleHTTPClient: Sendable {
    func send(_ request: URLRequest, outputLimit: Int, cancellation: GWSReadCancellation?) throws -> GoogleHTTPResponse
}

protocol GoogleAccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) throws -> String
    func accessToken(forceRefresh: Bool, deadline: Date) throws -> String
}

extension GoogleAccessTokenProviding {
    func accessToken(forceRefresh: Bool, deadline: Date) throws -> String { try accessToken(forceRefresh: forceRefresh) }
}

enum GoogleRESTFailure: Error, LocalizedError {
    case setupRequired, network, redirected, authentication, invalidConfiguration, cancelled
    var errorDescription: String? {
        switch self {
        case .setupRequired: return "Google REST: импортируйте Desktop OAuth JSON и выполните вход."
        case .network: return "Google REST: соединение прервано; результат записи требует проверки."
        case .redirected: return "Google REST: перенаправление на другой адрес запрещено."
        case .authentication: return "Google REST: требуется повторный вход."
        case .invalidConfiguration: return "Google REST: некорректная конфигурация OAuth."
        case .cancelled: return "Вход Google отменён."
        }
    }
}

struct GoogleRESTRequestBuilder {
    func build(_ invocation: ProcessInvocation) throws -> URLRequest {
        guard invocation.executableURL == GWSCommandFactory.restMarker, invocation.timeout > 0,
              invocation.outputLimit > 0 else { throw GWSFailure.forbiddenOperation }
        let expected = invocation.operation.rawValue.split(separator: ".").map(String.init)
        guard Array(invocation.arguments.prefix(3)) == expected else { throw GWSFailure.forbiddenOperation }
        var params: [String: Any] = [:], body: [String: Any]? = nil, seen = Set<String>()
        var index = 3
        while index < invocation.arguments.count {
            let flag = invocation.arguments[index]
            guard ["--params", "--json"].contains(flag), seen.insert(flag).inserted,
                  index + 1 < invocation.arguments.count,
                  let data = invocation.arguments[index + 1].data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GWSFailure.forbiddenOperation }
            if flag == "--params" { params = object } else { body = object }
            index += 2
        }
        var allowed: Set<String> = [], pathKeys = Set<String>(), method = "GET", path: [String] = []
        let op = invocation.operation
        func id(_ key: String) throws -> String {
            guard let value = params[key] as? String, !value.isEmpty, value.utf8.count <= 4096 else { throw GWSFailure.invalidInput("resource_identity") }
            pathKeys.insert(key); return value
        }
        switch op {
        case .calendarList, .calendarGet:
            path = ["users", "me", "calendarList"]
            allowed = op == .calendarList ? ["pageToken", "maxResults"] : ["calendarId"]
            if op == .calendarGet { path += [try id("calendarId")] }
        case .eventsList, .eventGet, .eventInsert, .eventPatch, .eventDelete:
            path = ["calendars", try id("calendarId"), "events"]
            allowed = ["calendarId"]
            if op == .eventsList { allowed.formUnion(["timeMin", "timeMax", "timeZone", "singleEvents", "orderBy", "maxResults", "pageToken"]) }
            if [.eventGet, .eventPatch, .eventDelete].contains(op) { path += [try id("eventId")]; allowed.insert("eventId") }
            if op == .eventInsert { allowed.insert("sendUpdates"); guard params["sendUpdates"] as? String == "none" else { throw GWSFailure.forbiddenOperation } }
        case .taskListsList, .taskListGet, .taskListInsert, .taskListPatch, .taskListDelete:
            path = ["users", "@me", "lists"]
            allowed = op == .taskListsList ? ["pageToken", "maxResults"] : []
            if [.taskListGet, .taskListPatch, .taskListDelete].contains(op) { path += [try id("tasklist")]; allowed.insert("tasklist") }
        case .tasksList, .taskGet, .taskInsert, .taskPatch, .taskMove, .taskDelete:
            path = ["lists", try id("tasklist"), "tasks"]; allowed = ["tasklist"]
            if op == .tasksList { allowed.formUnion(["showCompleted", "showHidden", "showDeleted", "maxResults", "pageToken"]) }
            if [.taskGet, .taskPatch, .taskMove, .taskDelete].contains(op) { path += [try id("task")]; allowed.insert("task") }
            if op == .taskMove { path += ["move"]; allowed.insert("destinationTasklist"); guard let destination = params["destinationTasklist"] as? String, !destination.isEmpty else { throw GWSFailure.invalidInput("destination") } }
        }
        guard Set(params.keys).isSubset(of: allowed) else { throw GWSFailure.forbiddenOperation }
        if [.eventInsert, .taskListInsert, .taskInsert, .taskMove].contains(op) { method = "POST" }
        if [.eventPatch, .taskListPatch, .taskPatch].contains(op) { method = "PATCH" }
        if [.eventDelete, .taskListDelete, .taskDelete].contains(op) { method = "DELETE" }
        let expectsBody = method == "PATCH" || (method == "POST" && op != .taskMove)
        guard expectsBody == (body != nil) else { throw GWSFailure.forbiddenOperation }
        if let body {
            let bodyKeys: Set<String>
            switch op {
            case .eventInsert, .eventPatch: bodyKeys = ["summary", "description", "location", "start", "end"]
            case .taskListInsert, .taskListPatch: bodyKeys = ["title"]
            case .taskInsert, .taskPatch: bodyKeys = ["title", "notes", "due", "status"]
            default: throw GWSFailure.forbiddenOperation
            }
            guard Set(body.keys).isSubset(of: bodyKeys), !body.isEmpty else { throw GWSFailure.forbiddenOperation }
            for key in ["start", "end"] where body[key] != nil {
                guard let value = body[key] as? [String: Any], Set(value.keys).isSubset(of: ["date", "dateTime", "timeZone"]),
                      value.values.allSatisfy({ $0 is String }) else { throw GWSFailure.forbiddenOperation }
            }
            for (key, value) in body where key != "start" && key != "end" {
                guard value is String || (key == "due" && value is NSNull) else { throw GWSFailure.forbiddenOperation }
            }
        }
        for key in ["singleEvents", "showCompleted", "showHidden", "showDeleted"] where params[key] != nil {
            guard let value = params[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw GWSFailure.forbiddenOperation }
        }
        if let value = params["maxResults"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.rounded() == number.doubleValue,
                  number.intValue > 0, number.intValue <= 250 else { throw GWSFailure.forbiddenOperation }
        }
        for key in ["pageToken", "timeMin", "timeMax", "timeZone", "orderBy", "destinationTasklist", "sendUpdates"] where params[key] != nil {
            guard let value = params[key] as? String, !value.isEmpty else { throw GWSFailure.forbiddenOperation }
        }
        if let status = body?["status"] as? String, !["completed", "needsAction"].contains(status) { throw GWSFailure.forbiddenOperation }
        let isCalendar = op.rawValue.hasPrefix("calendar.")
        var components = URLComponents()
        components.scheme = "https"; components.host = isCalendar ? "www.googleapis.com" : "tasks.googleapis.com"
        let segmentCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedPath = (isCalendar ? "/calendar/v3/" : "/tasks/v1/") + path.map { $0.addingPercentEncoding(withAllowedCharacters: segmentCharacters)! }.joined(separator: "/")
        components.queryItems = try params.keys.sorted().filter { !pathKeys.contains($0) }.map { key in
            let value = params[key]!
            let string: String
            if let text = value as? String { string = text }
            else if let number = value as? NSNumber {
                string = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
            } else { throw GWSFailure.forbiddenOperation }
            return URLQueryItem(name: key, value: string)
        }
        guard let url = components.url else { throw GWSFailure.forbiddenOperation }
        var request = URLRequest(url: url, timeoutInterval: invocation.timeout)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
}

// The compatibility API is synchronous only on background workers. The session's
// independent delegate queue continues streaming while the worker waits.
final class GoogleURLSessionHTTPClient: NSObject, GoogleHTTPClient, URLSessionDataDelegate, @unchecked Sendable {
    private final class Delegate: NSObject, URLSessionDataDelegate {
        weak var owner: GoogleURLSessionHTTPClient?
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let owner else { completionHandler(.cancel); return }
            owner.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { owner?.urlSession(session, dataTask: dataTask, didReceive: data) }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { owner?.urlSession(session, task: task, didCompleteWithError: error) }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let owner else { completionHandler(nil); return }
            owner.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
        }
    }
    private let delegate = Delegate()
    private final class Flight {
        let limit: Int
        let semaphore = DispatchSemaphore(value: 0)
        var response: HTTPURLResponse?, data = Data(), error: Error?
        init(limit: Int) { self.limit = limit }
    }
    private let lock = NSLock()
    private var flights: [Int: Flight] = [:]
    private var session: URLSession!
    override convenience init() { self.init(configuration: .ephemeral) }
    init(configuration: URLSessionConfiguration) {
        super.init()
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        delegate.owner = self
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
    }
    deinit { session.invalidateAndCancel() }
    func invalidate() { session.invalidateAndCancel() }
    func send(_ request: URLRequest, outputLimit: Int, cancellation: GWSReadCancellation?) throws -> GoogleHTTPResponse {
        guard !Thread.isMainThread else { throw GWSFailure.forbiddenOperation }
        try cancellation?.check()
        let flight = Flight(limit: outputLimit), task = session.dataTask(with: request)
        lock.lock(); flights[task.taskIdentifier] = flight; lock.unlock()
        let registration = cancellation?.register { task.cancel() }
        defer { if let registration { cancellation?.unregister(registration) }; lock.lock(); flights.removeValue(forKey: task.taskIdentifier); lock.unlock() }
        task.resume()
        if flight.semaphore.wait(timeout: .now() + request.timeoutInterval) == .timedOut { task.cancel(); throw GWSFailure.timedOut("Google HTTP") }
        try cancellation?.check()
        lock.lock(); let response = flight.response, data = flight.data, error = flight.error; lock.unlock()
        if let error { throw error }
        guard let response else { throw GoogleRESTFailure.network }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in result[String(describing: pair.key).lowercased()] = String(describing: pair.value) }
        return GoogleHTTPResponse(statusCode: response.statusCode, headers: headers, body: data)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); if let flight = flights[dataTask.taskIdentifier] { flight.response = response as? HTTPURLResponse }; lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let flight = flights[dataTask.taskIdentifier] else { lock.unlock(); return }
        if data.count > flight.limit - flight.data.count { flight.error = GWSFailure.outputTooLarge("Google HTTP"); lock.unlock(); dataTask.cancel(); return }
        flight.data.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let flight = flights[task.taskIdentifier]
        if let flight, flight.error == nil, error != nil { flight.error = GoogleRESTFailure.network }
        lock.unlock(); flight?.semaphore.signal()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // No endpoint in this application needs a redirect. Rejecting all also
        // prevents bearer headers reaching a different host or downgraded URL.
        lock.lock(); flights[task.taskIdentifier]?.error = GoogleRESTFailure.redirected; lock.unlock()
        completionHandler(nil)
    }
}

struct GoogleRESTRunner: GWSReadProcessRunning {
    let http: GoogleHTTPClient
    let tokens: GoogleAccessTokenProviding
    var sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var jitter: @Sendable () -> Double = { Double.random(in: 0...0.25) }
    func run(_ invocation: ProcessInvocation) throws -> ProcessResult { try run(invocation, cancellation: nil) }
    func run(_ invocation: ProcessInvocation, cancellation: GWSReadCancellation?) throws -> ProcessResult {
        let original = try GoogleRESTRequestBuilder().build(invocation)
        let read = original.httpMethod == "GET"
        let deadline = Date().addingTimeInterval(invocation.timeout)
        var refreshed = false, forceNextToken = false
        for attempt in 0..<(read ? 3 : 1) {
            try cancellation?.check()
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw GWSFailure.timedOut(invocation.operation.rawValue) }
            var request = original
            let token = try tokens.accessToken(forceRefresh: forceNextToken, deadline: deadline)
            forceNextToken = false
            request.timeoutInterval = deadline.timeIntervalSinceNow
            guard request.timeoutInterval > 0 else { throw GWSFailure.timedOut(invocation.operation.rawValue) }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let response = try http.send(request, outputLimit: invocation.outputLimit, cancellation: read ? cancellation : nil)
            guard response.body.count <= invocation.outputLimit else { throw GWSFailure.outputTooLarge(invocation.operation.rawValue) }
            if (200..<300).contains(response.statusCode) { return ProcessResult(exitCode: 0, stdout: response.body, stderr: Data()) }
            if read, response.statusCode == 401, !refreshed, attempt < 2 { refreshed = true; forceNextToken = true; continue }
            let quota = response.statusCode == 403 && Self.isQuota(response.body)
            if read, attempt < 2, response.statusCode == 429 || quota || (500..<600).contains(response.statusCode) {
                let retry = Self.retryAfter(response.headers["retry-after"])
                let delay = min(10, retry ?? (pow(2, Double(attempt)) * 0.25 + jitter()))
                guard delay < deadline.timeIntervalSinceNow else { throw GWSFailure.timedOut(invocation.operation.rawValue) }
                sleep(delay); continue
            }
            let sanitized = try JSONSerialization.data(withJSONObject: ["error": ["code": response.statusCode]])
            return ProcessResult(exitCode: 1, stdout: Data(), stderr: sanitized)
        }
        throw GoogleRESTFailure.network
    }
    private static func isQuota(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = object["error"] as? [String: Any], let errors = error["errors"] as? [[String: Any]] else { return false }
        return errors.contains { ["rateLimitExceeded", "userRateLimitExceeded", "quotaExceeded"].contains($0["reason"] as? String ?? "") }
    }
    private static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds >= 0 { return seconds }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}
