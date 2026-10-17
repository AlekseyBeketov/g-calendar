import Foundation

enum EventDateAdjustment {
    static func endAfterChangingStart(from oldStart: Date, to newStart: Date, end: Date,
                                      allDay: Bool, timeZone: TimeZone) -> Date {
        if allDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let oldDay = calendar.startOfDay(for: oldStart)
            let newDay = calendar.startOfDay(for: newStart)
            let endDay = calendar.startOfDay(for: end)
            // The editor displays the last included day; same-day is valid.
            guard newDay > endDay else { return end }
            let days = max(0, calendar.dateComponents([.day], from: oldDay, to: endDay).day ?? 0)
            return calendar.date(byAdding: .day, value: days, to: newDay) ?? newDay
        }
        guard newStart >= end else { return end }
        let duration = end.timeIntervalSince(oldStart)
        return newStart.addingTimeInterval(duration > 0 ? duration : 3600)
    }
}
