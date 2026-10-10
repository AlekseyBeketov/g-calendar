import SwiftUI

struct CalendarWorkspaceView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()
    @AppStorage("calendarUndatedTasksCollapsed") private var undatedTasksCollapsed = true

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(periodTitle).font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(model.calendarMode.rawValue).font(.caption).foregroundStyle(.secondary)
                        if let calendar = model.selectedCalendar {
                            Text(calendar.isWritable ? calendar.title : "\(calendar.title) · Только просмотр")
                                .font(.caption).foregroundStyle(calendar.isWritable ? AppTheme.textSecondary : AppTheme.warning).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Picker("Вид календаря", selection: $model.calendarMode) {
                    ForEach(WorkspaceViewModel.CalendarMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                Button { local.showingEventEditor = true; local.selectedEvent = nil } label: { Label("Событие", systemImage: "plus") }
                    .disabled(model.selectedCalendar?.isWritable != true || model.mutationsBlocked)
                    .help(model.selectedCalendar?.isWritable == true ? "Создать событие" : "Выберите календарь с правом записи")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if model.snapshot.calendars.isEmpty {
                WorkspaceEmptyState(title: model.snapshot.fetchedAt == .distantPast ? "Календари не загружены" : "Нет доступных календарей", symbol: "calendar",
                                    description: model.snapshot.fetchedAt == .distantPast
                                        ? "Проверьте подключение и выполните синхронизацию."
                                        : "Синхронизация завершена. В подключённом аккаунте нет доступных календарей.",
                                    actionTitle: "Обновить") { model.refresh() }
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
                            .padding(.horizontal, 24)
                    }
                    if !model.undatedTasks.isEmpty {
                        CalendarUndatedTaskRegion(tasks: model.undatedTasks, isCollapsed: $undatedTasksCollapsed, onToggleTask: toggleTask)
                            .padding(.horizontal, 24)
                            .disabled(model.mutationsBlocked)
                    }
                    GeometryReader { geometry in
                        let availableWidth = Double(geometry.size.width - 48)
                        let timeAxisWidth = CGFloat(CalendarGridLayout.timeAxisWidth)
                        let columnWidth = CGFloat(CalendarGridLayout.columnWidth(
                            isDayView: model.calendarMode == .day,
                            availableWidth: availableWidth,
                            visibleDayCount: visibleDays.count
                        ))
                        let headerHeight = CGFloat(CalendarGridLayout.headerHeight)
                        let dateOnlyHeight = sharedDateOnlyHeight
                        let axisDayMinutes = visibleDays.compactMap { CalendarTimeGridLayout.dayInterval(containing: $0, timeZone: model.selectedTimeZone)?.durationMinutes }.max() ?? 1_440
                        let bottomPadding = CalendarTimedCardLayout.bottomPadding(minimumHeight: CalendarTimedCardTypography(sizeCategory: sizeCategory).policy.minimumHeight)
                        let axisContentHeight = CGFloat(axisDayMinutes * CalendarGridLayout.pointsPerMinute + bottomPadding)
                        let documentWidth = CGFloat(visibleDays.count) * columnWidth + CGFloat(max(0, visibleDays.count - 1)) * 10
                        let axisDay = visibleDays.first ?? model.currentRange().start
                        let initialMinutes = CalendarTimeGridLayout.dayInterval(containing: axisDay, timeZone: model.selectedTimeZone)
                            .flatMap { interval in CalendarTimeGridLayout.hourMarks(for: interval, timeZone: model.selectedTimeZone).first { $0.localHour == 8 }?.offsetMinutes } ?? 480
                        CalendarNativeScrollableGrid(
                            axis: AnyView(CalendarHourAxis(day: axisDay, timeZone: model.selectedTimeZone, height: axisContentHeight)
                                .background(AppTheme.canvas)),
                            headers: AnyView(VStack(spacing: 0) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(visibleDays, id: \.self) { day in dayColumn(day, width: columnWidth).dayHeader }
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(visibleDays, id: \.self) { day in dayColumn(day, width: columnWidth).dateOnlyArea }
                                }
                                Rectangle().fill(AppTheme.outline.opacity(0.45)).frame(height: 1)
                            }),
                            days: AnyView(HStack(alignment: .top, spacing: 10) {
                                ForEach(visibleDays, id: \.self) { day in dayColumn(day, width: columnWidth) }
                            }),
                            axisWidth: timeAxisWidth,
                            headerHeight: headerHeight + dateOnlyHeight + 1,
                            documentWidth: documentWidth,
                            documentHeight: axisContentHeight,
                            initialVerticalOffset: CGFloat(initialMinutes * CalendarGridLayout.pointsPerMinute)
                        )
                        .padding(.horizontal, 24)
                        .background(AppTheme.canvas)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Spacer(minLength: 0)
            Text("Повторяющиеся события доступны только для просмотра; участники и приглашения не поддерживаются.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .sheet(isPresented: $local.showingEventEditor, onDismiss: { local.selectedEvent = nil }) {
            EventEditorView(event: local.selectedEvent, calendar: editorCalendar)
                .environmentObject(model)
        }
        .onChange(of: model.calendarMode) { _ in model.refreshCalendarRangeIfNeeded() }
        .onChange(of: model.selectedCalendarID) { _ in model.refreshCalendarRangeIfNeeded() }
        .onChange(of: model.newItemRequestID) { _ in
            guard model.section == .calendar, model.selectedCalendar?.isWritable == true else { return }
            local.selectedEvent = nil
            local.showingEventEditor = true
        }
        .accessibilityIdentifier("calendar-workspace")
    }

    private func dayColumn(_ day: Date, width: CGFloat) -> CalendarTimeGridDay {
        CalendarTimeGridDay(day: day,
                           events: model.events(on: day),
                           tasks: model.tasks(on: day),
                           calendars: model.snapshot.calendars,
                           timeZone: model.selectedTimeZone,
                           columnWidth: width,
                           dateOnlyHeight: sharedDateOnlyHeight,
                           onEdit: { event in local.selectedEvent = event; local.showingEventEditor = true },
                           onToggleTask: toggleTask)
    }

    private var sharedDateOnlyHeight: CGFloat {
        let maximum = visibleDays.map { day in
            CalendarTimeGridLayout.allDayEvents(model.events(on: day), on: day, timeZone: model.selectedTimeZone).count + model.tasks(on: day).count
        }.max() ?? 0
        return CGFloat(CalendarGridLayout.dateOnlyHeight(maximumItemCount: maximum))
    }

    private var editorCalendar: CalendarInfo? {
        guard let event = local.selectedEvent else { return model.selectedCalendar }
        return model.snapshot.calendars.first { $0.id == event.calendarID }
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

struct EventEditorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent?
    let calendar: CalendarInfo?

    @StateObject private var local: ViewLocalState
    @FocusState private var titleFocused: Bool

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
                                                         allDay: event?.isAllDay ?? false, timeZoneID: zone.identifier, contextID: calendar?.isWritable == true ? (calendar?.id ?? "") : ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            HStack {
                Text(event == nil ? "Новое событие" : (canEdit ? "Редактирование события" : "Просмотр события")).font(.title2.weight(.semibold))
                Spacer()
                if event != nil && canEdit { Button("Удалить", role: .destructive) { local.showingDeleteConfirmation = true }.disabled(model.mutationsBlocked) }
            }
            EditorBody {
            VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
                if canEdit {
                    EditorField(title: "Название") { TextField("Название события", text: $local.title).textFieldStyle(.roundedBorder).focused($titleFocused) }
                    Toggle("Весь день", isOn: $local.allDay)
                    DatePicker("Начало", selection: $local.start, displayedComponents: local.allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker(local.allDay ? "Последний день (включительно)" : "Окончание", selection: $local.end, displayedComponents: local.allDay ? [.date] : [.date, .hourAndMinute])
                    Picker("Часовой пояс", selection: $local.timeZoneID) {
                        ForEach(timeZoneChoices, id: \.self) { id in Text(id).tag(id) }
                    }
                } else {
                    EditorField(title: "Название") { Text(local.title).textSelection(.enabled).foregroundStyle(AppTheme.textPrimary) }
                    LabeledContent("Формат", value: local.allDay ? "Весь день" : "Со временем")
                    LabeledContent("Начало", value: readOnlyDateText(local.start))
                    LabeledContent(local.allDay ? "Последний день (включительно)" : "Окончание", value: readOnlyDateText(local.end))
                    LabeledContent("Часовой пояс", value: local.timeZoneID)
                }
                if event == nil {
                    Picker("Календарь", selection: $local.contextID) {
                        ForEach(model.sortedCalendars.filter(\.isWritable)) { Text($0.title).tag($0.id) }
                    }
                } else if let calendar { LabeledContent("Календарь", value: calendar.title) }
                if let event {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Локальное напоминание на этом Mac").font(.callout.weight(.medium))
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Локальное напоминание на этом Mac").font(.callout.weight(.medium))
                        Text("Сначала сохраните событие; затем можно добавить напоминание для конкретного события.")
                            .font(.callout).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if !canEdit { Text(event?.recurring == true ? "Повторяющиеся события доступны только для просмотра." : "Выбранный календарь доступен только для просмотра.").foregroundStyle(AppTheme.warning) }
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            }
            .disabled(model.mutationsBlocked)
            HStack {
                Spacer()
                Button(canEdit ? "Отмена" : "Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
                if canEdit {
                    MutationSaveControl(pendingMutationID: local.pendingMutationID, disabled: local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: save, verified: { dismiss() })
                }
            }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .defaultFocus($titleFocused, true)
        .onAppear {
            if event == nil && local.contextID.isEmpty { local.contextID = model.sortedCalendars.first(where: \.isWritable)?.id ?? "" }
            if let event, let record = model.eventReminderCoordinator.store.record(for: event.identity) {
                local.enabled = true
                local.fireDate = record.fireDate
            }
        }
        .confirmationDialog("Удалить событие?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить событие", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text(model.launchMode == .demo ? "Будет удалено только тестовое событие в демо-режиме." : "Это действие будет отправлено в Google после подтверждения.") }
    }

    private var activeCalendar: CalendarInfo? {
        event == nil ? model.snapshot.calendars.first { $0.id == local.contextID } : calendar
    }

    private var canEdit: Bool {
        activeCalendar?.isWritable == true && event?.recurring != true && (event == nil || event?.calendarID == calendar?.id)
    }
    private var timeZoneChoices: [String] {
        Array(Set([local.timeZoneID, TimeZone.current.identifier, "America/Los_Angeles", "America/New_York", "Europe/Moscow", "Europe/London"])).sorted()
    }

    private func readOnlyDateText(_ date: Date) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: local.allDay ? .omitted : .shortened)
        format.timeZone = zone
        return date.formatted(format)
    }

    private func save() {
        guard let calendar = activeCalendar, calendar.isWritable else { local.errorMessage = "Для записи выберите календарь с правом редактирования."; return }
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
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Сохранение не выполнено." }
    }

    private func delete() {
        guard let event, let calendar else { return }
        do {
            let invocation = try model.commandFactory().eventDelete(event: event, calendar: calendar, authorization: .confirmedDelete)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Удаление не выполнено." }
    }

    private func saveEventReminder() {
        guard model.launchMode == .normal else {
            local.localMessage = "В тестовом режиме системные уведомления отключены. Напоминание не отправлено в macOS."
            return
        }
        guard let event, !event.isAllDay, !event.recurring else {
            local.errorMessage = "Локальное напоминание доступно для события со временем без повторения."
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
