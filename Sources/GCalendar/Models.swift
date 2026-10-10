import Foundation

struct DateOnly: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard components.calendar?.date(from: components) != nil,
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!
        let verified = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        guard verified.year == year, verified.month == month, verified.day == day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = DateOnly(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date-only value")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func adding(days: Int, calendar inputCalendar: Calendar = Calendar(identifier: .gregorian)) -> DateOnly? {
        var calendar = inputCalendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let base = calendar.date(from: components), let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        return DateOnly(date: shifted, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    func startOfDay(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}

enum CalendarNavigation {
    static func sorted(_ calendars: [CalendarInfo]) -> [CalendarInfo] {
        calendars.sorted { lhs, rhs in
            if lhs.isWritable != rhs.isWritable { return lhs.isWritable }
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    static func selectedID(_ current: String?, calendars: [CalendarInfo]) -> String? {
        if let current, calendars.contains(where: { $0.id == current }) { return current }
        return sorted(calendars).first?.id
    }
}

struct CalendarInfo: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var accessRole: String
    var timeZoneID: String?
    var colorHex: String?

    var isWritable: Bool { accessRole == "owner" || accessRole == "writer" }
}

struct EventTime: Codable, Equatable {
    let rawValue: String
    let instant: Date?
    let dateOnly: DateOnly?
    let timeZoneID: String?

    var isAllDay: Bool { dateOnly != nil }

    static func decode(_ dictionary: [String: Any]) throws -> EventTime {
        if let raw = dictionary["date"] as? String, let date = DateOnly(rawValue: raw) {
            return EventTime(rawValue: raw, instant: nil, dateOnly: date, timeZoneID: dictionary["timeZone"] as? String)
        }
        if let raw = dictionary["dateTime"] as? String, let instant = ISO8601.parse(raw) {
            return EventTime(rawValue: raw, instant: instant, dateOnly: nil, timeZoneID: dictionary["timeZone"] as? String)
        }
        throw GWSFailure.invalidResponse("event_time")
    }
}

struct CalendarEvent: Codable, Equatable, Identifiable {
    let id: String
    let calendarID: String
    var title: String
    var start: EventTime
    var end: EventTime
    var recurring: Bool
    var status: String?

    static func decode(_ dictionary: [String: Any], calendarID: String) throws -> CalendarEvent {
        guard let id = dictionary["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let startObject = dictionary["start"] as? [String: Any],
              let endObject = dictionary["end"] as? [String: Any] else {
            throw GWSFailure.invalidResponse("event_shape")
        }
        let title: String
        if let summary = dictionary["summary"] as? String, !summary.isEmpty { title = summary }
        else { title = "Без названия" }
        let recurrence = dictionary["recurrence"] as? [String]
        let recurring = dictionary["recurringEventId"] != nil || !(recurrence?.isEmpty ?? true)
        return CalendarEvent(id: id,
                             calendarID: calendarID,
                             title: title,
                             start: try EventTime.decode(startObject),
                             end: try EventTime.decode(endObject),
                             recurring: recurring,
                             status: dictionary["status"] as? String)
    }

    var isAllDay: Bool { start.isAllDay && end.isAllDay }

    /// Google Calendar all-day end is exclusive; this is the last day shown to a person.
    var visibleAllDayEnd: DateOnly? {
        guard isAllDay, let exclusive = end.dateOnly else { return nil }
        return exclusive.adding(days: -1)
    }
}

struct TaskList: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var updated: Date?

    static func decode(_ dictionary: [String: Any]) throws -> TaskList {
        guard let id = dictionary["id"] as? String, let title = dictionary["title"] as? String else {
            throw GWSFailure.invalidResponse("task_list_shape")
        }
        return TaskList(id: id, title: title, updated: (dictionary["updated"] as? String).flatMap(ISO8601.parse))
    }
}

struct GoogleTask: Codable, Equatable, Identifiable {
    let id: String
    let taskListID: String
    var title: String
    var notes: String?
    var due: DateOnly?
    var completed: Bool
    var deleted: Bool
    var updated: Date?

    static func decode(_ dictionary: [String: Any], taskListID: String) throws -> GoogleTask {
        guard let id = dictionary["id"] as? String, let title = dictionary["title"] as? String else {
            throw GWSFailure.invalidResponse("task_shape")
        }
        var due: DateOnly?
        if let dueRaw = dictionary["due"] as? String {
            // The Tasks API only guarantees a date. Deliberately discard any API time/offset.
            let day = String(dueRaw.prefix(10))
            guard let parsed = DateOnly(rawValue: day) else { throw GWSFailure.invalidResponse("task_due_date") }
            due = parsed
        }
        let status = dictionary["status"] as? String
        return GoogleTask(id: id,
                          taskListID: taskListID,
                          title: title,
                          notes: dictionary["notes"] as? String,
                          due: due,
                          completed: status == "completed",
                          deleted: dictionary["deleted"] as? Bool ?? false,
                          updated: (dictionary["updated"] as? String).flatMap(ISO8601.parse))
    }
}

struct CalendarRangeCoverage: Codable, Equatable {
    let start: Date
    let endExclusive: Date
    let timeZoneID: String

    init(range: DateRange) {
        start = range.start
        endExclusive = range.endExclusive
        timeZoneID = range.timeZone.identifier
    }

    func covers(_ range: DateRange) -> Bool {
        timeZoneID == range.timeZone.identifier && start <= range.start && endExclusive >= range.endExclusive
    }
}

struct WorkspaceSnapshot: Codable, Equatable {
    var calendars: [CalendarInfo]
    var events: [CalendarEvent]
    var taskLists: [TaskList]
    var tasks: [GoogleTask]
    var fetchedAt: Date
    var calendarCoverage: CalendarRangeCoverage? = nil
    var calendarFetchedAt: Date? = nil
    var tasksFetchedAt: Date? = nil

    static let empty = WorkspaceSnapshot(calendars: [], events: [], taskLists: [], tasks: [], fetchedAt: .distantPast)
}

enum CalendarContentState: Equatable {
    case hasContent
    case emptyRange
    case unknownRange
    case noResults
}

enum CalendarContentAvailability {
    static func isEmpty(events: [CalendarEvent], tasks: [GoogleTask]) -> Bool {
        events.isEmpty && tasks.isEmpty
    }

    static func state(events: [CalendarEvent], tasks: [GoogleTask], rangeCovered: Bool, hasSearch: Bool) -> CalendarContentState {
        guard isEmpty(events: events, tasks: tasks) else { return .hasContent }
        guard rangeCovered else { return .unknownRange }
        if hasSearch { return .noResults }
        return .emptyRange
    }
}

struct DateRange: Equatable {
    let start: Date
    let endExclusive: Date
    let timeZone: TimeZone

    init(start: Date, endExclusive: Date, timeZone: TimeZone = .current) throws {
        guard start < endExclusive else { throw GWSFailure.invalidInput("date_range") }
        self.start = start
        self.endExclusive = endExclusive
        self.timeZone = timeZone
    }

    var startISO8601: String { ISO8601.format(start) }
    var endISO8601: String { ISO8601.format(endExclusive) }
}

enum ISO8601 {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
