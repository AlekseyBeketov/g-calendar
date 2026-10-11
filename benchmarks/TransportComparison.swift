import Foundation

private enum BenchmarkFailure: Error { case mismatch, configuration, setupRequired }

private struct BenchmarkConfiguration: Decodable {
    let schema: Int
    let mode: String
    let transport: String
    let samples: Int
    let rangeStart: String
    let rangeEnd: String
    let timeZone: String
}

// Entirely invented objects. No account resource identities or payloads are read
// or persisted in synthetic mode. This process also acts as a fixture gws binary.
private enum Fixture {
    static func task(_ list: Int, _ index: Int) -> [String: Any] {
        ["id": "task-\(list)-\(index)", "title": "Fixture task \(index)", "status": "needsAction",
         "due": "2026-10-\(String(format: "%02d", 5 + index % 7))T00:00:00.000Z"]
    }

    static func response(_ operation: GWSOperation, _ parameters: [String: Any], scenario: String) throws -> (Int, Data) {
        if scenario == "malformed" { return (200, Data("{broken".utf8)) }
        if scenario == "permission" { return try json(403, ["error": ["code": 403]]) }
        if scenario == "missing" { return try json(404, ["error": ["code": 404]]) }
        if scenario == "uncertain_write", operation == .taskInsert { return try json(503, ["error": ["code": 503]]) }
        if scenario == "empty" { return try json(200, [:]) }
        let listID = parameters["tasklist"] as? String ?? "list-0"
        let list = Int(listID.split(separator: "-").last ?? "0") ?? 0
        switch operation {
        case .calendarList:
            return try json(200, ["items": (0..<7).map { ["id": "calendar-\($0)", "summary": "Fixture calendar \($0)", "accessRole": "owner", "timeZone": "Europe/Moscow"] }])
        case .taskListsList:
            return try json(200, ["items": (0..<5).map { ["id": "list-\($0)", "title": "Fixture list \($0)"] }])
        case .tasksList:
            let count = list == 0 ? 30 : 29
            let offset = parameters["pageToken"] as? String == "page-2" ? 20 : 0
            let upper = scenario == "paged" ? min(count, offset + 20) : count
            var object: [String: Any] = ["items": (offset..<upper).map { task(list, $0) }]
            if upper < count { object["nextPageToken"] = "page-2" }
            return try json(200, object)
        case .eventsList:
            let calendarID = parameters["calendarId"] as? String ?? "calendar-0"
            let calendar = Int(calendarID.split(separator: "-").last ?? "0") ?? 0
            let count = calendar < 3 ? 5 : 4
            return try json(200, ["items": (0..<count).map { index in
                ["id": "event-\(calendar)-\(index)", "summary": "Fixture event \(index)",
                 "start": ["date": "2026-10-05"], "end": ["date": "2026-10-06"]] as [String: Any]
            }])
        case .taskGet:
            let id = parameters["task"] as? String ?? "task-0-0"
            let index = Int(id.split(separator: "-").last ?? "0") ?? 0
            return try json(200, task(list, index))
        default: throw BenchmarkFailure.configuration
        }
    }

    static func json(_ status: Int, _ object: [String: Any]) throws -> (Int, Data) {
        (status, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    static func child(_ arguments: [String]) throws {
        guard arguments.count >= 3, let operation = GWSOperation(rawValue: arguments.prefix(3).joined(separator: ".")) else { throw BenchmarkFailure.configuration }
        let parameters = WorkspaceSnapshotReducer.parameters(ProcessInvocation(executableURL: URL(fileURLWithPath: CommandLine.arguments[0]), arguments: arguments, operation: operation, timeout: 20, outputLimit: 2_097_152))
        let scenario = ProcessInfo.processInfo.environment["G_CALENDAR_SYNTHETIC_CASE"] ?? "normal"
        // This stub has no gws internal retry policy. Fault results describe the
        // application boundary and must not be called real CLI reliability.
        let selected = ["quota_once", "server_once", "auth_once"].contains(scenario) ? "permission" : scenario
        let (status, data) = try response(operation, parameters, scenario: selected)
        (status < 300 ? FileHandle.standardOutput : FileHandle.standardError).write(data)
        exit(status < 300 ? 0 : 1)
    }

    static func request(_ request: URLRequest) throws -> (GWSOperation, [String: Any]) {
        guard let url = request.url else { throw BenchmarkFailure.configuration }
        let pieces = url.path.split(separator: "/").map(String.init)
        var parameters: [String: Any] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { parameters[item.name] = item.value }
        if pieces == ["calendar", "v3", "users", "me", "calendarList"] { return (.calendarList, parameters) }
        if pieces == ["tasks", "v1", "users", "@me", "lists"] { return (.taskListsList, parameters) }
        if pieces.count == 5, pieces[0] == "calendar", pieces[2] == "calendars", pieces[4] == "events" {
            parameters["calendarId"] = pieces[3]; return (.eventsList, parameters)
        }
        if pieces.count >= 5, pieces[0] == "tasks", pieces[2] == "lists", pieces[4] == "tasks" {
            parameters["tasklist"] = pieces[3]
            if request.httpMethod == "POST" { return (.taskInsert, parameters) }
            if pieces.count == 6 { parameters["task"] = pieces[5]; return (.taskGet, parameters) }
            return (.tasksList, parameters)
        }
        throw BenchmarkFailure.configuration
    }
}

private final class FixtureTokens: GoogleAccessTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var refreshes = 0
    func accessToken(forceRefresh: Bool) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if forceRefresh { refreshes += 1 }
        return "synthetic-token"
    }
}

