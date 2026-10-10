import SwiftUI

struct EditorBody<Content: View>: View {
    @ViewBuilder let content: Content

    private var maximumHeight: CGFloat {
        // Reserve space for header, 24 pt insets and the taller recovery footer.
        max(180, min(520, (NSApp.mainWindow?.contentLayoutRect.height ?? 700) - 180))
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content.fixedSize(horizontal: false, vertical: true) }
                .scrollIndicators(.visible)
        }.frame(maxHeight: maximumHeight)
    }
}

/// Shared editor spacing: 24 pt outer inset, 16 pt sections, 8 pt field labels.
struct EditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(AppTheme.textSecondary)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MutationSaveControl: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let pendingMutationID: UUID?
    let disabled: Bool
    let save: () -> Void
    let verified: () -> Void
    var verifiedResult: ((GWSMutationResult) -> Void)? = nil

    private var ownsPendingAttempt: Bool {
        pendingMutationID != nil && pendingMutationID == model.pendingMutation?.id
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if ownsPendingAttempt {
                Text(model.pendingMutation?.resourceID == nil
                     ? "ID не получен. Закройте форму и откройте сохранённый черновик для ручной сверки."
                     : "Запрос уже отправлен. Проверка повторно прочитает объект.")
                    .font(.caption).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
                Button(model.mutationInFlight ? "Проверяем…" : "Проверить сохранение") {
                    model.recheckPendingMutation(onSuccess: verifiedResult == nil ? verified : nil,
                                                 thenRefresh: verifiedResult == nil, onVerified: verifiedResult)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(disabled || model.mutationInFlight || model.pendingMutation?.resourceID == nil)
            } else {
                Button(model.mutationInFlight ? "Сохраняем…" : "Сохранить", action: save)
                    .keyboardShortcut(.defaultAction).disabled(disabled || model.mutationsBlocked)
            }
        }
    }
}

struct WorkspaceEmptyState: View {
    let title: String
    let symbol: String
    let description: String
    let actionTitle: String?
    let action: () -> Void

