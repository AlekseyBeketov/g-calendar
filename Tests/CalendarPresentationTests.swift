import Foundation

extension InvariantTests {
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
