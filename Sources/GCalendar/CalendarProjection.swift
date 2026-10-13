import Foundation

struct CalendarDayContent: Equatable, Identifiable {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [GoogleTask]
    let allDayEventCount: Int
    var id: Date { day }
}

// Each source collection is filtered once. Date spans are prepared once per
// event, then shared by the header, date-only area, grid and empty-state check.
struct CalendarWorkspaceProjection: Equatable {
    let days: [CalendarDayContent]
    let undatedTasks: [GoogleTask]
    let sharedDateOnlyHeight: Double

    init(range: DateRange, isDayView: Bool, events: [CalendarEvent], tasks: [GoogleTask],
         visibleCalendarIDs: Set<String>?, selectedTaskListID: String?, searchText: String) {
        let dates = isDayView ? [range.start] : CalendarDatePolicy.days(in: range)
        let dayValues = dates.map { DateOnly(date: $0, timeZone: range.timeZone) }
        let spans = events.compactMap { event -> (CalendarEvent, DateOnly, DateOnly)? in
            guard visibleCalendarIDs?.contains(event.calendarID) ?? true,
                  searchText.isEmpty || event.title.localizedCaseInsensitiveContains(searchText) else { return nil }
            if event.isAllDay, let start = event.start.dateOnly, let end = event.end.dateOnly {
                // Keep the API's exclusive end and the existing date-only rule.
                guard let last = end.adding(days: -1) else { return nil }
                return (event, start, last)
            }
            guard let start = event.start.instant, let end = event.end.instant else { return nil }
            return (event, DateOnly(date: start, timeZone: range.timeZone), DateOnly(date: end.addingTimeInterval(-1), timeZone: range.timeZone))
        }
        let filteredTasks = tasks.filter {
            !$0.deleted && (selectedTaskListID == nil || $0.taskListID == selectedTaskListID)
                && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText))
        }
        let tasksByDate = Dictionary(grouping: filteredTasks.filter { $0.due != nil }, by: { $0.due! })
        let contents = zip(dates, dayValues).map { date, value in
            let events = spans.compactMap { event, start, last in value >= start && value <= last ? event : nil }
            return CalendarDayContent(day: date, events: events, tasks: tasksByDate[value] ?? [], allDayEventCount: events.filter(\.isAllDay).count)
        }
        days = contents
        undatedTasks = filteredTasks.filter { $0.due == nil }.sorted { $0.id < $1.id }
        sharedDateOnlyHeight = CalendarGridLayout.dateOnlyHeight(maximumItemCount: contents.map { $0.allDayEventCount + $0.tasks.count }.max() ?? 0)
    }

    func contentState(rangeCovered: Bool, hasSearch: Bool) -> CalendarContentState {
        CalendarContentAvailability.state(events: days.flatMap(\.events), tasks: days.flatMap(\.tasks) + undatedTasks,
                                          rangeCovered: rangeCovered, hasSearch: hasSearch)
    }
}