    init(title: String, symbol: String, description: String, actionTitle: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle { Button(actionTitle, action: action).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}

struct TaskEditorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    let task: GoogleTask?
    let taskListID: String?

    @StateObject private var local: ViewLocalState
    @FocusState private var titleFocused: Bool
    @StateObject private var reminder = TaskEditorReminderState()

    init(task: GoogleTask?, taskListID: String?) {
        self.task = task
        self.taskListID = taskListID
        let initialDue = task?.due?.startOfDay(in: .current) ?? Date()
        _local = StateObject(wrappedValue: ViewLocalState(title: task?.title ?? "", notes: task?.notes ?? "",
                                                         dueEnabled: task?.due != nil, dueDate: initialDue, contextID: taskListID ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            HStack {
                Text(task == nil ? "Новая задача" : "Редактирование задачи").font(.title2.weight(.semibold))
                Spacer()
                if task != nil { Button("Удалить", role: .destructive) { local.showingDeleteConfirmation = true }.disabled(model.mutationsBlocked || reminder.isSaving || !reminder.saveState.needsGoogleSave) }
            }
            EditorBody {
            VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
                Group {
                EditorField(title: "Название") { TextField("Название задачи", text: $local.title).textFieldStyle(.roundedBorder).focused($titleFocused) }
                EditorField(title: "Заметки") { TextField("Необязательно", text: $local.notes, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder) }
                Toggle("Указать срок", isOn: $local.dueEnabled)
                if local.dueEnabled {
                    DatePicker("Срок (дата)", selection: $local.dueDate, displayedComponents: [.date])
                }
                if task == nil {
                    EditorField(title: "Список") {
                        Picker("Список задач", selection: $local.contextID) {
                            ForEach(model.snapshot.taskLists) { Text($0.title).tag($0.id) }
                        }.labelsHidden()
                    }
                } else {
                    LabeledContent("Список", value: model.snapshot.taskLists.first(where: { $0.id == taskListID })?.title ?? "Не выбран")
                }
                }
                .disabled(!reminder.saveState.needsGoogleSave)
                Text("Google Tasks API сохраняет срок только как дату. Время ниже относится к локальному напоминанию на этом Mac.")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Локальное напоминание", isOn: $reminder.enabled)
                    .disabled(task?.completed == true)
                if reminder.enabled {
                    DatePicker("Напомнить", selection: $reminder.fireDate, displayedComponents: [.date, .hourAndMinute])
                        .disabled(task?.completed == true)
                }
                if task?.completed == true {
                    Text("Для выполненной задачи уведомление не планируется.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = reminder.message {
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                }
            }
            }
            .disabled(model.mutationsBlocked || reminder.isSaving)
            HStack {
                Spacer()
                Button(reminder.saveState.needsGoogleSave ? "Отмена" : "Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(reminder.isSaving)
                if reminder.saveState.needsGoogleSave {
                    MutationSaveControl(pendingMutationID: local.pendingMutationID,
                                        disabled: reminder.isSaving || local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || local.contextID.isEmpty,
                                        save: save, verified: {}, verifiedResult: taskVerified)
                } else {
                    Button(reminder.isSaving ? "Сохраняем напоминание…" : "Сохранить напоминание", action: saveLocalReminder)
                        .keyboardShortcut(.defaultAction).disabled(reminder.isSaving)
                }
            }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .defaultFocus($titleFocused, true)
        .onAppear {
            if local.contextID.isEmpty { local.contextID = model.snapshot.taskLists.first?.id ?? "" }
            if !reminder.initialized {
                if let task, let date = model.metadataStore.metadata(for: task.id).reminderAt {
                    reminder.enabled = true
                    reminder.fireDate = date
                    reminder.originalFireDate = date
                }
                reminder.initialized = true
            }
        }
        .confirmationDialog("Удалить задачу?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить задачу", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text(model.launchMode == .demo ? "Будет удалена только тестовая задача в демо-режиме." : "Задача будет удалена из Google Tasks только после подтверждения.") }
    }

    private func save() {
        guard !reminder.isSaving else { return }
        if !reminder.saveState.needsGoogleSave { saveLocalReminder(); return }
        if let problem = TaskReminderSaveState.validationMessage(enabled: reminder.enabled, fireDate: reminder.fireDate,
                                                                     unchangedDate: reminder.originalFireDate, completed: task?.completed == true) {
            local.errorMessage = problem
            return
        }
        local.errorMessage = nil
        let taskListID = task?.taskListID ?? local.contextID
        guard !taskListID.isEmpty else { local.errorMessage = "Сначала выберите список задач."; return }
        do {
            let factory = try model.commandFactory()
            let due = local.dueEnabled ? DateOnly(date: local.dueDate) : nil
            let invocation: ProcessInvocation
            if let task {
                invocation = try factory.taskPatch(task: task, title: local.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   notes: local.notes, due: due, authorization: .userSave)
            } else {
                invocation = try factory.taskInsert(taskListID: taskListID, title: local.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    notes: local.notes, due: due, authorization: .userSave)
            }
            model.performMutation(invocation, thenRefresh: false,
                                  onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id },
                                  onVerified: taskVerified)
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Сохранение не выполнено." }
    }

    private func taskVerified(_ result: GWSMutationResult) {
        if case .resourceDeleted = result {
            model.refreshTasksAfterSave()
            dismiss()
            return
        }
        guard reminder.saveState.accept(result) else {
            local.errorMessage = "Результат сохранения задачи не подтверждён."
            return
        }
        local.pendingMutationID = nil
        local.errorMessage = nil
        saveLocalReminder()
    }

    private func saveLocalReminder() {
        guard !reminder.isSaving, let verifiedTask = reminder.saveState.verifiedTask else { return }
        if let problem = TaskReminderSaveState.validationMessage(enabled: reminder.enabled, fireDate: reminder.fireDate,
                                                                     unchangedDate: reminder.originalFireDate, completed: task?.completed == true) {
            local.errorMessage = "Задача сохранена. " + problem
            model.refreshTasksAfterSave()
            return
        }
        reminder.isSaving = true
        reminder.message = nil
        local.errorMessage = nil
        let date = reminder.enabled ? reminder.fireDate : nil
        Task { @MainActor in
            defer {
                reminder.isSaving = false
                model.refreshTasksAfterSave()
            }
            do {
                let authorization = try await model.reminderCoordinator.saveReminder(task: verifiedTask, title: verifiedTask.title,
                                                                                     at: date, explicitEnableAction: reminder.enabled)
                if date == nil {
                    dismiss()
                } else if verifiedTask.completed || (date == reminder.originalFireDate && reminder.fireDate <= Date()) {
                    // Keep a pre-existing expired reminder without blocking ordinary task edits.
                    dismiss()
                } else if authorization.status == .authorized && reminder.fireDate > Date() && !verifiedTask.deleted {
                    dismiss()
                } else {
                    let delivery = verifiedTask.completed ? "Для выполненной задачи уведомление не планируется." : authorization.userMessage
                    reminder.message = "Задача сохранена. Время локального напоминания сохранено. " + delivery
                }
                await model.refreshNotificationStatus()
            } catch {
                local.errorMessage = "Задача сохранена. Не удалось сохранить или запланировать локальное напоминание. Можно повторить только сохранение напоминания или закрыть форму."
            }
        }
    }

    private func delete() {
        guard let task else { return }
        do {
            let invocation = try model.commandFactory().taskDelete(task: task, authorization: .confirmedDelete)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Удаление не выполнено." }
    }
}

struct TaskListManagerView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            HStack {
                Text("Списки задач").font(.title2.weight(.semibold))
                Spacer()
                Button { local.listForm = .create } label: { Label("Новый список", systemImage: "plus") }
            }
            if model.snapshot.taskLists.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
                    Label("Списков пока нет", systemImage: "list.bullet").font(.headline)
                    Text("Создайте первый список задач.").foregroundStyle(AppTheme.textSecondary)
                }.padding(.vertical, AppTheme.sectionGap)
            } else {
                List(model.snapshot.taskLists) { list in
                    Button { local.listForm = .edit(list) } label: {
                        HStack {
                            Text(list.title).lineLimit(1).foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Label("Изменить", systemImage: "pencil").foregroundStyle(AppTheme.accent)
                        }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(.interaction, Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Изменить список: \(list.title)")
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .frame(height: CGFloat(min(model.snapshot.taskLists.count, 6)) * 44 + 16)
            }
            HStack { Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $local.listForm) { form in
            switch form {
            case .create: TaskListEditorView(list: nil).environmentObject(model)
            case .edit(let list): TaskListEditorView(list: list).environmentObject(model)
            }
        }
    }
}

private struct TaskListEditorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    let list: TaskList?
    @StateObject private var local: ViewLocalState
    @FocusState private var titleFocused: Bool

    init(list: TaskList?) {
        self.list = list
        _local = StateObject(wrappedValue: ViewLocalState(title: list?.title ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            HStack {
                Text(list == nil ? "Новый список" : "Переименовать список").font(.title2.weight(.semibold))
                Spacer()
                if list != nil { Button("Удалить…", role: .destructive) { local.showingDeleteConfirmation = true }.disabled(model.mutationsBlocked) }
            }
            EditorBody {
            VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
                EditorField(title: "Название списка") { TextField("Например, Рабочие задачи", text: $local.title).textFieldStyle(.roundedBorder).focused($titleFocused) }
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                }
            }
            }
            .disabled(model.mutationsBlocked)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                MutationSaveControl(pendingMutationID: local.pendingMutationID, disabled: local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: save, verified: { dismiss() })
            }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .defaultFocus($titleFocused, true)
        .confirmationDialog("Удалить список задач?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить список", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text(model.launchMode == .demo ? "Будут удалены только тестовый список и его задачи в демо-режиме." : "Будут удалены список и его задачи в Google Tasks.") }
    }

    private func save() {
        do {
            let factory = try model.commandFactory()
            let invocation = try list.map { try factory.taskListPatch(id: $0.id, title: local.title, authorization: .userSave) }
                ?? factory.taskListInsert(title: local.title, authorization: .userSave)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Сохранение не выполнено." }
    }

    private func delete() {
        guard let list else { return }
        do {
            let invocation = try model.commandFactory().taskListDelete(id: list.id, authorization: .confirmedDelete)
            let tasks = model.snapshot.tasks.filter { $0.taskListID == list.id }
            let coordinator = model.reminderCoordinator
            model.performMutation(invocation, onSuccess: {
                Task { for task in tasks { try? await coordinator.delete(taskID: task.id) } }
                dismiss()
            }, onFailure: { local.errorMessage = $0; local.pendingMutationID = model.pendingMutation?.id })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Удаление не выполнено." }
    }
}

struct ReminderEditorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    let task: GoogleTask
    @StateObject private var local: ViewLocalState

    init(task: GoogleTask) {
        self.task = task
        _local = StateObject(wrappedValue: ViewLocalState(enabled: false, fireDate: Date().addingTimeInterval(3600)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            Text("Локальное напоминание").font(.title2.weight(.semibold))
            EditorBody {
                VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            Text("Для «\(task.title)». Время хранится только на этом устройстве и не отправляется в Google Tasks.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Напомнить в выбранное время", isOn: $local.enabled)
            if local.enabled { DatePicker("Время", selection: $local.fireDate, displayedComponents: [.date, .hourAndMinute]) }
            Text("Показ зависит от разрешения macOS, Focus и настроек уведомлений. Спящий Mac может показать уведомление позже; после явного завершения приложения доставка не гарантируется.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = local.reminderStatus { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(local.isSaving ? "Сохраняется…" : (local.enabled ? "Включить и сохранить" : "Удалить напоминание")) { save() }
                    .keyboardShortcut(.defaultAction).disabled(local.isSaving)
            }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            let metadata = model.metadataStore.metadata(for: task.id)
            local.enabled = metadata.reminderAt != nil
            local.fireDate = metadata.reminderAt ?? Date().addingTimeInterval(3600)
        }
    }

    private func save() {
        guard model.launchMode == .normal else {
            local.reminderStatus = "В тестовом режиме системные уведомления отключены. Напоминание не отправлено в macOS."
            return
        }
        local.isSaving = true
        Task {
            do {
                let authorization = try await model.reminderCoordinator.saveReminder(task: task, title: task.title,
                                                                                     at: local.enabled ? local.fireDate : nil,
                                                                                     explicitEnableAction: local.enabled)
                await model.refreshNotificationStatus()
                await MainActor.run {
                    model.notificationPermission = authorization.status
                    local.isSaving = false
                    if local.enabled && authorization.status != .authorized {
                        local.reminderStatus = authorization.userMessage
                    } else {
                        model.statusMessage = local.enabled ? "Локальное напоминание сохранено." : "Локальное напоминание удалено."
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run { local.isSaving = false; local.reminderStatus = "Не удалось сохранить локальное напоминание." }
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var loginItems = LoginItemSettings()
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            Text("Настройки")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
                    SettingsSection(title: "Google Workspace CLI") {
                        VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
                            Text("Оставьте путь пустым для безопасного поиска gws. Приложение проверяет только исполняемый файл и не читает и не показывает OAuth-данные.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("Например, /opt/homebrew/bin/gws", text: $model.gwsPath)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Абсолютный путь к исполняемому файлу gws")
                                .frame(maxWidth: .infinity)
                            if let pathStatus = local.pathStatus {
                                Text(pathStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                            Button("Проверить и сохранить путь") {
                                model.saveSettings()
                                do { _ = try model.commandFactory(); local.pathStatus = "gws доступен. Выполните синхронизацию для чтения данных." }
                                catch { local.pathStatus = (error as? LocalizedError)?.errorDescription ?? "gws недоступен." }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SettingsSection(title: "Внешний вид") {
                        Picker("Тема", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                            ForEach(WorkspaceViewModel.Appearance.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SettingsSection(title: "Запуск приложения") {
                        Toggle("Запускать при входе в систему", isOn: Binding(
                            get: { loginItems.isRegistered },
                            set: { enabled in Task { await loginItems.setEnabled(enabled) } }
                        ))
                        .disabled(!loginItems.isAvailable || loginItems.isUpdating)
                        Text(loginItems.statusMessage).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = loginItems.errorMessage {
                            Text(message).font(.caption).foregroundStyle(AppTheme.overdue)
                                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                        }
                        Button("Объекты входа в macOS") { loginItems.openSystemSettings() }
                            .disabled(!loginItems.isAvailable || loginItems.isUpdating)
                    }

                    SettingsSection(title: "Горячие клавиши") {
                        WorkspaceShortcutSettingsView()
                    }

                    SettingsSection(title: "Локальные уведомления") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(notificationActionTitle, action: inspectOrRequestNotificationAccess)
                                .disabled(model.launchMode != .normal || model.notificationRuntimeStatus == nil ||
                                          model.notificationRuntimeStatus?.authorization == "authorized")
                            if model.launchMode == .demo || model.launchMode == .ledgerAcceptance {
                                Text("UserNotifications отключены в изолированном тестовом режиме.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let status = model.notificationRuntimeStatus {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(status.userFacingLines, id: \.self) { Text($0) }
                                }
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(status.userFacingLines.joined(separator: " "))
                            } else {
                                ProgressView("Проверяется статус macOS…").font(.caption)
                            }
                            if let reminderStatus = local.reminderStatus {
                                Text(reminderStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                            Button("Открыть настройки уведомлений macOS") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Text("Чтобы уведомления оставались до закрытия, выберите g-calendar в уведомлениях macOS и стиль «Предупреждения» (постоянный). Системный выбор имеет приоритет.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Показы зависят от Focus и системных настроек. Во время сна уведомление может задержаться; после явного завершения приложения доставка не гарантируется.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack { Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(AppTheme.editorInset)
        .frame(minWidth: 400, idealWidth: 500, minHeight: 430)
        .task {
            loginItems.refresh(isNormalMode: model.launchMode == .normal)
            await model.refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItems.refresh(isNormalMode: model.launchMode == .normal)
            Task { await model.refreshNotificationStatus() }
        }
    }

    private var notificationActionTitle: String {
        if model.launchMode != .normal { return "Уведомления отключены в тестовом режиме" }
        return model.notificationRuntimeStatus?.authorization == "not_determined" ? "Запросить разрешение…" : "Обновить статус"
    }

    private func inspectOrRequestNotificationAccess() {
        Task {
            if model.notificationRuntimeStatus?.authorization == "not_determined" {
                let result = await model.reminderCoordinator.enableAfterExplicitUserAction()
                model.notificationPermission = result.status
                local.reminderStatus = result.userMessage
                if result.status == .authorized {
                    await model.reminderCoordinator.reconcile(tasks: model.snapshot.tasks)
                }
            }
            await model.refreshNotificationStatus()
            if model.notificationRuntimeStatus?.authorization == "denied" {
                local.reminderStatus = "Уведомления отключены. Разрешите их для g-calendar в системных настройках macOS → Уведомления."
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
            Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(AppTheme.outline.opacity(0.4))
            .allowsHitTesting(false).accessibilityHidden(true))
        .accessibilityElement(children: .contain)
    }
}

private struct WorkspaceShortcutSettingsView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = WorkspaceShortcutEditorState()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
            Text("Укажите латинскую клавишу и модификаторы, затем нажмите «Применить». Изменения сохраняются сразу. ⌘Q, Return, Escape и стрелки остаются стандартными.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(WorkspaceShortcutAction.allCases) { action in
                WorkspaceShortcutEditor(action: action)
            }
            .id(local.resetGeneration)
            Button("Сбросить горячие клавиши") {
                model.resetShortcuts()
                local.resetGeneration += 1
            }
        }
    }
}

private struct WorkspaceShortcutEditor: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let action: WorkspaceShortcutAction
    @StateObject private var local = WorkspaceShortcutEditorState()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.title).font(.callout)
            HStack(spacing: 8) {
                TextField("Клавиша", text: $local.draft.key)
                    .textFieldStyle(.roundedBorder).frame(width: 48)
                    .accessibilityLabel("Клавиша: " + action.title)
                modifier("⌘", value: $local.draft.command, name: "Command")
                modifier("⌥", value: $local.draft.option, name: "Option")
                modifier("⌃", value: $local.draft.control, name: "Control")
                modifier("⇧", value: $local.draft.shift, name: "Shift")
                Spacer(minLength: 0)
                Button("Применить") { local.problem = model.updateShortcut(local.draft, for: action) }
            }
            if let problem = local.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear { local.draft = model.shortcutSettings[action] }
        .onChange(of: model.shortcutSettings[action]) { binding in
            local.draft = binding
            local.problem = nil
        }
    }

    private func modifier(_ symbol: String, value: Binding<Bool>, name: String) -> some View {
        Toggle(symbol, isOn: value).toggleStyle(.checkbox)
            .accessibilityLabel(name + ": " + action.title)
    }
}

@MainActor
private final class WorkspaceShortcutEditorState: ObservableObject {
    @Published var resetGeneration = 0
    @Published var draft = WorkspaceShortcutBinding(key: "")
    @Published var problem: String?
}

@MainActor
private final class TaskEditorReminderState: ObservableObject {
    @Published var initialized = false
    @Published var enabled = false
    @Published var fireDate = Date().addingTimeInterval(3600)
    var originalFireDate: Date?
    @Published var isSaving = false
    @Published var message: String?
    @Published var saveState = TaskReminderSaveState()
}
