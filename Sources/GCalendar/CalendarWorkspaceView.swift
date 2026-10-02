import SwiftUI

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(periodTitle).font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(model.calendarMode.rawValue).font(.caption).foregroundStyle(.secondary)
                        if let calendar = model.selectedCalendar {
                            Text(calendar.isWritable ? calendar.title : "\(calendar.title) · Только просмотр")
                                .font(.caption).foregroundColor(calendar.isWritable ? .secondary : .orange).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Picker("Вид календаря", selection: $model.calendarMode) {
                    ForEach(WorkspaceViewModel.CalendarMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Button { local.showingEventEditor = true; local.selectedEvent = nil } label: { Label("Событие", systemImage: "plus") }
                    .disabled(model.selectedCalendar?.isWritable != true || model.mutationInFlight)
                    .help(model.selectedCalendar?.isWritable == true ? "Создать событие" : "Выберите календарь с правом записи")
            }
            .padding(.horizontal, 18)

            if model.snapshot.calendars.isEmpty {
                WorkspaceEmptyState(title: "Календари не загружены", symbol: "calendar", description: "Проверьте путь к gws и выполните синхронизацию.") { }
            } else if calendarContentState != .hasContent {
                WorkspaceEmptyState(title: calendarEmptyStateTitle,
                                    symbol: "calendar.badge.clock",
                                    description: calendarEmptyStateDescription,
                                    actionTitle: calendarEmptyStateAction) {
                    if model.searchText.isEmpty { model.refresh() }
                    else { model.searchText = "" }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.calendarRangeIsCovered {
                        Label("События для этого диапазона не подтверждены сохранённым снимком.", systemImage: "clock.badge.questionmark")
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 18)
                    }
                    if !model.undatedTasks.isEmpty {
                        CalendarUndatedTaskRegion(tasks: model.undatedTasks, onToggleTask: toggleTask)
                            .padding(.horizontal, 18)
                    }
                    GeometryReader { geometry in
                        let columnWidth = CGFloat(CalendarGridLayout.columnWidth(
                            isDayView: model.calendarMode == .day,
                            availableWidth: Double(geometry.size.width - 36),
                            visibleDayCount: visibleDays.count
                        ))
                        ScrollView(.vertical) {
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(visibleDays, id: \.self) { day in
                                        CalendarTimeGridDay(day: day,
                                                          events: model.events(on: day),
                                                          tasks: model.tasks(on: day),
                                                          calendars: model.snapshot.calendars,
                                                          timeZone: model.selectedTimeZone,
                                                          columnWidth: columnWidth,
                                                          onEdit: { event in local.selectedEvent = event; local.showingEventEditor = true },
                                                          onToggleTask: toggleTask)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.bottom, 14)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Spacer(minLength: 0)
            Text("Повторяющиеся события доступны только для просмотра; участники и приглашения не поддерживаются.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .sheet(isPresented: $local.showingEventEditor, onDismiss: { local.selectedEvent = nil }) {
            EventEditorView(event: local.selectedEvent, calendar: model.selectedCalendar)
                .environmentObject(model)
        }
        .onChange(of: model.calendarMode) { _ in model.refresh() }
        .onChange(of: model.newItemRequestID) { _ in
            guard model.section == .calendar, model.selectedCalendar?.isWritable == true else { return }
            local.selectedEvent = nil
            local.showingEventEditor = true
        }
        .accessibilityIdentifier("calendar-workspace")
    }

    private var visibleDays: [Date] {
        let range = model.currentRange()
        if model.calendarMode == .day { return [range.start] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.selectedTimeZone
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
    }

    private var calendarContentState: CalendarContentState {
        CalendarContentAvailability.state(events: model.eventsInVisibleRange,
                                         tasks: visibleDays.flatMap(model.tasks(on:)) + model.undatedTasks,
                                         rangeCovered: model.calendarRangeIsCovered,
                                         hasSearch: !model.searchText.isEmpty)
    }

    private var calendarEmptyStateTitle: String {
        switch calendarContentState {
        case .hasContent: return ""
        case .emptyRange: return "Событий и задач нет"
        case .unknownRange: return "Диапазон ещё не загружен"
        case .noResults: return "Ничего не найдено"
        }
    }

    private var calendarEmptyStateDescription: String {
        switch calendarContentState {
        case .hasContent: return ""
        case .emptyRange: return "На этот период нет событий и задач с датой."
        case .unknownRange: return "Кэш не подтверждает данные для выбранных дат. Синхронизируйте диапазон, чтобы не принять неполные данные за пустой календарь."
        case .noResults: return "Измените запрос или очистите поиск."
        }
    }

    private var calendarEmptyStateAction: String? {
        switch calendarContentState {
        case .hasContent, .emptyRange: return nil
        case .unknownRange: return "Синхронизировать"
        case .noResults: return "Очистить поиск"
        }
    }

    private var periodTitle: String {
        let range = model.currentRange()
        if model.calendarMode == .day { return formattedDate(range.start, template: "EEEE, d MMMM y") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.selectedTimeZone
        let end = calendar.date(byAdding: .day, value: -1, to: range.endExclusive) ?? range.endExclusive
        return "\(formattedDate(range.start, template: "d MMM")) – \(formattedDate(end, template: "d MMM"))"
    }

    private func formattedDate(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = model.selectedTimeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func toggleTask(_ task: GoogleTask) {
        do {
            let factory = try model.commandFactory()
            let invocation = try factory.taskPatch(task: task, title: task.title, notes: task.notes, due: task.due,
                                                   completed: !task.completed, authorization: .userCompletionToggle)
            model.performMutation(invocation)
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить задачу." }
    }
}

private struct CalendarDayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [GoogleTask]
    let timeZone: TimeZone
    let canWrite: Bool
    let onEdit: (CalendarEvent) -> Void
    let onToggleTask: (GoogleTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day())).font(.title2.weight(.medium))
            }
            .padding(.bottom, 2)
            if events.isEmpty && tasks.isEmpty {
                Text("Нет записей").font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
            }
            ForEach(events) { event in
                let writable = canWrite && !event.recurring
                Button { onEdit(event) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: event.isAllDay ? "sun.max.fill" : "clock").font(.caption2)
                            Text(eventTimeText(event)).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            if !writable { Image(systemName: "lock.fill").font(.caption2).help(event.recurring ? "Повторяющиеся события доступны только для просмотра" : "Календарь только для просмотра") }
                        }
                        Text(event.title).font(.callout.weight(.medium)).lineLimit(3).multilineTextAlignment(.leading)
                        if event.isAllDay, let lastDay = event.visibleAllDayEnd, lastDay != event.start.dateOnly {
                            Text("до \(lastDay.description), включительно").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3).padding(.vertical, 5) }
                }
                .buttonStyle(.plain)
                .disabled(!writable)
                .accessibilityLabel("Событие: \(event.title), \(eventTimeText(event))\(writable ? ", редактировать" : ", только просмотр")")
                .help(event.recurring ? "Повторяющееся событие: изменение не поддерживается" : (canWrite ? "Редактировать событие" : "Календарь только для просмотра"))
            }
            if !tasks.isEmpty {
                Divider().padding(.vertical, 2)
                Text("ЗАДАЧИ · дата без времени").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(tasks) { task in
                    Button { onToggleTask(task) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? .secondary : Color(hex: "#16836B") ?? .green)
                            Text(task.title).lineLimit(2).strikethrough(task.completed)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    }

    private func eventTimeText(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            guard let start = event.start.dateOnly else { return "Весь день" }
            if event.visibleAllDayEnd == start { return "Весь день" }
            return "Весь день · \(start.description)–\(event.visibleAllDayEnd?.description ?? start.description)"
        }
        guard let start = event.start.instant, let end = event.end.instant else { return "Время не указано" }
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = timeZone
        return "\(start.formatted(formatter))–\(end.formatted(formatter))"
    }
}

struct EventEditorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent?
    let calendar: CalendarInfo?

    @StateObject private var local: ViewLocalState

    init(event: CalendarEvent?, calendar: CalendarInfo?) {
        self.event = event
        self.calendar = calendar
        let zoneID = event?.start.timeZoneID ?? calendar?.timeZoneID ?? TimeZone.current.identifier
        let zone = TimeZone(identifier: zoneID) ?? .current
        let startValue = event?.start.instant ?? event?.start.dateOnly?.startOfDay(in: zone) ?? Date().addingTimeInterval(900)
        let endValue = event?.end.instant ?? event?.end.dateOnly?.startOfDay(in: zone) ?? startValue.addingTimeInterval(3600)
        let displayedEnd: Date
        if event?.isAllDay == true, let inclusive = event?.visibleAllDayEnd, let date = inclusive.startOfDay(in: zone) { displayedEnd = date }
        else { displayedEnd = endValue }
        _local = StateObject(wrappedValue: ViewLocalState(title: event?.title ?? "", start: startValue, end: displayedEnd,
                                                         allDay: event?.isAllDay ?? false, timeZoneID: zone.identifier))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(event == nil ? "Новое событие" : "Редактирование события").font(.title2.weight(.semibold))
                Spacer()
                if event != nil { Button("Удалить", role: .destructive) { local.showingDeleteConfirmation = true }.disabled(!canEdit) }
            }
            Form {
                TextField("Название", text: $local.title)
                Toggle("Весь день", isOn: $local.allDay)
                DatePicker("Начало", selection: $local.start, displayedComponents: local.allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker(local.allDay ? "Последний день (включительно)" : "Окончание", selection: $local.end, displayedComponents: local.allDay ? [.date] : [.date, .hourAndMinute])
                Picker("Часовой пояс", selection: $local.timeZoneID) {
                    ForEach(timeZoneChoices, id: \.self) { id in Text(id).tag(id) }
                }
                if let calendar { LabeledContent("Календарь", value: calendar.title) }
                if let event {
                    Section("Локальное напоминание на этом Mac") {
                        if event.isAllDay || event.recurring {
                            Toggle("Напомнить локально", isOn: $local.enabled).disabled(true)
                            Text(event.isAllDay ? "Для событий на весь день локальное напоминание недоступно." : "Для повторяющихся событий выбор серии не поддерживается.")
                                .font(.callout).foregroundStyle(AppTheme.textSecondary)
                        } else {
                            Toggle("Напомнить локально", isOn: $local.enabled)
                            if local.enabled {
                                DatePicker("Точное время", selection: $local.fireDate, displayedComponents: [.date, .hourAndMinute])
                            }
                            Button(local.enabled ? "Сохранить локальное напоминание" : "Удалить локальное напоминание") {
                                saveEventReminder()
                            }
                            Text("Хранится только на этом Mac и не меняет Google event.reminders.")
                                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                        }
                        if let message = local.localMessage { Text(message).font(.callout).foregroundStyle(AppTheme.textSecondary) }
                    }
                } else {
                    Section("Локальное напоминание на этом Mac") {
                        Text("Сначала сохраните событие; затем можно добавить напоминание для конкретного события.")
                            .font(.callout).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if !canEdit { Text(event?.recurring == true ? "Повторяющиеся события доступны только для просмотра." : "Выбранный календарь доступен только для просмотра.").foregroundStyle(.orange) }
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).font(.callout)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction).disabled(!canEdit || local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.mutationInFlight)
            }
        }
        .padding(22)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            if let event, let record = model.eventReminderCoordinator.store.record(for: event.identity) {
                local.enabled = true
                local.fireDate = record.fireDate
            }
        }
        .confirmationDialog("Удалить событие?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить событие", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Это действие будет отправлено в Google после подтверждения.") }
    }

    private var canEdit: Bool { calendar?.isWritable == true && event?.recurring != true }
    private var timeZoneChoices: [String] {
        Array(Set([local.timeZoneID, TimeZone.current.identifier, "America/Los_Angeles", "America/New_York", "Europe/Moscow", "Europe/London"])).sorted()
    }

    private func save() {
        guard let calendar, calendar.isWritable else { local.errorMessage = "Для записи выберите календарь с правом редактирования."; return }
        guard local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { local.errorMessage = "Введите название события."; return }
        guard !local.allDay || DateOnly(date: local.start, timeZone: zone) <= DateOnly(date: local.end, timeZone: zone) else { local.errorMessage = "Дата окончания должна быть не раньше даты начала."; return }
        guard local.allDay || local.start < local.end else { local.errorMessage = "Окончание должно быть позже начала."; return }
        do {
            let factory = try model.commandFactory()
            let body = try makeBody()
            let invocation: ProcessInvocation
            if let event {
                guard !event.recurring else { local.errorMessage = "Изменение повторяющихся событий не поддерживается."; return }
                invocation = try factory.eventPatch(event: event, calendar: calendar, body: body, authorization: .userSave)
            } else {
                invocation = try factory.eventInsert(calendar: calendar, body: body, authorization: .userSave)
            }
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0 })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Сохранение не выполнено." }
    }

    private func delete() {
        guard let event, let calendar else { return }
        do {
            let invocation = try model.commandFactory().eventDelete(event: event, calendar: calendar, authorization: .confirmedDelete)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0 })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Удаление не выполнено." }
    }

    private func saveEventReminder() {
        guard let event, !event.isAllDay, !event.recurring else {
            local.errorMessage = "Локальное напоминание доступно только для timed non-recurring events."
            return
        }
        let date = local.enabled ? local.fireDate : nil
        Task {
            do {
                let authorization = try await model.eventReminderCoordinator.save(event: event, at: date,
                                                                                    explicitEnableAction: local.enabled)
                await model.refreshNotificationStatus()
                model.notificationPermission = authorization.status
                local.errorMessage = nil
                if date == nil { local.localMessage = "Локальное напоминание удалено." }
                else if authorization.status == .authorized { local.localMessage = "Локальное напоминание сохранено на этом Mac." }
                else { local.localMessage = authorization.userMessage }
            } catch {
                local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Локальное напоминание не сохранено."
            }
        }
    }

    private var zone: TimeZone { TimeZone(identifier: local.timeZoneID) ?? .current }

    private func makeBody() throws -> [String: Any] {
        if local.allDay {
            let startDay = DateOnly(date: local.start, timeZone: zone)
            let inclusiveEnd = DateOnly(date: local.end, timeZone: zone)
            guard let exclusiveEnd = inclusiveEnd.adding(days: 1) else { throw GWSFailure.invalidInput("event_end") }
            return ["summary": local.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    "start": ["date": startDay.description], "end": ["date": exclusiveEnd.description]]
        }
        return ["summary": local.title.trimmingCharacters(in: .whitespacesAndNewlines),
                "start": ["dateTime": timestamp(local.start, zone: zone), "timeZone": zone.identifier],
                "end": ["dateTime": timestamp(local.end, zone: zone), "timeZone": zone.identifier]]
    }

    private func timestamp(_ date: Date, zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = zone
        return formatter.string(from: date)
    }
}
