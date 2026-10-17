import Foundation

/// Local, opt-in-to-sharing diagnostics. The API accepts no free-form payloads.
final class AppDiagnostics: @unchecked Sendable {
    enum Event: String { case launch, requestStarted, requestFinished, mutationStarted, mutationFinished, uiStall, uiRecovered }
    enum Outcome: String { case success, failure, timeout, cancelled, pendingVerification, rejected, invalidResponse }
    static let preferenceKey = "diagnosticLoggingEnabled"
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("g-calendar/Logs", isDirectory: true)
    static let shared = AppDiagnostics(directory: directory, enabled: false)

    private let directory: URL
    private let queue = DispatchQueue(label: "g-calendar.diagnostics", qos: .utility)
    private let lock = NSLock()
    private var enabled: Bool
    private var generation = 0
    private var pending = 0
    private let fileLimit: Int
    private let retention: TimeInterval = 7 * 86400
    private var lastPrune: Date?
    private var heartbeat: DispatchSourceTimer?
    private var awaitingHeartbeat: TimeInterval?
    private var reportedStall = false
    private var monitoring = false

    init(directory: URL, enabled: Bool, fileLimit: Int = 256 * 1024) {
        self.directory = directory
        self.enabled = enabled
        self.fileLimit = max(256, fileLimit)
    }

    func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value; generation += 1; lock.unlock()
        queue.async { [self] in
            try? prune(now: Date())
            awaitingHeartbeat = nil; reportedStall = false
        }
    }

    func record(_ event: Event, operation: GWSOperation? = nil, outcome: Outcome? = nil,
                milliseconds: Int? = nil, now: Date = Date()) {
        lock.lock()
        guard enabled, pending < 256 else { lock.unlock(); return }
        let captured = generation
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            lock.lock(); let allowed = enabled && generation == captured; lock.unlock()
            guard allowed else { return }
            var entry: [String: Any] = ["time": now.timeIntervalSince1970, "event": event.rawValue]
            if let operation { entry["operation"] = operation.rawValue }
            if let outcome { entry["outcome"] = outcome.rawValue }
            if let milliseconds { entry["duration_ms"] = max(0, milliseconds) }
            guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
            data.append(10)
            try? append(data, now: now)
        }
    }

    static func outcome(for error: Error) -> Outcome {
        switch error {
        case GWSFailure.timedOut: return .timeout
        case GWSFailure.readCancelled, GoogleRESTFailure.cancelled: return .cancelled
        case MutationRecoveryFailure.pendingVerification, MutationRecoveryFailure.unknownIdentity,
             GWSFailure.mutationNotVerified: return .pendingVerification
        case GWSFailure.invalidResponse, GWSFailure.paginationLoop: return .invalidResponse
        case GWSFailure.forbiddenOperation: return .rejected
        case is GoogleRESTUnsubmittedFailure: return .rejected
        default: return .failure
        }
    }

    func clear(completion: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); generation += 1; lock.unlock()
        queue.async { [self] in
            do {
                for url in try files() { try FileManager.default.removeItem(at: url) }
                completion(true)
            } catch { completion(false) }
        }
    }

    // Tests and shutdown tooling only; never call on the UI path.
    func flush() { queue.sync {} }

    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]).filter {
            let parts = $0.lastPathComponent.split(separator: ".")
            return parts.count == 3 && Int(parts[0]) != nil && ["0", "1"].contains(parts[1]) && parts[2] == "jsonl"
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func prune(now: Date) throws {
        let cutoff = now.addingTimeInterval(-retention).timeIntervalSince1970
        for url in try files() {
            guard let day = Double(url.lastPathComponent.split(separator: ".")[0]) else { continue }
            if day * 86400 < cutoff { try FileManager.default.removeItem(at: url) }
        }
        let remaining = try files().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in remaining.prefix(max(0, remaining.count - 14)) { try FileManager.default.removeItem(at: url) }
        lastPrune = now
    }

    private func append(_ data: Data, now: Date) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if lastPrune == nil || now.timeIntervalSince(lastPrune!) >= 3600 { try prune(now: now) }
        let day = Int(floor(now.timeIntervalSince1970 / 86400))
        let current = directory.appendingPathComponent("\(day).0.jsonl")
        let previous = directory.appendingPathComponent("\(day).1.jsonl")
        let size = (try? manager.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + data.count > fileLimit {
            if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
            if manager.fileExists(atPath: current.path) { try manager.moveItem(at: current, to: previous) }
        }
        if !manager.fileExists(atPath: current.path) {
            guard manager.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
        }
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        if size == 0 { try prune(now: now) }
    }

    /// A single outstanding main-queue ping; a blocked UI cannot grow this queue.
    func startResponsivenessMonitor() {
        queue.async { [self] in
            guard !monitoring else { return }
            monitoring = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.sampleHeartbeat() }
            heartbeat = timer
            timer.resume()
        }
    }

    private func sampleHeartbeat() {
        lock.lock(); let active = enabled; lock.unlock()
        if lastPrune == nil || Date().timeIntervalSince(lastPrune!) >= 3600 { try? prune(now: Date()) }
        guard active else { awaitingHeartbeat = nil; return }
        let now = ProcessInfo.processInfo.systemUptime
        if let start = awaitingHeartbeat {
            if now - start >= 2, !reportedStall {
                reportedStall = true
                record(.uiStall, milliseconds: Int((now - start) * 1000))
            }
            return
        }
        awaitingHeartbeat = now
        DispatchQueue.main.async { [weak self] in
            self?.queue.async { [weak self] in
                guard let self else { return }
                if self.reportedStall, let start = self.awaitingHeartbeat {
                    self.record(.uiRecovered, milliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
                }
                self.awaitingHeartbeat = nil; self.reportedStall = false
            }
        }
    }

    deinit { heartbeat?.cancel() }
}

struct DiagnosticProcessRunner: GWSReadProcessRunning {
    let base: GWSProcessRunning
    let diagnostics: AppDiagnostics

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult { try run(invocation, cancellation: nil) }
    func run(_ invocation: ProcessInvocation, cancellation: GWSReadCancellation?) throws -> ProcessResult {
        let start = ProcessInfo.processInfo.systemUptime
        diagnostics.record(.requestStarted, operation: invocation.operation)
        do {
            let result: ProcessResult
            if let reader = base as? GWSReadProcessRunning { result = try reader.run(invocation, cancellation: cancellation) }
            else { try cancellation?.check(); result = try base.run(invocation) }
            diagnostics.record(.requestFinished, operation: invocation.operation, outcome: result.exitCode == 0 ? .success : .failure,
                               milliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            return result
        } catch {
            diagnostics.record(.requestFinished, operation: invocation.operation, outcome: AppDiagnostics.outcome(for: error),
                               milliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            throw error
        }
    }
}
