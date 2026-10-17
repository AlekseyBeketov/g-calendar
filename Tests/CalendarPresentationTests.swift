import Foundation

extension InvariantTests {
    static func testCalendarWeekStart() throws {
        let suite = "gcalendar.calendar-week-start-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(CalendarWeekStart.load(from: defaults) == .monday, "existing users retain Monday by default")
        for preference in CalendarWeekStart.allCases {
            preference.save(to: defaults)
            try check(CalendarWeekStart.load(from: UserDefaults(suiteName: suite)!) == preference, "week start survives settings reload")
        }
        defaults.set("invalid", forKey: "calendarWeekStart")
        try check(CalendarWeekStart.load(from: defaults) == .monday, "invalid setting safely falls back to Monday")
        var system = Calendar(identifier: .gregorian)
        system.locale = Locale(identifier: "en_US")
        system.firstWeekday = 1
        try check(CalendarWeekStart.system.firstWeekday(systemCalendar: system) == 1, "system preference follows regional Sunday")
        try check(CalendarWeekStart.monday.firstWeekday(systemCalendar: system) == 2, "explicit Monday overrides regional Sunday")
        system.locale = Locale(identifier: "ru_RU")
        system.firstWeekday = 2
        try check(CalendarWeekStart.system.firstWeekday(systemCalendar: system) == 2, "system preference follows regional Monday")
        try check(CalendarWeekStart.sunday.firstWeekday(systemCalendar: system) == 1, "explicit Sunday overrides regional Monday")

        for zoneID in ["Europe/Moscow", "America/Los_Angeles"] {
            let zone = TimeZone(identifier: zoneID)!
            let date = DateOnly(rawValue: "2026-03-11")!.startOfDay(in: zone)!
            for (preference, first, monthFirst, monthEnd) in [
                (CalendarWeekStart.monday, "2026-03-09", "2026-02-23", "2026-04-06"),
                (CalendarWeekStart.sunday, "2026-03-08", "2026-03-01", "2026-04-05")
            ] {
                let weekday = preference.firstWeekday()
                let week = CalendarDatePolicy.range(containing: date, mode: .week, timeZone: zone, firstWeekday: weekday)
                let month = CalendarDatePolicy.range(containing: date, mode: .month, timeZone: zone, firstWeekday: weekday)
                try check(DateOnly(date: week.start, timeZone: zone).description == first && CalendarDatePolicy.days(in: week).count == 7, "explicit week start independent of timezone and DST")
                try check(DateOnly(date: month.start, timeZone: zone).description == monthFirst && DateOnly(date: month.endExclusive, timeZone: zone).description == monthEnd, "month padding follows chosen weekday")
                let day = CalendarDatePolicy.range(containing: date, mode: .day, timeZone: zone, firstWeekday: weekday)
                try check(day.start == date && CalendarDatePolicy.days(in: day).count == 1, "week-start choice never shifts day mode")
                var prefetch = CalendarNeighbourPrefetch()
                let next = prefetch.neighbours(after: week, calendars: [], snapshot: .empty, firstWeekday: weekday)
                try check(next.count == 1 && next[0].start == week.endExclusive && CalendarDatePolicy.days(in: next[0]).count == 7, "prefetch follows displayed week's start across DST")
                try check(prefetch.neighbours(after: month, calendars: [], snapshot: .empty, firstWeekday: weekday).isEmpty, "month does not speculate on already visible weeks")
            }
        }
        let instant = ISO8601DateFormatter().date(from: "2026-10-12T22:30:00Z")!
        try check(DateOnly(date: instant, timeZone: TimeZone(identifier: "Europe/Moscow")!).description == "2026-10-13" && DateOnly(date: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!).description == "2026-10-12", "today uses calendar's local date, independently of week-start choice")
    }

    static func testCalendarPresentation() throws {
        for zoneID in ["Europe/Moscow", "America/Los_Angeles"] {
            let zone = TimeZone(identifier: zoneID)!
            for (input, first, end, count) in [
                ("2024-02-15", "2024-01-29", "2024-03-04", 35),
                ("2021-02-15", "2021-02-01", "2021-03-01", 28),
                ("2026-03-15", "2026-02-23", "2026-04-06", 42),
                ("2026-12-15", "2026-11-30", "2027-01-04", 35)
            ] {
                let date = DateOnly(rawValue: input)!.startOfDay(in: zone)!
                let range = CalendarDatePolicy.range(containing: date, mode: .month, timeZone: zone)
                let days = CalendarDatePolicy.days(in: range)
                try check(DateOnly(date: range.start, timeZone: zone).description == first, "month starts at first visible Monday")
                try check(DateOnly(date: range.endExclusive, timeZone: zone).description == end, "month includes complete final week")
                try check(days.count == count && Set(days).count == count, "month contains unique local days across DST and leap year")
            }
            let january = DateOnly(rawValue: "2026-01-31")!.startOfDay(in: zone)!
            let february = CalendarDatePolicy.moving(january, by: 1, mode: .month, timeZone: zone)!
            let march = CalendarDatePolicy.moving(february, by: 1, mode: .month, timeZone: zone)!
            try check(DateOnly(date: february, timeZone: zone).description == "2026-02-01" && DateOnly(date: march, timeZone: zone).description == "2026-03-01", "month navigation cannot skip short months")
            try check(CalendarDatePolicy.days(in: CalendarDatePolicy.range(containing: january, mode: .day, timeZone: zone)).count == 1, "day range unchanged")
            try check(CalendarDatePolicy.days(in: CalendarDatePolicy.range(containing: january, mode: .week, timeZone: zone)).count == 7, "week range unchanged")
        }
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let date = DateOnly(rawValue: "2026-03-15")!.startOfDay(in: zone)!
        let range = CalendarDatePolicy.range(containing: date, mode: .month, timeZone: zone)
        let event = try CalendarEvent.decode(["id": "span", "summary": "Needle event", "start": ["date": "2026-03-30"], "end": ["date": "2026-04-02"]], calendarID: "c")
        let task = GoogleTask(id: "task", taskListID: "l", title: "Needle task", notes: nil, due: DateOnly(rawValue: "2026-04-01"), completed: false, deleted: false, updated: nil)
        let undated = GoogleTask(id: "undated", taskListID: "l", title: "Needle undated", notes: nil, due: nil, completed: false, deleted: false, updated: nil)
        let projection = CalendarWorkspaceProjection(range: range, isDayView: false, events: [event], tasks: [task, undated], visibleCalendarIDs: ["c"], selectedTaskListID: "l", searchText: "needle")
        try check(projection.days.count == 42 && projection.days.filter { !$0.events.isEmpty }.count == 3, "month projection includes final week and respects all-day exclusive end")
        try check(projection.days.first { DateOnly(date: $0.day, timeZone: zone) == task.due }?.tasks == [task], "adjacent month's date-only task belongs to its real date")
        try check(projection.undatedTasks == [undated], "month does not duplicate undated tasks")
        let hidden = CalendarWorkspaceProjection(range: range, isDayView: false, events: [event], tasks: [task, undated], visibleCalendarIDs: [], selectedTaskListID: "other", searchText: "needle")
        try check(hidden.days.allSatisfy { $0.events.isEmpty && $0.tasks.isEmpty } && hidden.undatedTasks.isEmpty, "month honors calendar visibility and task-list scope")
    }
}


