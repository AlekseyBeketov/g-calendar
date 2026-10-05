import SwiftUI

struct CalendarTimeGridDay: View {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [GoogleTask]
    let calendars: [CalendarInfo]
    let timeZone: TimeZone
    let columnWidth: CGFloat
    var dateOnlyHeight: CGFloat = CGFloat(CalendarGridLayout.dateOnlyRegionHeight)
    let onEdit: (CalendarEvent) -> Void
    let onToggleTask: (GoogleTask) -> Void

    private let pointsPerMinute = CGFloat(CalendarGridLayout.pointsPerMinute)
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
        timeGrid
        .frame(width: columnWidth, alignment: .topLeading)
        .background(AppTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(formattedDay(day, template: "EEEE, d MMMM y"))
    }

    var dayHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(formattedDay(day, template: "EEE")).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(AppTheme.textSecondary)
            Text(formattedDay(day, template: "d")).font(.title3.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(width: columnWidth, height: CGFloat(CalendarGridLayout.headerHeight), alignment: .center)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outline.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(formattedDay(day, template: "EEEE, d MMMM y"))
    }

    var dateOnlyArea: some View {
        ScrollView(.vertical) {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity)
        .frame(height: dateOnlyHeight, alignment: .topLeading)
        .frame(width: columnWidth)
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
        .accessibilityLabel("Событие: \(event.title), \(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: calendar?.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? timeZone)), календарь \(calendar?.title ?? "неизвестен")\(event.recurring ? ", повторяется" : "")\(writable ? ", редактировать" : ", только просмотр")")
        .help(writable ? "Редактировать событие" : "Открыть событие для просмотра")
    }

    private var timeGrid: some View {
        Group {
            if let dayInterval {
                let eventsByIdentity = Dictionary(timedEvents.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
                let height = CGFloat(dayInterval.durationMinutes) * pointsPerMinute
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(CalendarTimeGridLayout.hourMarks(for: dayInterval, timeZone: timeZone)) { mark in
                            Rectangle()
                                .fill(AppTheme.outline.opacity(0.30))
                                .frame(height: 1)
                                .offset(y: CGFloat(mark.offsetMinutes) * pointsPerMinute)
                        }
                        ForEach(placements) { placement in
                            if let event = eventsByIdentity[placement.identity] {
                                let availableWidth = max(0, geometry.size.width - 4)
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
                                    .offset(x: CGFloat(placement.laneIndex) * laneWidth,
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


    private func formattedDay(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

}

struct CalendarHourAxis: View {
    let day: Date
    let timeZone: TimeZone
    let height: CGFloat

    var body: some View {
        Group {
            if let interval = CalendarTimeGridLayout.dayInterval(containing: day, timeZone: timeZone) {
                let marks = CalendarTimeGridLayout.hourMarks(for: interval, timeZone: timeZone)
                VStack(spacing: 0) {
                    ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                        let nextOffset = index + 1 < marks.count ? marks[index + 1].offsetMinutes : interval.durationMinutes
                        Text(mark.label)
                            .font(.system(.caption2).monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: CGFloat(CalendarGridLayout.timeAxisWidth) - 5,
                                   height: CGFloat(nextOffset - mark.offsetMinutes) * CGFloat(CalendarGridLayout.pointsPerMinute),
                                   alignment: .topTrailing)
                            .id(mark.localHour == 8 ? "calendar-hour-8" : "calendar-hour-\(mark.id)")
                            .offset(y: index == 0 ? 0 : -7)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: CGFloat(CalendarGridLayout.timeAxisWidth), height: height, alignment: .topLeading)
            }
        }
    }
}

struct CalendarUndatedTaskRegion: View {
    let tasks: [GoogleTask]
    @Binding var isCollapsed: Bool
    let onToggleTask: (GoogleTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { isCollapsed.toggle() } label: {
                HStack {
                    Label("Без срока", systemImage: "tray")
                    Spacer()
                    Text("\(tasks.count)").monospacedDigit()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                }
                .font(.headline)
                .foregroundStyle(AppTheme.task)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar-undated-task-toggle")
            .accessibilityLabel("Задачи без срока, \(tasks.count)")
            .accessibilityValue(isCollapsed ? "Свёрнуто" : "Развёрнуто")
            .accessibilityHint(isCollapsed ? "Показать задачи" : "Скрыть задачи")
            if !isCollapsed {
                ScrollView {
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
                .frame(maxHeight: 160)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Задачи без срока, \(tasks.count)")
    }
}
