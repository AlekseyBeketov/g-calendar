import Foundation

enum CalendarPresentationMode: String, CaseIterable {
    case week = "Неделя", day = "День", month = "Месяц"

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

enum CalendarWeekStart: String, CaseIterable, Identifiable {
    case monday, sunday, system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .monday: return "Понедельник"
        case .sunday: return "Воскресенье"
        case .system: return "По настройкам системы"
        }
    }

    func firstWeekday(systemCalendar: Calendar = .autoupdatingCurrent) -> Int {
        switch self {
        case .monday: return 2
        case .sunday: return 1
        case .system: return systemCalendar.firstWeekday
        }
    }

    static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: "calendarWeekStart").flatMap(Self.init(rawValue:)) ?? .monday
    }

    func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: "calendarWeekStart") }
}

enum CalendarDatePolicy {
    static func range(containing date: Date, mode: CalendarPresentationMode, timeZone: TimeZone,
                      firstWeekday: Int = 2) -> DateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        let interval = calendar.dateInterval(of: mode.component, for: date)!
        var start = interval.start, end = interval.end
        if mode == .month {
            let leading = (calendar.component(.weekday, from: start) - firstWeekday + 7) % 7
            start = calendar.date(byAdding: .day, value: -leading, to: start)!
            let trailing = (firstWeekday - calendar.component(.weekday, from: end) + 7) % 7
            end = calendar.date(byAdding: .day, value: trailing, to: end)!
        }
        return try! DateRange(start: start, endExclusive: end, timeZone: timeZone)
    }

    static func moving(_ date: Date, by amount: Int, mode: CalendarPresentationMode, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let anchor = mode == .month ? calendar.dateInterval(of: .month, for: date)?.start ?? date : date
        return calendar.date(byAdding: mode.component, value: amount, to: anchor)
    }

    static func days(in range: DateRange) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = range.timeZone
        var days: [Date] = [], date = range.start
        while date < range.endExclusive {
            days.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return days
    }
}
