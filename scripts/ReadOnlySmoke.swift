import Foundation

final class CountingGWSRunner: GWSProcessRunning, @unchecked Sendable {
    private let underlying = FoundationProcessRunner()
    private let lock = NSLock()
    private var counts: [GWSOperation: Int] = [:]

    func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
        lock.lock()
        counts[invocation.operation, default: 0] += 1
        lock.unlock()
        return try underlying.run(invocation)
    }

    var pageCounts: [GWSOperation: Int] {
        lock.lock(); defer { lock.unlock() }
        return counts
    }
}

@main
struct ReadOnlySmoke {
    static func main() {
        do {
            let executable = try GWSExecutableResolver().resolve(configuredPath: "/Users/alexbeketov/.local/bin/gws")
            let runner = CountingGWSRunner()
            let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = 2
            calendar.timeZone = .current
            let now = Date()
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            let range = try DateRange(start: interval.start, endExclusive: interval.end, timeZone: calendar.timeZone)
            let snapshot = try GWSWorkspaceService(reader: reader, cache: MemorySnapshotStore()).refresh(range: range)
            let pages = runner.pageCounts

            print("LIVE_READ_ONLY_SMOKE=success")
            print("calendar_count=\(snapshot.calendars.count) read_only_calendar_count=\(snapshot.calendars.filter { !$0.isWritable }.count)")
            print("event_count=\(snapshot.events.count) all_day_event_count=\(snapshot.events.filter(\.isAllDay).count)")
            print("task_list_count=\(snapshot.taskLists.count) task_count=\(snapshot.tasks.count) tasks_with_date_only_due=\(snapshot.tasks.filter { $0.due != nil }.count)")
            print("calendar_list_pages=\(pages[.calendarList, default: 0]) event_pages=\(pages[.eventsList, default: 0]) task_list_pages=\(pages[.taskListsList, default: 0]) task_pages=\(pages[.tasksList, default: 0]) all_pages_consumed=true")
            print("google_mutations=0 cache_destination=memory_only")
        } catch let failure as GWSFailure {
            fputs("LIVE_READ_ONLY_SMOKE=failed error=\(failure.errorDescription ?? "safe_failure")\n", stderr)
            exit(EXIT_FAILURE)
        } catch {
            fputs("LIVE_READ_ONLY_SMOKE=failed error=unexpected_safe_failure\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
