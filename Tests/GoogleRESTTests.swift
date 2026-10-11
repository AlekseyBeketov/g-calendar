import Foundation

final class FakeGoogleHTTPClient: GoogleHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    var responses: [GoogleHTTPResponse]
    var requests: [URLRequest] = []
    var latency: TimeInterval = 0
    init(_ responses: [GoogleHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest, outputLimit: Int, cancellation: GWSReadCancellation?) throws -> GoogleHTTPResponse {
        try cancellation?.check()
        if latency > 0 { Thread.sleep(forTimeInterval: latency) }
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !responses.isEmpty else { throw GoogleRESTFailure.network }
        return responses.removeFirst()
    }
}

final class FakeGoogleTokens: GoogleAccessTokenProviding, @unchecked Sendable {
    var refreshes = 0
    func accessToken(forceRefresh: Bool) throws -> String { if forceRefresh { refreshes += 1 }; return "synthetic-token" }
}

extension InvariantTests {
    static func testGoogleRESTCore() throws {
        let factory = GWSCommandFactory.googleREST()
        let builder = GoogleRESTRequestBuilder()
        let range = try DateRange(start: Date(timeIntervalSince1970: 1), endExclusive: Date(timeIntervalSince1970: 2))
        let calendar = CalendarInfo(id: "c/%?", title: "Synthetic", accessRole: "owner", timeZoneID: "UTC", colorHex: nil)
        let task = GoogleTask(id: "t/%?", taskListID: "l/%?", title: "Synthetic", notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let event = CalendarEvent(id: "e/%?", calendarID: calendar.id, title: "Synthetic", start: EventTime(rawValue: "1970-01-01T00:00:01Z", instant: Date(timeIntervalSince1970: 1), dateOnly: nil, timeZoneID: "UTC"), end: EventTime(rawValue: "1970-01-01T00:00:02Z", instant: Date(timeIntervalSince1970: 2), dateOnly: nil, timeZoneID: "UTC"), recurring: false, status: nil)
        let invocations = try [factory.readCalendars(pageToken: nil), factory.readCalendar(id: calendar.id),
            factory.readEvents(calendarID: calendar.id, range: range, pageToken: "page &+"), factory.readEvent(calendarID: calendar.id, eventID: event.id),
            factory.readTaskLists(pageToken: nil), factory.readTaskList(id: task.taskListID), factory.readTasks(taskListID: task.taskListID, pageToken: nil), factory.readTask(taskListID: task.taskListID, taskID: task.id),
            factory.eventInsert(calendar: calendar, body: ["summary": "Synthetic"], authorization: .userSave), factory.eventPatch(event: event, calendar: calendar, body: ["summary": "Synthetic"], authorization: .userSave), factory.eventDelete(event: event, calendar: calendar, authorization: .confirmedDelete),
            factory.taskListInsert(title: "Synthetic", authorization: .userSave), factory.taskListPatch(id: "l", title: "Synthetic", authorization: .userSave), factory.taskListDelete(id: "l", authorization: .confirmedDelete),
            factory.taskInsert(taskListID: "l", title: "Synthetic", notes: nil, due: nil, authorization: .userSave), factory.taskPatch(task: task, title: "Synthetic", notes: nil, due: nil, authorization: .userSave), factory.taskMove(task: task, destinationTaskListID: "other/%?", authorization: .userSave), factory.taskDelete(task: task, authorization: .confirmedDelete)]
        let methods = ["GET", "GET", "GET", "GET", "GET", "GET", "GET", "GET", "POST", "PATCH", "DELETE", "POST", "PATCH", "DELETE", "POST", "PATCH", "POST", "DELETE"]
        for (index, invocation) in invocations.enumerated() {
            let request = try builder.build(invocation)
            try check(request.httpMethod == methods[index] && request.url?.scheme == "https", "all 18 operations use explicit REST methods")
            try check(request.url!.host == (index < 4 || (8...10).contains(index) ? "www.googleapis.com" : "tasks.googleapis.com"), "API host is fixed by domain")
        }
        let encoded = try builder.build(invocations[3]).url!.absoluteString
        try check(encoded.contains("c%2F%25%3F") && encoded.contains("e%2F%25%3F"), "resource segments escape slash percent question individually")
        let move = try builder.build(invocations[16])
        try check(move.httpBody == nil && move.url!.path.hasSuffix("/move") && URLComponents(url: move.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.name == "destinationTasklist", "task move uses destination query with no insert/delete body")
        let unsafe = ProcessInvocation(executableURL: GWSCommandFactory.restMarker, arguments: ["tasks", "tasks", "get", "--params", "{\"tasklist\":\"l\",\"task\":\"t\",\"host\":\"evil\"}"], operation: .taskGet, timeout: 2, outputLimit: 1024)
        do { _ = try builder.build(unsafe); throw TestFailure(description: "unsafe REST params accepted") } catch GWSFailure.forbiddenOperation { assertions += 1 }
        let mismatched = ProcessInvocation(executableURL: GWSCommandFactory.restMarker, arguments: invocations[0].arguments, operation: .taskGet, timeout: 2, outputLimit: 1024)
        do { _ = try builder.build(mismatched); throw TestFailure(description: "mismatched operation accepted") } catch GWSFailure.forbiddenOperation { assertions += 1 }
        let tokens = FakeGoogleTokens()
        let retryHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 429, headers: ["retry-after": "0"], body: Data()), GoogleHTTPResponse(statusCode: 503, headers: [:], body: Data()), GoogleHTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))])
        // The sleeper uses a locked recorder in production benchmarks; this focused
        // fixture is serial and verifies bounded attempts without real waiting.
        let runner = GoogleRESTRunner(http: retryHTTP, tokens: tokens, sleep: { _ in }, jitter: { 0 })
        _ = try runner.run(invocations[0])
        try check(retryHTTP.requests.count == 3, "GET retries quota/transient failures at most three calls")
        let writeHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 401, headers: [:], body: Data("secret forbidden details".utf8))])
        let failed = try GoogleRESTRunner(http: writeHTTP, tokens: tokens, sleep: { _ in }).run(invocations[14])
        try check(writeHTTP.requests.count == 1 && tokens.refreshes == 0 && !String(data: failed.stderr, encoding: .utf8)!.contains("secret"), "write401 never retries or leaks server text")
        let authHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 401, headers: [:], body: Data()), GoogleHTTPResponse(statusCode: 503, headers: [:], body: Data()), GoogleHTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))])
        _ = try GoogleRESTRunner(http: authHTTP, tokens: tokens, sleep: { _ in }).run(invocations[0])
        try check(tokens.refreshes == 1 && authHTTP.requests.count == 3, "401 followed by503 forces token refresh once")
        let permissionHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 403, headers: [:], body: Data())])
        _ = try GoogleRESTRunner(http: permissionHTTP, tokens: tokens).run(invocations[0])
        try check(permissionHTTP.requests.count == 1, "permission403 has no quota retry")
        let missingHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 410, headers: [:], body: Data())])
        let reader = GWSReadClient(factory: factory, runner: GoogleRESTRunner(http: missingHTTP, tokens: tokens))
        try check(try reader.task(taskListID: "l", taskID: "t") == nil, "structured410 passes exact GET missing proof")
        let cancelled = GWSReadCancellation(); var callbacks = 0
        let registration = cancelled.register { callbacks += 1 }; cancelled.cancel(); cancelled.unregister(registration)
        let cancellationHTTP = FakeGoogleHTTPClient([])
        do { _ = try GoogleRESTRunner(http: cancellationHTTP, tokens: tokens).run(invocations[0], cancellation: cancelled); throw TestFailure(description: "cancelled read started") } catch GWSFailure.readCancelled { assertions += 1 }
        try check(callbacks == 1 && cancellationHTTP.requests.isEmpty, "cancellation handlers cancel HTTP without starting more reads")
    }
}

