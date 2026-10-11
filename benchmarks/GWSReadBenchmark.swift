import Foundation

// Live reads are opt-in. Payloads and resource identities stay in memory.
private final class CountingReadRunner: GWSProcessRunning, @unchecked Sendable {
    private let underlying = FoundationProcessRunner()
    private let lock = NSLock()
    private var calls = 0
    private var bytes = 0

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
        guard [.calendarList, .eventsList, .taskListsList, .tasksList].contains(invocation.operation) else {
            throw GWSFailure.forbiddenOperation
        }
        let result = try underlying.run(invocation)
        lock.lock()
        calls += 1
        bytes += result.stdout.count
        lock.unlock()
        return result
    }

    func totals() -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        return (calls, bytes)
    }
}

@main
struct GWSReadBenchmark {
    static func main() {
        guard CommandLine.arguments.dropFirst() == ["--live-read-only"] else {
            fputs("Explicit --live-read-only is required. No writes are supported.\n", stderr)
            exit(2)
        }
        do { try measure() }
        catch {
            // Never print request URLs, resource identities or underlying errors.
            fputs("Read benchmark failed; no Google writes or user-cache changes were performed.\n", stderr)
            exit(1)
        }
    }

    private static func measure() throws {
        let path = ProcessInfo.processInfo.environment["G_CALENDAR_GWS_PATH"]
        let executable = try GWSExecutableResolver().resolve(configuredPath: path)
        let zone = TimeZone(identifier: "Europe/Moscow")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = zone
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date())!
        let range = try DateRange(start: interval.start, endExclusive: interval.end, timeZone: zone)
        var samples: [[String: Any]] = []
        for index in 0..<3 {
            let runner = CountingReadRunner()
            let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
            let service = GWSWorkspaceService(reader: reader, cache: MemorySnapshotStore())
            let start = DispatchTime.now().uptimeNanoseconds
            let full = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .full))
            let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let totals = runner.totals()
            samples.append(["operation": "full_parallel4", "sample": index, "elapsed_ms": duration,
                            "calls": totals.0, "bytes": totals.1, "calendars": full.calendars?.count ?? 0,
                            "lists": full.taskLists?.count ?? 0, "events": full.events.count, "tasks": full.tasks.count])
            if let list = full.taskLists?.first {
                let before = runner.totals()
                let targetStart = DispatchTime.now().uptimeNanoseconds
                let partial = try service.read(query: WorkspaceRefreshQuery(range: range, scope: .targeted, taskListIDs: [list.id]))
                let targetDuration = Double(DispatchTime.now().uptimeNanoseconds - targetStart) / 1_000_000
                let after = runner.totals()
                samples.append(["operation": "one_list", "sample": index, "elapsed_ms": targetDuration,
                                "calls": after.0 - before.0, "bytes": after.1 - before.1, "tasks": partial.tasks.count])
            }
        }
        let output: [String: Any] = ["schema": 1, "mode": "live_read_only", "samples": samples,
                                     "note": "Three samples; not p95. No resource data persisted."]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
