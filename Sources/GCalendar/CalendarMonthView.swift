import SwiftUI

struct CalendarMonthView: View {
    let projection: CalendarWorkspaceProjection
    let activeDate: Date
    let timeZone: TimeZone
    let calendars: [CalendarInfo]
    let mutationsBlocked: Bool
    let onOpenDay: (Date) -> Void
    let onEdit: (CalendarEvent) -> Void
    let onToggleTask: (GoogleTask) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 100), spacing: 6), count: 7)
    private let visibleItemLimit = 3

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 6) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(projection.days.prefix(7))) { content in
                            Text(formatted(content.day, template: "EEE"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(projection.days) { content in
                            dayCell(content, height: max(150, (geometry.size.height - 32) / CGFloat(max(1, projection.days.count / 7)) - 6))
                        }
                    }
                }
                .frame(width: max(geometry.size.width, 760), alignment: .topLeading)
            }
        }
        .accessibilityIdentifier("calendar-month-grid")
    }

    private func dayCell(_ content: CalendarDayContent, height: CGFloat) -> some View {
        let events = content.events.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.start.instant != $1.start.instant { return ($0.start.instant ?? .distantPast) < ($1.start.instant ?? .distantPast) }
            return $0.identity.stableKey < $1.identity.stableKey
        }
        let tasks = content.tasks.sorted { $0.id < $1.id }
        let visibleEvents = Array(events.prefix(visibleItemLimit))
        let visibleTasks = Array(tasks.prefix(max(0, visibleItemLimit - visibleEvents.count)))
        let overflow = events.count + tasks.count - visibleEvents.count - visibleTasks.count
        let day = DateOnly(date: content.day, timeZone: timeZone)
        let active = DateOnly(date: activeDate, timeZone: timeZone)
        let inMonth = day.month == active.month && day.year == active.year
        return VStack(alignment: .leading, spacing: 4) {
            Button { onOpenDay(content.day) } label: {
                HStack {
                    Text(formatted(content.day, template: "d")).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    if !inMonth { Text(formatted(content.day, template: "MMM")).font(.caption2) }
                }
                .foregroundStyle(inMonth ? AppTheme.textPrimary : AppTheme.textSecondary)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.pointingHandCursor()
            .buttonStyle(.plain)
            .accessibilityLabel("Открыть день: \(formatted(content.day, template: "EEEE, d MMMM y"))")
            ForEach(visibleEvents, id: \.identity) { event in
                eventButton(event)
            }
            ForEach(visibleTasks) { task in
                Button { onToggleTask(task) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(AppTheme.task)
                        Text(task.title).lineLimit(1).strikethrough(task.completed)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.pointingHandCursor()
                .buttonStyle(.plain)
                .disabled(mutationsBlocked)
                .accessibilityLabel("Задача: \(task.title), \(task.completed ? "выполнена" : "не выполнена")")
                .help(task.title)
            }
            if overflow > 0 {
                Button { onOpenDay(content.day) } label: {
                    Text("ещё \(overflow)").font(.caption).foregroundStyle(AppTheme.accent)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.pointingHandCursor()
                .buttonStyle(.plain)
                .accessibilityLabel("Ещё \(overflow) записей, открыть \(formatted(content.day, template: "d MMMM"))")
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .topLeading)
        .background(inMonth ? AppTheme.surface : AppTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.outline.opacity(0.3), lineWidth: 1)
            .allowsHitTesting(false).accessibilityHidden(true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-month-day-\(day)")
    }

    private func eventButton(_ event: CalendarEvent) -> some View {
        let calendar = calendars.first { $0.id == event.calendarID }
        return Button { onEdit(event) } label: {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: calendar?.colorHex) ?? AppTheme.event)
                    .frame(width: 3, height: 14)
                if let start = event.start.instant, !event.isAllDay {
                    Text(formatted(start, template: "jm")).foregroundStyle(AppTheme.textSecondary)
                }
                Text(event.title).foregroundStyle(AppTheme.textPrimary).lineLimit(1)
                if calendar?.isWritable != true || event.recurring {
                    Image(systemName: "lock.fill").foregroundStyle(AppTheme.textSecondary)
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.pointingHandCursor()
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: timeZone))")
        .help("\(event.title) · \(CalendarEventAccessibilityText.timeDescription(for: event, fallbackTimeZone: timeZone))")
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