extension InvariantTests {
    static func testGoogleOAuthIsolation() throws {
        let configData = Data(#"{"installed":{"client_id":"synthetic.apps.googleusercontent.com","client_secret":"synthetic","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}"#.utf8)
        let config = try GoogleOAuthClientConfiguration.imported(configData)
        try check(config.clientID == "synthetic.apps.googleusercontent.com", "Desktop JSON import uses own client")
        for invalid in [String(data: configData, encoding: .utf8)!.replacingOccurrences(of: "installed", with: "web"), String(data: configData, encoding: .utf8)!.replacingOccurrences(of: "oauth2.googleapis.com", with: "evil.invalid")] {
            do { _ = try GoogleOAuthClientConfiguration.imported(Data(invalid.utf8)); throw TestFailure(description: "unsafe OAuth JSON accepted") } catch GoogleRESTFailure.invalidConfiguration { assertions += 1 }
        }
        let pkce = try GooglePKCE.create()
        try check(pkce.verifier.count == 43 && pkce.challenge.count == 43 && pkce.state != pkce.verifier, "PKCE uses independent cryptographic32byte verifier/state")
        let known = GooglePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
        try check(known.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 RFC vector")
        let callback = "GET /oauth/callback?state=s&code=c HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n"
        try check(try GoogleOAuthEndpoint.callbackCode(callback, port: 8080, state: "s") == "c", "loopback callback validates exact host path state")
        for invalid in [callback.replacingOccurrences(of: "state=s", with: "state=bad"), callback.replacingOccurrences(of: "&code=c", with: "&code=c&code=d"), callback.replacingOccurrences(of: "127.0.0.1", with: "evil.invalid"), callback.replacingOccurrences(of: "GET", with: "POST"), callback.replacingOccurrences(of: "/oauth/callback", with: "/other")] {
            do { _ = try GoogleOAuthEndpoint.callbackCode(invalid, port: 8080, state: "s"); throw TestFailure(description: "invalid OAuth callback accepted") } catch GoogleRESTFailure.authentication { assertions += 1 }
        }
        try check(String(data: GoogleOAuthEndpoint.form(["code": "a+b &="]), encoding: .utf8) == "code=a%2Bb%20%26%3D", "OAuth form escapes literal plus and separators")
        let secrets = GoogleMemorySecretStore(); try secrets.write(configData, key: "fixture")
        try check(try secrets.read("fixture") == configData, "offline secret store never writes owner Keychain")
        let first = WorkspaceTransportContext.namespace(clientID: "a", subject: "b"), second = WorkspaceTransportContext.namespace(clientID: "a", subject: "c")
        try check(first.count == 64 && first != second && first != WorkspaceTransportContext.namespace(clientID: "a\u{0}b", subject: ""), "account namespace binds client and trusted subject")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rest-guard-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try check(WorkspaceTransportContext.durableSwitchAllowed(in: directory), "empty workspace allows transport setup")
        let journal = MutationJournal(fileURL: directory.appendingPathComponent("pending-verification.json"))
        let legacy = try GWSCommandFactory(executableURL: executable).taskListInsert(title: "Synthetic", authorization: .userSave)
        _ = try journal.begin(legacy)
        try check(!WorkspaceTransportContext.durableSwitchAllowed(in: directory), "legacy durable pending blocks account transport switching")
        var restFactory = GWSCommandFactory.googleREST(); restFactory.contextIdentity = first
        let http = FakeGoogleHTTPClient([]), runner = GoogleRESTRunner(http: http, tokens: FakeGoogleTokens())
        do { _ = try RecoverableMutationService(runner: runner, journal: journal).recheck(reader: GWSReadClient(factory: restFactory, runner: runner)); throw TestFailure(description: "legacy journal read through REST") } catch GWSFailure.forbiddenOperation { assertions += 1 }
        try check(http.requests.isEmpty && journal.pending != nil, "context mismatch rejects before network and retains journal")
        let profileNamespace = WorkspaceTransportContext.namespace(clientID: config.clientID, subject: "synthetic-sub")
        let archivedCredential = GoogleOAuthCredential(clientID: config.clientID, subject: "synthetic-sub", refreshToken: "synthetic")
        try secrets.write(JSONEncoder().encode(GoogleOAuthProfile(configuration: config, credential: archivedCredential)), key: "profile." + profileNamespace)
        let oldProfileDirectory = directory.appendingPathComponent("rest/" + profileNamespace)
        var oldFactory = GWSCommandFactory.googleREST(); oldFactory.contextIdentity = profileNamespace
        _ = try MutationJournal(fileURL: oldProfileDirectory.appendingPathComponent("pending-verification.json")).begin(oldFactory.taskListInsert(title: "Synthetic", authorization: .userSave))
        let defaults = UserDefaults(suiteName: "rest-context-test-" + UUID().uuidString)!
        defaults.set("rest", forKey: "activeGoogleTransport"); defaults.set(profileNamespace, forKey: "activeGoogleRESTIdentity"); defaults.set("gws", forKey: "requestedGoogleTransport")
        let preserved = WorkspaceTransportContext.load(defaults: defaults, secrets: secrets, http: FakeGoogleHTTPClient([]), applicationDirectory: directory)
        try check(preserved.kind == .rest && preserved.identity == profileNamespace && preserved.recoveryOnly && preserved.setupProblem == nil,
                  "startup switch guard retains archived old REST credentials solely for exact recovery")
        try check(try preserved.factory(configuredGWSPath: "").contextIdentity == profileNamespace, "old REST recovery factory retains account binding without gws binary")
        let a = NamespacedReminderScheduler(base: NoopReminderScheduler(), namespace: first), b = NamespacedReminderScheduler(base: NoopReminderScheduler(), namespace: second)
        try check(a.identifier("task") != b.identifier("task") && a.identifier("task") != "task", "REST notifications isolated from legacy and other subjects")
        let credential = GoogleOAuthCredential(clientID: config.clientID, subject: "synthetic-sub", refreshToken: "synthetic-refresh")
        let tokenBody = try JSONSerialization.data(withJSONObject: ["token_type": "Bearer", "access_token": "synthetic-access", "expires_in": 3600, "scope": GoogleOAuthEndpoint.scopes.joined(separator: " ")])
        let tokenHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 200, headers: [:], body: tokenBody), GoogleHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"sub":"synthetic-sub"}"#.utf8))])
        let provider = GoogleAccessTokenProvider(configuration: config, credential: credential, http: tokenHTTP)
        let group = DispatchGroup()
        let errors = OAuthTestErrors()
        for _ in 0..<4 { group.enter(); DispatchQueue.global().async { defer { group.leave() }; do { _ = try provider.accessToken(forceRefresh: false) } catch { errors.add() } } }
        group.wait()
        try check(errors.count == 0 && tokenHTTP.requests.count == 2, "four expired reads share one token refresh and trusted userinfo subject proof")
        let failedTokenHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 400, headers: [:], body: Data())]); failedTokenHTTP.latency = 0.1
        let failedProvider = GoogleAccessTokenProvider(configuration: config, credential: credential, http: failedTokenHTTP)
        let failedGroup = DispatchGroup(), failures = OAuthTestErrors()
        for _ in 0..<4 { failedGroup.enter(); DispatchQueue.global().async { defer { failedGroup.leave() }; do { _ = try failedProvider.accessToken(forceRefresh: false) } catch { failures.add() } } }
        failedGroup.wait()
        try check(failures.count == 4 && failedTokenHTTP.requests.count == 1, "singleflight failure reaches all waiters without serial repeated refreshes")
        let missingScopeHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"token_type":"Bearer","access_token":"synthetic","expires_in":3600}"#.utf8))])
        do { _ = try GoogleOAuthEndpoint.token(missingScopeHTTP, values: ["grant_type": "authorization_code"]); throw TestFailure(description: "missing initial OAuth scope accepted") } catch GoogleRESTFailure.authentication { assertions += 1 }
        let wrongHTTP = FakeGoogleHTTPClient([GoogleHTTPResponse(statusCode: 200, headers: [:], body: tokenBody), GoogleHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"sub":"wrong-sub"}"#.utf8))])
        do { _ = try GoogleAccessTokenProvider(configuration: config, credential: credential, http: wrongHTTP).accessToken(forceRefresh: false); throw TestFailure(description: "replaced subject accepted") } catch GoogleRESTFailure.authentication { assertions += 1 }
    }
}
private final class OAuthTestErrors: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func add() { lock.lock(); value += 1; lock.unlock() }
}

