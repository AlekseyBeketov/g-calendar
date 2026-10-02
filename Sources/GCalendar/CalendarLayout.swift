import Foundation

struct CalendarDayInterval: Equatable {
    let start: Date
    let endExclusive: Date

    var durationMinutes: Double { endExclusive.timeIntervalSince(start) / 60 }
}

enum TaskWorkspaceLayout {
    static let idealSidebarWidth = 245.0
    static let topScrollAnchorID = "task-workspace-scroll-top"

    static func detailWidth(windowWidth: Double, sidebarWidth: Double = idealSidebarWidth) -> Double {
        max(0, windowWidth - sidebarWidth)
    }

    static func usesSingleColumn(availableWidth: Double, threshold: Double = 1_020) -> Bool {
        availableWidth < threshold
    }
}

enum CalendarGridLayout {
    static let minimumColumnWidth = 220.0
    static let minimumWeekColumnWidth = 160.0
    static let dateOnlyRegionHeight = 116.0

    static func columnWidth(isDayView: Bool,
                            availableWidth: Double,
                            visibleDayCount: Int = 7,
                            interColumnSpacing: Double = 10) -> Double {
        if isDayView { return max(minimumColumnWidth, availableWidth) }
        let dayCount = max(1, visibleDayCount)
        let totalSpacing = interColumnSpacing * Double(max(0, dayCount - 1))
        return max(minimumWeekColumnWidth, (availableWidth - totalSpacing) / Double(dayCount))
    }
}

enum CalendarEventAccessibilityText {
    static func timeDescription(for event: CalendarEvent, fallbackTimeZone: TimeZone) -> String {
        guard !event.isAllDay, let start = event.start.instant, let end = event.end.instant else { return "весь день" }
        let zone = event.start.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? fallbackTimeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}

struct CalendarTimedPlacement: Equatable, Identifiable {
    let identity: CalendarEventIdentity
    let startOffsetMinutes: Double
    let durationMinutes: Double
    let laneIndex: Int
    let laneCount: Int

    var id: CalendarEventIdentity { identity }
}

private struct TimedInterval {
    let identity: CalendarEventIdentity
    let start: Date
    let end: Date
    let laneEnd: Date
}

enum CalendarTimeGridLayout {
    static func dayInterval(containing date: Date, timeZone: TimeZone) -> CalendarDayInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start), start < end else { return nil }
        return CalendarDayInterval(start: start, endExclusive: end)
    }

    static func allDayEvents(_ events: [CalendarEvent], on date: Date, timeZone: TimeZone) -> [CalendarEvent] {
        let day = DateOnly(date: date, timeZone: timeZone)
        return events.filter { event in
            guard event.isAllDay, let start = event.start.dateOnly, let endExclusive = event.end.dateOnly else { return false }
            return day >= start && day < endExclusive
        }.sorted {
            if $0.start.dateOnly != $1.start.dateOnly { return ($0.start.dateOnly ?? DateOnly(year: 1970, month: 1, day: 1)) < ($1.start.dateOnly ?? DateOnly(year: 1970, month: 1, day: 1)) }
            return $0.identity.stableKey < $1.identity.stableKey
        }
    }

    static func dateOnlyTasks(_ tasks: [GoogleTask], on date: Date, timeZone: TimeZone) -> [GoogleTask] {
        let day = DateOnly(date: date, timeZone: timeZone)
        return tasks.filter { !$0.deleted && $0.due == day }.sorted { $0.id < $1.id }
    }

    static func undatedTasks(_ tasks: [GoogleTask], selectedTaskListID: String?, searchText: String) -> [GoogleTask] {
        tasks.filter { task in
            !task.deleted && task.due == nil && (selectedTaskListID == nil || task.taskListID == selectedTaskListID) &&
            (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.id < $1.id }
    }

    static func timedPlacements(_ events: [CalendarEvent], on date: Date, timeZone: TimeZone) -> [CalendarTimedPlacement] {
        guard let day = dayInterval(containing: date, timeZone: timeZone) else { return [] }
        let intervals = events.compactMap { event -> TimedInterval? in
            guard !event.isAllDay, let start = event.start.instant, let end = event.end.instant, start < end else { return nil }
            let clippedStart = max(start, day.start)
            let clippedEnd = min(end, day.endExclusive)
            guard clippedStart < clippedEnd else { return nil }
            let minimumLaneEnd = clippedStart.addingTimeInterval(22.5 * 60)
            return TimedInterval(identity: event.identity, start: clippedStart, end: clippedEnd,
                                 laneEnd: min(day.endExclusive, max(clippedEnd, minimumLaneEnd)))
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.identity.stableKey < $1.identity.stableKey
        }

        var clusters: [[TimedInterval]] = []
        var current: [TimedInterval] = []
        var clusterEnd: Date?
        for interval in intervals {
            if let end = clusterEnd, interval.start >= end {
                clusters.append(current)
                current = []
                clusterEnd = nil
            }
            current.append(interval)
            clusterEnd = max(clusterEnd ?? interval.laneEnd, interval.laneEnd)
        }
        if !current.isEmpty { clusters.append(current) }

        var result: [CalendarTimedPlacement] = []
        for cluster in clusters {
            var laneEnds: [Date] = []
            var assignments: [(TimedInterval, Int)] = []
            for interval in cluster {
                if let lane = laneEnds.firstIndex(where: { $0 <= interval.start }) {
                    laneEnds[lane] = interval.laneEnd
                    assignments.append((interval, lane))
                } else {
                    let lane = laneEnds.count
                    laneEnds.append(interval.laneEnd)
                    assignments.append((interval, lane))
                }
            }
            let laneCount = max(1, laneEnds.count)
            result.append(contentsOf: assignments.map { interval, lane in
                CalendarTimedPlacement(identity: interval.identity,
                                       startOffsetMinutes: interval.start.timeIntervalSince(day.start) / 60,
                                       durationMinutes: interval.end.timeIntervalSince(interval.start) / 60,
                                       laneIndex: lane,
                                       laneCount: laneCount)
            })
        }
        return result.sorted {
            if $0.startOffsetMinutes != $1.startOffsetMinutes { return $0.startOffsetMinutes < $1.startOffsetMinutes }
            return $0.identity.stableKey < $1.identity.stableKey
        }
    }
}

extension CalendarEvent {
    var identity: CalendarEventIdentity { CalendarEventIdentity(calendarID: calendarID, eventID: id) }
}

struct CalendarEventIdentity: Codable, Hashable {
    let calendarID: String
    let eventID: String

    var stableKey: String { "\(calendarID.utf8.count):\(calendarID)\(eventID.utf8.count):\(eventID)" }
}