private final class FixtureHTTP: GoogleHTTPClient, @unchecked Sendable {
    let scenario: String
    private let lock = NSLock()
    private var calls = 0
    init(_ scenario: String) { self.scenario = scenario }
    func send(_ request: URLRequest, outputLimit: Int, cancellation: GWSReadCancellation?) throws -> GoogleHTTPResponse {
        lock.lock(); calls += 1; let current = calls; lock.unlock()
        if scenario == "cancelled" { cancellation?.cancel(); try cancellation?.check() }
        if current == 1, let status = ["quota_once": 429, "server_once": 503, "auth_once": 401][scenario] {
            return GoogleHTTPResponse(statusCode: status, headers: ["retry-after": "0"], body: Data())
        }
        let (operation, parameters) = try Fixture.request(request)
        let (status, data) = try Fixture.response(operation, parameters, scenario: scenario)
        return GoogleHTTPResponse(statusCode: status, headers: [:], body: data)
    }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
}

private final class CountingRunner: GWSReadProcessRunning, @unchecked Sendable {
    let underlying: GWSProcessRunning
    private let lock = NSLock()
    private var calls = 0, bytes = 0
    init(_ underlying: GWSProcessRunning) { self.underlying = underlying }
    func run(_ invocation: ProcessInvocation) throws -> ProcessResult { try run(invocation, cancellation: nil) }
    func run(_ invocation: ProcessInvocation, cancellation: GWSReadCancellation?) throws -> ProcessResult {
        lock.lock(); calls += 1; lock.unlock()
        let result: ProcessResult
        if let cancellable = underlying as? GWSReadProcessRunning { result = try cancellable.run(invocation, cancellation: cancellation) }
        else { result = try underlying.run(invocation) }
        lock.lock(); bytes += result.stdout.count + result.stderr.count; lock.unlock()
        return result
    }
    var totals: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (calls, bytes) }
}

private final class CountingHTTP: GoogleHTTPClient, @unchecked Sendable {
    let underlying: GoogleHTTPClient
    private let lock = NSLock()
    private var api = 0, auth = 0
    init(_ underlying: GoogleHTTPClient) { self.underlying = underlying }
    func send(_ request: URLRequest, outputLimit: Int, cancellation: GWSReadCancellation?) throws -> GoogleHTTPResponse {
        lock.lock()
        if ["tasks.googleapis.com", "www.googleapis.com"].contains(request.url?.host ?? "") { api += 1 } else { auth += 1 }
        lock.unlock()
        return try underlying.send(request, outputLimit: outputLimit, cancellation: cancellation)
    }
    var totals: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (api, auth) }
}

private struct FixtureContext {
    let runner: CountingRunner
    let reader: GWSReadClient
    let http: FixtureHTTP?
    let tokens: FixtureTokens?
    init(transport: String, scenario: String, cancellation: GWSReadCancellation? = nil) {
        let factory: GWSCommandFactory
        let underlying: GWSProcessRunning
        if transport == "rest" {
            let http = FixtureHTTP(scenario), tokens = FixtureTokens()
            self.http = http; self.tokens = tokens
            var restFactory = GWSCommandFactory.googleREST()
            restFactory.contextIdentity = "synthetic-benchmark"
            factory = restFactory
            underlying = GoogleRESTRunner(http: http, tokens: tokens, sleep: { _ in }, jitter: { 0 })
        } else {
            http = nil; tokens = nil
            factory = GWSCommandFactory(executableURL: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL)
            var environment = ProcessInfo.processInfo.environment
            environment["G_CALENDAR_SYNTHETIC_CASE"] = scenario
            underlying = FoundationProcessRunner(environment: environment)
        }
        runner = CountingRunner(underlying)
        reader = GWSReadClient(factory: factory, runner: runner, cancellation: cancellation)
    }
}