extension InvariantTests {
    static func testCalendarProjectionReuse() throws {
        let range = try DateRange(start: Date(timeIntervalSince1970: 0), endExclusive: Date(timeIntervalSince1970: 42 * 86400))
        let cache = CalendarProjectionCache()
        func projection(_ search: String = "", calendars: Set<String>? = nil) -> CalendarWorkspaceProjection {
            cache.value(range: range, isDayView: false, events: [], tasks: [], visibleCalendarIDs: calendars,
                        selectedTaskListID: nil, searchText: search)
        }
        let original = projection()
        for _ in 0..<100 { try check(projection() == original, "geometry updates reuse calendar content") }
        try check(cache.buildCount == 1, "scroll/layout must not rebuild an unchanged month")
        _ = projection("changed")
        _ = projection("changed", calendars: ["calendar"])
        try check(cache.buildCount == 3, "search and calendar visibility invalidate projection")
        cache.invalidate()
        _ = projection("changed", calendars: ["calendar"])
        try check(cache.buildCount == 4, "snapshot replacement invalidates projection")
        let date = Date(timeIntervalSince1970: 0)
        let utc = CalendarDisplayFormatting.string(date, template: "HHmm", timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"))
        let shifted = CalendarDisplayFormatting.string(date, template: "HHmm", timeZone: TimeZone(secondsFromGMT: 10800)!, locale: Locale(identifier: "en_US_POSIX"))
        try check(utc == "00:00" && shifted == "03:00", "formatter cache isolates timezone and preserves 24-hour labels")
    }
}


extension InvariantTests {
    static func testEventDateAdjustment() throws {
        let zone = TimeZone(identifier: "Europe/Moscow")!
        let start = ISO8601.parse("2026-10-17T10:00:00+03:00")!
        let end = ISO8601.parse("2026-10-17T15:00:00+03:00")!
        let next = ISO8601.parse("2026-10-17T16:00:00+03:00")!
        let shifted = EventDateAdjustment.endAfterChangingStart(from: start, to: next, end: end, allDay: false, timeZone: zone)
        try check(shifted == ISO8601.parse("2026-10-17T21:00:00+03:00")!, "10–15 moved to 16 ends at 21")
        let nextDate = next.addingTimeInterval(86400)
        try check(EventDateAdjustment.endAfterChangingStart(from: start, to: nextDate, end: end, allDay: false, timeZone: zone) == nextDate.addingTimeInterval(18000), "changing start date retains five elapsed hours")
        try check(EventDateAdjustment.endAfterChangingStart(from: start, to: start.addingTimeInterval(3600), end: end, allDay: false, timeZone: zone) == end, "still-valid end is unchanged")
        try check(EventDateAdjustment.endAfterChangingStart(from: start, to: end, end: end, allDay: false, timeZone: zone) == end.addingTimeInterval(18000), "equal timed endpoints shift rather than create zero duration")
        let dst = TimeZone(identifier: "America/New_York")!
        let old = DateOnly(rawValue: "2026-03-01")!.startOfDay(in: dst)!
        let oldEnd = DateOnly(rawValue: "2026-03-03")!.startOfDay(in: dst)!
        let moved = DateOnly(rawValue: "2026-03-07")!.startOfDay(in: dst)!
        let result = EventDateAdjustment.endAfterChangingStart(from: old, to: moved, end: oldEnd, allDay: true, timeZone: dst)
        try check(DateOnly(date: result, timeZone: dst).description == "2026-03-09", "all-day duration uses calendar days across DST")
        try check(result.timeIntervalSince(moved) == 47 * 3600, "DST fixture distinguishes days from 24-hour arithmetic")
        try check(EventDateAdjustment.endAfterChangingStart(from: old, to: moved, end: old, allDay: true, timeZone: dst) == moved, "single-day event remains single-day")
        try check(EventDateAdjustment.endAfterChangingStart(from: old, to: oldEnd, end: oldEnd, allDay: true, timeZone: dst) == oldEnd, "inclusive same-day end remains valid")
    }
}
