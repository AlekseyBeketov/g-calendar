import SwiftUI

struct CalendarTimeGridDay: View {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [GoogleTask]
    let calendars: [CalendarInfo]
    let timeZone: TimeZone
    let onEdit: (CalendarEvent) -> Void
    let onToggleTask: (GoogleTask) -> Void

    private let hourGutter: CGFloat = 44
    private let pointsPerMinute: CGFloat = 0.8
    private let minimumEventHeight: CGFloat = 18

    private var calendarByID: [String: CalendarInfo] {
        Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var allDayEvents: [CalendarEvent] {
        CalendarTimeGridLayout.allDayEvents(events, on: day, timeZone: timeZone)
    }

    private var timedEvents: [CalendarEvent] {
        events.filter { !$0.isAllDay }
    }

    private var placements: [CalendarTimedPlacement] {
        CalendarTimeGridLayout.timedPlacements(timedEvents, on: day, timeZone: timeZone)
    }

    private var dayInterval: CalendarDayInterval? {
        CalendarTimeGridLayout.dayInterval(containing: day, timeZone: timeZone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedDay(day, template: "EEE")).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(AppTheme.textSecondary)
                Text(formattedDay(day, template: "d")).font(.title3.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            dateOnlyArea
            Rectangle().fill(AppTheme.outline.opacity(0.45)).frame(height: 1)
            timeGrid
        }
        .frame(width: 220, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outline.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(formattedDay(day, template: "EEEE, d MMMM y"))
    }

    private var dateOnlyArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !allDayEvents.isEmpty {
                Label("Весь день", systemImage: "sun.max.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                ForEach(allDayEvents, id: \.identity) { event in
                    eventButton(event, compact: true)
                }
            }
            if !tasks.isEmpty {
                Label("Задачи · срок без времени", systemImage: "checklist")
                    .font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.task)
                ForEach(tasks) { task in
                    Button { onToggleTask(task) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? AppTheme.textSecondary : AppTheme.task)
                            Text(task.title).font(.caption).foregroundStyle(AppTheme.textPrimary).lineLimit(2).strikethrough(task.completed)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Задача: \(task.title), срок \(task.due?.description ?? "без срока"), \(task.completed ? "выполнена" : "не выполнена")")
                }
            }
            if allDayEvents.isEmpty && tasks.isEmpty {
                Text("Нет событий на весь день или задач с датой")
                    .font(.caption2).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(AppTheme.canvas.opacity(0.72))
    }

    private func eventButton(_ event: CalendarEvent, compact: Bool) -> some View {
        let calendar = calendarByID[event.calendarID]
        let writable = calendar?.isWritable == true && !event.recurring
        return Button { onEdit(event) } label: {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: calendar?.colorHex) ?? AppTheme.event)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.textPrimary).lineLimit(compact ? 2 : 1)
                    if !compact, let calendar {
                        Text(calendar.title).font(.caption2).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !writable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(AppTheme.textSecondary) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, compact ? 3 : 2)
            .frame(maxWidth: .infinity, minHeight: compact ? 26 : 18, alignment: .leading)
            .background((Color(hex: calendar?.colorHex) ?? AppTheme.event).opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!writable)
        .accessibilityLabel("Событие: \(event.title), \(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: calendar?.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? timeZone)), календарь \(calendar?.title ?? "неизвестен")\(event.recurring ? ", повторяется" : "")\(writable ? ", редактировать" : ", только просмотр")")
        .help(event.recurring ? "Повторяющиеся события доступны только для просмотра" : (calendar?.isWritable == true ? "Редактировать событие" : "Календарь только для просмотра"))
    }

    private var timeGrid: some View {
        Group {
            if let dayInterval {
                let eventsByIdentity = Dictionary(timedEvents.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
                let height = CGFloat(dayInterval.durationMinutes) * pointsPerMinute
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(hourMarks(for: dayInterval)) { mark in
                            Rectangle()
                                .fill(AppTheme.outline.opacity(0.30))
                                .frame(height: 1)
                                .offset(x: hourGutter, y: CGFloat(mark.offsetMinutes) * pointsPerMinute)
                            Text(mark.label)
                                .font(.system(.caption2, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: hourGutter - 5, alignment: .trailing)
                                .offset(y: CGFloat(mark.offsetMinutes) * pointsPerMinute - 7)
                                .accessibilityHidden(true)
                        }
                        ForEach(placements) { placement in
                            if let event = eventsByIdentity[placement.identity] {
                                let availableWidth = max(0, geometry.size.width - hourGutter - 4)
                                let laneWidth = availableWidth / CGFloat(max(placement.laneCount, 1))
                                let calendar = calendarByID[event.calendarID]
                                let color = Color(hex: calendar?.colorHex) ?? AppTheme.event
                                eventButton(event, compact: false)
                                    .frame(width: max(8, laneWidth - 2),
                                           height: max(minimumEventHeight, CGFloat(placement.durationMinutes) * pointsPerMinute),
                                           alignment: .topLeading)
                                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 2)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .offset(x: hourGutter + CGFloat(placement.laneIndex) * laneWidth,
                                            y: CGFloat(placement.startOffsetMinutes) * pointsPerMinute)
                                    .zIndex(Double(placement.laneIndex + 1))
                                    .accessibilityValue("\(Int(placement.startOffsetMinutes)) минут от начала дня, длительность \(Int(placement.durationMinutes)) минут, полоса \(placement.laneIndex + 1) из \(placement.laneCount)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: height)
                .padding(.horizontal, 3)
            }
        }
        .padding(.bottom, 8)
    }

    private func hourMarks(for interval: CalendarDayInterval) -> [CalendarHourMark] {
        var dates: [Date] = []
        var current = interval.start
        while current < interval.endExclusive {
            dates.append(current)
            current = current.addingTimeInterval(60 * 60)
        }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        var counts: [String: Int] = [:]
        for date in dates { counts[formatter.string(from: date), default: 0] += 1 }
        return dates.enumerated().map { index, date in
            let base = formatter.string(from: date)
            let label = counts[base, default: 0] > 1 ? "\(base) \(timeZone.abbreviation(for: date) ?? "")" : base
            return CalendarHourMark(id: index,
                                    offsetMinutes: date.timeIntervalSince(interval.start) / 60,
                                    label: label)
        }
    }

    private func formattedDay(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

}

struct CalendarUndatedTaskRegion: View {
    let tasks: [GoogleTask]
    let onToggleTask: (GoogleTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Без срока", systemImage: "tray")
                .font(.headline)
                .foregroundStyle(AppTheme.task)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(tasks) { task in
                    Button { onToggleTask(task) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? AppTheme.textSecondary : AppTheme.task)
                            Text(task.title)
                                .font(.callout)
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)
                                .strikethrough(task.completed)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Задача: \(task.title), без срока, \(task.completed ? "выполнена" : "не выполнена")")
                    .accessibilityHint("Изменить состояние выполнения")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Задачи без срока, \(tasks.count)")
    }
}

private struct CalendarHourMark: Identifiable {
    let id: Int
    let offsetMinutes: Double
    let label: String
}