@main
private struct TransportComparison {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if ["calendar", "tasks"].contains(args.first ?? "") {
            do { try Fixture.child(args) } catch { exit(2) }
        }
        let completion = DispatchGroup(); completion.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { completion.leave() }
            do {
                guard let path = args.first else { throw BenchmarkFailure.configuration }
                let config = try JSONDecoder().decode(BenchmarkConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                guard config.schema == 1, config.mode == "synthetic", (20...100).contains(config.samples), ["paired", "gws", "rest"].contains(config.transport) else { throw BenchmarkFailure.configuration }
                let result = try args.dropFirst().contains("--live-read-only") ? measureLive(config) : measure(config)
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                fputs("Transport benchmark failed or requires Google setup. No Google writes or user-cache changes were performed.\n", stderr)
                exit(1)
            }
        }
        completion.wait()
    }

    static func measure(_ config: BenchmarkConfiguration) throws -> [String: Any] {
        let range = try configuredRange(config)
        var reports: [[String: Any]] = [], paired: [String: WorkspaceSnapshot] = [:]
        let transports = config.transport == "paired" ? ["gws", "rest"] : [config.transport]
        for transport in transports {
            for operation in ["full", "paged_full", "one_list", "exact_get", "range_cached_metadata", "cache_return"] {
                var values: [Double] = [], counts: [Int] = [], sizes: [Int] = []
                var baseline: WorkspaceSnapshot?
                for _ in 0..<config.samples {
                    let context = FixtureContext(transport: transport, scenario: operation == "paged_full" ? "paged" : "normal")
                    let service = GWSWorkspaceService(reader: context.reader, cache: MemorySnapshotStore())
                    if ["range_cached_metadata", "cache_return"].contains(operation) {
                        baseline = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .full)).merging(into: .empty)
                    }
                    let before = context.runner.totals
                    let started = DispatchTime.now().uptimeNanoseconds
                    switch operation {
                    case "full", "paged_full":
                        let snapshot = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .full)).merging(into: .empty)
                        guard snapshot.calendars.count == 7, snapshot.taskLists.count == 5, snapshot.tasks.count == 146, snapshot.events.count == 31 else { throw BenchmarkFailure.mismatch }
                        if let previous = paired[operation] {
                            guard previous.calendars == snapshot.calendars, previous.taskLists == snapshot.taskLists, previous.tasks == snapshot.tasks, previous.events == snapshot.events else { throw BenchmarkFailure.mismatch }
                        } else { paired[operation] = snapshot }
                    case "one_list":
                        let result = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .targeted, taskListIDs: ["list-0"]))
                        guard result.tasks.count == 30 else { throw BenchmarkFailure.mismatch }
                    case "exact_get":
                        guard try context.reader.readTask(taskListID: "list-0", taskID: "task-0-0").title == "Fixture task 0" else { throw BenchmarkFailure.mismatch }
                    case "range_cached_metadata":
                        let result = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .calendarRange), baseline: baseline)
                        guard result.events.count == 31 else { throw BenchmarkFailure.mismatch }
                    case "cache_return":
                        guard let baseline, CalendarRangeCache.activate(range: range, in: baseline) != nil else { throw BenchmarkFailure.mismatch }
                    default: throw BenchmarkFailure.configuration
                    }
                    values.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                    let after = context.runner.totals; counts.append(after.0 - before.0); sizes.append(after.1 - before.1)
                }
                reports.append(["transport": transport, "operation": operation, "samples": values.count, "p50_ms": percentile(values, 0.5), "p95_ms": percentile(values, 0.95), "calls": counts, "bytes": sizes, "elapsed_ms": values])
            }
            for scenario in ["quota_once", "server_once", "auth_once", "permission", "missing", "malformed", "empty", "cancelled", "uncertain_write"] {
                let cancellation = GWSReadCancellation()
                if scenario == "cancelled", transport == "gws" { cancellation.cancel() }
                let context = FixtureContext(transport: transport, scenario: scenario, cancellation: cancellation)
                var succeeded = false, blocked = false
                if scenario == "uncertain_write" {
                    let journal = MutationJournal()
                    let service = RecoverableMutationService(runner: context.runner, journal: journal)
                    let invocation = try context.reader.factory.taskInsert(taskListID: "list-0", title: "Fixture write", notes: nil, due: nil, authorization: .userSave)
                    do { _ = try service.perform(invocation, reader: context.reader); succeeded = true } catch { }
                    blocked = journal.isBlocked
                    guard blocked, !succeeded, context.runner.totals.0 == 1 else { throw BenchmarkFailure.mismatch }
                } else if scenario == "empty" {
                    succeeded = (try? context.reader.tasks(taskListID: "list-0").isEmpty) == true
                    guard succeeded else { throw BenchmarkFailure.mismatch }
                } else {
                    do { _ = try context.reader.readTask(taskListID: "list-0", taskID: "task-0-0"); succeeded = true } catch { }
                    let expected = transport == "rest" && ["quota_once", "server_once", "auth_once"].contains(scenario)
                    guard succeeded == expected else { throw BenchmarkFailure.mismatch }
                }
                reports.append(["transport": transport, "operation": scenario, "succeeded": succeeded, "journal_blocked": blocked,
                                "calls": context.runner.totals.0, "http_calls": context.http?.callCount ?? 0, "token_refreshes": context.tokens?.refreshes ?? 0])
            }
        }
        return ["schema": 1, "mode": "synthetic", "samples": reports, "identity_match": true,
                "environment": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64"],
                "source": sourceMetadata(),
                "note": "Synthetic process/HTTP boundaries; no real Google latency or gws internal retry policy measured. All objects invented; no user data persisted."]
    }

    static func sourceMetadata() -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        return ["commit": environment["G_CALENDAR_BENCHMARK_COMMIT"] ?? "unknown",
                "swift": environment["G_CALENDAR_BENCHMARK_SWIFT"] ?? "unknown",
                "orx_run": environment["ORX_RUN_ID"] ?? "see-external-run-record"]
    }

    // Explicitly opt-in and reads only. Load Keychain directly rather than the
    // application transport context: no settings, journals or caches are changed.
    static func measureLive(_ config: BenchmarkConfiguration) throws -> [String: Any] {
        guard config.transport == "paired" else { throw BenchmarkFailure.configuration }
        let secrets = GoogleKeychainSecretStore()
        guard let configurationData = try secrets.read("configuration"), let credentialData = try secrets.read("credential") else { throw BenchmarkFailure.setupRequired }
        let configuration = try JSONDecoder().decode(GoogleOAuthClientConfiguration.self, from: configurationData)
        let credential = try JSONDecoder().decode(GoogleOAuthCredential.self, from: credentialData)
        guard configuration.clientID == credential.clientID, !credential.subject.isEmpty, !credential.refreshToken.isEmpty else { throw BenchmarkFailure.setupRequired }
        let path = ProcessInfo.processInfo.environment["G_CALENDAR_GWS_PATH"] ?? UserDefaults.standard.string(forKey: "gwsExecutablePath")
        let executable = try GWSExecutableResolver().resolve(configuredPath: path)
        let range = try configuredRange(config)
        var reports: [[String: Any]] = []
        func context(_ transport: String) -> (GWSReadClient, CountingRunner, GoogleURLSessionHTTPClient?, CountingHTTP?) {
            var measuredHTTP: CountingHTTP?
            var ownedHTTP: GoogleURLSessionHTTPClient?
            let factory: GWSCommandFactory, underlying: GWSProcessRunning
            if transport == "gws" { factory = GWSCommandFactory(executableURL: executable); underlying = FoundationProcessRunner() }
            else {
                let session = GoogleURLSessionHTTPClient(); ownedHTTP = session
                let http = CountingHTTP(session); measuredHTTP = http
                var restFactory = GWSCommandFactory.googleREST()
                restFactory.contextIdentity = WorkspaceTransportContext.namespace(clientID: configuration.clientID, subject: credential.subject)
                factory = restFactory
                underlying = GoogleRESTRunner(http: http, tokens: GoogleAccessTokenProvider(configuration: configuration, credential: credential, http: http))
            }
            let counted = CountingRunner(ReadOnlyRunner(underlying))
            return (GWSReadClient(factory: factory, runner: counted), counted, ownedHTTP, measuredHTTP)
        }
        for temperature in ["cold", "warm"] {
            let warmContexts = ["gws": context("gws"), "rest": context("rest")]
            defer { warmContexts.values.forEach { $0.2?.invalidate() } }
            if temperature == "warm" {
                var warmup: [String: WorkspaceSnapshot] = [:]
                for transport in ["gws", "rest"] {
                    warmup[transport] = try GWSWorkspaceService(reader: warmContexts[transport]!.0, cache: MemorySnapshotStore())
                        .read(query: WorkspaceRefreshQuery(range: range, scope: .full)).merging(into: .empty)
                }
                guard sameObjects(warmup["gws"]!, warmup["rest"]!) else { throw BenchmarkFailure.mismatch }
            }
            var times: [String: [Double]] = ["gws": [], "rest": []]
            var calls: [String: [Int]] = ["gws": [], "rest": []], bytes = calls
            var restAPI: [Int] = [], restAuth: [Int] = []
            for index in 0..<config.samples {
                var snapshots: [String: WorkspaceSnapshot] = [:]
                for transport in index.isMultiple(of: 2) ? ["gws", "rest"] : ["rest", "gws"] {
                    let active = temperature == "cold" ? context(transport) : warmContexts[transport]!
                    defer { if temperature == "cold" { active.2?.invalidate() } }
                    let before = active.1.totals, httpBefore = active.3?.totals
                    let started = DispatchTime.now().uptimeNanoseconds
                    let payload = try GWSWorkspaceService(reader: active.0, cache: MemorySnapshotStore()).read(query: WorkspaceRefreshQuery(range: range, scope: .full))
                    times[transport]!.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                    let after = active.1.totals; calls[transport]!.append(after.0 - before.0); bytes[transport]!.append(after.1 - before.1)
                    if let httpBefore, let afterHTTP = active.3?.totals { restAPI.append(afterHTTP.0 - httpBefore.0); restAuth.append(afterHTTP.1 - httpBefore.1) }
                    snapshots[transport] = try payload.merging(into: .empty)
                }
                guard sameObjects(snapshots["gws"]!, snapshots["rest"]!) else { throw BenchmarkFailure.mismatch }
            }
            for transport in ["gws", "rest"] {
                let values = times[transport]!
                reports.append(["transport": transport, "operation": "full_" + temperature, "samples": values.count,
                                "p50_ms": percentile(values, 0.5), "p95_ms": percentile(values, 0.95), "elapsed_ms": values,
                                "logical_operation_calls": calls[transport]!, "response_payload_bytes": bytes[transport]!,
                                "rest_api_http_attempts": transport == "rest" ? restAPI : [], "rest_oauth_http_attempts": transport == "rest" ? restAuth : []])
            }

        }
        let activeContexts = ["gws": context("gws"), "rest": context("rest")]
        defer { activeContexts.values.forEach { $0.2?.invalidate() } }
        var baselines: [String: WorkspaceSnapshot] = [:]
        for transport in ["gws", "rest"] {
            baselines[transport] = try GWSWorkspaceService(reader: activeContexts[transport]!.0, cache: MemorySnapshotStore())
                .read(query: WorkspaceRefreshQuery(range: range, scope: .full)).merging(into: .empty)
        }
        guard sameObjects(baselines["gws"]!, baselines["rest"]!) else { throw BenchmarkFailure.mismatch }
        let listID = baselines["gws"]!.taskLists.sorted { $0.id < $1.id }.first?.id
        let task = baselines["gws"]!.tasks.sorted { $0.taskListID + $0.id < $1.taskListID + $1.id }.first
        for operation in ["one_list", "exact_get", "range_cached_metadata", "cache_return"] {
            // An empty account has no resource for an exact/scoped read.
            if operation == "one_list" && listID == nil || operation == "exact_get" && task == nil {
                reports.append(["operation": operation, "skipped": "empty_account"]); continue
            }
            var times: [String: [Double]] = ["gws": [], "rest": []]
            var calls: [String: [Int]] = ["gws": [], "rest": []], bytes = calls
            var restAPI: [Int] = [], restAuth: [Int] = []
            for index in 0..<config.samples {
                var results: [String: WorkspaceSnapshot] = [:]
                for transport in index.isMultiple(of: 2) ? ["gws", "rest"] : ["rest", "gws"] {
                    let active = activeContexts[transport]!, baseline = baselines[transport]!
                    let before = active.1.totals, httpBefore = active.3?.totals, started = DispatchTime.now().uptimeNanoseconds
                    let service = GWSWorkspaceService(reader: active.0, cache: MemorySnapshotStore())
                    switch operation {
                    case "one_list":
                        results[transport] = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .targeted, taskListIDs: [listID!]), baseline: baseline).merging(into: baseline)
                    case "exact_get":
                        let verified = try active.0.readTask(taskListID: task!.taskListID, taskID: task!.id)
                        var result = WorkspaceSnapshot.empty; result.tasks = [verified]; results[transport] = result
                    case "range_cached_metadata":
                        results[transport] = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .calendarRange), baseline: baseline).merging(into: baseline)
                    case "cache_return":
                        guard let cached = CalendarRangeCache.activate(range: range, in: baseline) else { throw BenchmarkFailure.mismatch }
                        results[transport] = cached
                    default: throw BenchmarkFailure.configuration
                    }
                    times[transport]!.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                    let after = active.1.totals; calls[transport]!.append(after.0 - before.0); bytes[transport]!.append(after.1 - before.1)
                    if let httpBefore, let afterHTTP = active.3?.totals { restAPI.append(afterHTTP.0 - httpBefore.0); restAuth.append(afterHTTP.1 - httpBefore.1) }
                }
                guard sameObjects(results["gws"]!, results["rest"]!) else { throw BenchmarkFailure.mismatch }
            }
            for transport in ["gws", "rest"] {
                let values = times[transport]!
                reports.append(["transport": transport, "operation": operation, "samples": values.count,
                                "p50_ms": percentile(values, 0.5), "p95_ms": percentile(values, 0.95), "elapsed_ms": values,
                                "logical_operation_calls": calls[transport]!, "response_payload_bytes": bytes[transport]!,
                                "rest_api_http_attempts": transport == "rest" ? restAPI : [], "rest_oauth_http_attempts": transport == "rest" ? restAuth : []])
            }
        }
        return ["schema": 1, "mode": "live_read_only", "identity_match": true, "samples": reports,
                "range": ["start": config.rangeStart, "end": config.rangeEnd, "timeZone": config.timeZone],
                "source": sourceMetadata(), "environment": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64"],
                "note": "20+ paired full cold/warm and scoped/exact/range/cache reads, alternating order, committed range and fields. gws stdout bytes and REST response bytes are payload sizes, not captured wire traffic. No Google writes or user-cache changes."]
    }

    static func sameObjects(_ left: WorkspaceSnapshot, _ right: WorkspaceSnapshot) -> Bool {
        left.calendars.sorted { $0.id < $1.id } == right.calendars.sorted { $0.id < $1.id }
            && left.taskLists.sorted { $0.id < $1.id } == right.taskLists.sorted { $0.id < $1.id }
            && left.tasks.sorted { $0.taskListID + "\u{0}" + $0.id < $1.taskListID + "\u{0}" + $1.id } == right.tasks.sorted { $0.taskListID + "\u{0}" + $0.id < $1.taskListID + "\u{0}" + $1.id }
            && left.events.sorted { $0.calendarID + "\u{0}" + $0.id < $1.calendarID + "\u{0}" + $1.id } == right.events.sorted { $0.calendarID + "\u{0}" + $0.id < $1.calendarID + "\u{0}" + $1.id }
    }

    static func configuredRange(_ config: BenchmarkConfiguration) throws -> DateRange {
        guard let zone = TimeZone(identifier: config.timeZone), let start = ISO8601.parse(config.rangeStart),
              let end = ISO8601.parse(config.rangeEnd) else { throw BenchmarkFailure.configuration }
        return try DateRange(start: start, endExclusive: end, timeZone: zone)
    }

    static func percentile(_ values: [Double], _ quantile: Double) -> Double {
        let sorted = values.sorted(); return sorted[max(0, Int(ceil(Double(sorted.count) * quantile)) - 1)]
    }
}

private struct ReadOnlyRunner: GWSReadProcessRunning {
    let underlying: GWSProcessRunning
    init(_ underlying: GWSProcessRunning) { self.underlying = underlying }
    func run(_ invocation: ProcessInvocation) throws -> ProcessResult { try run(invocation, cancellation: nil) }
    func run(_ invocation: ProcessInvocation, cancellation: GWSReadCancellation?) throws -> ProcessResult {
        guard [.calendarList, .calendarGet, .eventsList, .eventGet, .taskListsList, .taskListGet, .tasksList, .taskGet].contains(invocation.operation) else { throw GWSFailure.forbiddenOperation }
        if let cancellable = underlying as? GWSReadProcessRunning { return try cancellable.run(invocation, cancellation: cancellation) }
        return try underlying.run(invocation)
    }
}