final class SyntheticGoogleURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/stall" { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 1024))
        client?.urlProtocol(self, didLoad: Data(repeating: 66, count: 1024))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

extension InvariantTests {
    static func testGoogleHTTPStreamingLimit() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyntheticGoogleURLProtocol.self]
        let http = GoogleURLSessionHTTPClient(configuration: config)
        defer { http.invalidate() }
        let group = DispatchGroup(), errors = OAuthTestErrors()
        weak var released: GoogleURLSessionHTTPClient?
        do { let temporary = GoogleURLSessionHTTPClient(configuration: config); released = temporary }
        try check(released == nil, "URLSession delegate does not retain its owner after context release")
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                _ = try http.send(URLRequest(url: URL(string: "https://tasks.googleapis.com/synthetic")!, timeoutInterval: 2), outputLimit: 1500, cancellation: nil)
            } catch GWSFailure.outputTooLarge { errors.add() } catch { }
        }
        group.wait()
        try check(errors.count == 1, "persistent URLSession enforces output cap while streaming synthetic chunks")
        let deadlines = OAuthTestErrors()
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do { _ = try http.send(URLRequest(url: URL(string: "https://tasks.googleapis.com/stall")!, timeoutInterval: 0.05), outputLimit: 1500, cancellation: nil) }
            catch GWSFailure.timedOut { deadlines.add() } catch GoogleRESTFailure.network { deadlines.add() } catch { }
        }
        group.wait()
        try check(deadlines.count == 1, "stalled HTTP fixture finishes within bounded request timeout")
    }
}
