import SwiftUI

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

    init(task: GoogleTask?, taskListID: String?) {
        self.task = task
        self.taskListID = taskListID
        let initialDue = task?.due?.startOfDay(in: .current) ?? Date()
        _local = StateObject(wrappedValue: ViewLocalState(title: task?.title ?? "", notes: task?.notes ?? "",
                                                         dueEnabled: task?.due != nil, dueDate: initialDue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(task == nil ? "Новая задача" : "Редактирование задачи").font(.title2.weight(.semibold))
                Spacer()
                if task != nil { Button("Удалить", role: .destructive) { local.showingDeleteConfirmation = true } }
            }
            Form {
                TextField("Название", text: $local.title)
                TextField("Заметки", text: $local.notes, axis: .vertical).lineLimit(2...5)
                Toggle("Указать срок", isOn: $local.dueEnabled)
                if local.dueEnabled {
                    DatePicker("Срок (дата)", selection: $local.dueDate, displayedComponents: [.date])
                }
                LabeledContent("Список", value: model.snapshot.taskLists.first(where: { $0.id == taskListID })?.title ?? "Не выбран")
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).accessibilityAddTraits(.updatesFrequently)
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || taskListID == nil || model.mutationInFlight)
            }
        }
        .padding(22)
        .frame(minWidth: 460, minHeight: 400)
        .confirmationDialog("Удалить задачу?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить задачу", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Задача будет удалена из Google Tasks только после подтверждения.") }
    }

    private func save() {
        guard let taskListID else { local.errorMessage = "Сначала выберите список задач."; return }
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
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0 })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Сохранение не выполнено." }
    }

    private func delete() {
        guard let task else { return }
        do {
            let invocation = try model.commandFactory().taskDelete(task: task, authorization: .confirmedDelete)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0 })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Удаление не выполнено." }
    }
}

struct TaskListManagerView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Списки задач").font(.title2.weight(.semibold))
                Spacer()
                Button { local.listForm = .create } label: { Label("Новый список", systemImage: "plus") }
            }
            if model.snapshot.taskLists.isEmpty {
                WorkspaceEmptyState(title: "Списков пока нет", symbol: "list.bullet", description: "Создайте первый Google Tasks list.") { }
            } else {
                List(model.snapshot.taskLists) { list in
                    HStack {
                        Text(list.title).lineLimit(1)
                        Spacer()
                        Button("Изменить") { local.listForm = .edit(list) }
                    }
                    .padding(.vertical, 3)
                }
            }
            HStack { Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
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

    init(list: TaskList?) {
        self.list = list
        _local = StateObject(wrappedValue: ViewLocalState(title: list?.title ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(list == nil ? "Новый список" : "Переименовать список").font(.title2.weight(.semibold))
                Spacer()
                if list != nil { Button("Удалить…", role: .destructive) { local.showingDeleteConfirmation = true } }
            }
            Form {
                TextField("Название списка", text: $local.title)
                if let message = local.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.overdue).accessibilityAddTraits(.updatesFrequently)
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.mutationInFlight)
            }
        }
        .padding(22)
        .frame(minWidth: 400, minHeight: 200)
        .confirmationDialog("Удалить список задач?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить список", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Будут удалены список и его задачи в Google Tasks.") }
    }

    private func save() {
        do {
            let factory = try model.commandFactory()
            let invocation = try list.map { try factory.taskListPatch(id: $0.id, title: local.title, authorization: .userSave) }
                ?? factory.taskListInsert(title: local.title, authorization: .userSave)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: { local.errorMessage = $0 })
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
            }, onFailure: { local.errorMessage = $0 })
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Локальное напоминание").font(.title2.weight(.semibold))
            Text("Для «\(task.title)». Время хранится только на этом устройстве и не отправляется в Google Tasks.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Напомнить в выбранное время", isOn: $local.enabled)
            if local.enabled { DatePicker("Время", selection: $local.fireDate, displayedComponents: [.date, .hourAndMinute]) }
            Text("Показ зависит от разрешения macOS, Focus и настроек уведомлений. Спящий Mac может показать уведомление позже; после явного завершения приложения доставка не гарантируется.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = local.reminderStatus { Text(message).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(local.isSaving ? "Сохраняется…" : (local.enabled ? "Включить и сохранить" : "Удалить напоминание")) { save() }
                    .keyboardShortcut(.defaultAction).disabled(local.isSaving)
            }
        }
        .padding(22)
        .frame(minWidth: 450, minHeight: 300)
        .onAppear {
            let metadata = model.metadataStore.metadata(for: task.id)
            local.enabled = metadata.reminderAt != nil
            local.fireDate = metadata.reminderAt ?? Date().addingTimeInterval(3600)
        }
    }

    private func save() {
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
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Google Workspace CLI") {
                        VStack(alignment: .leading, spacing: 9) {
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

                    GroupBox("Внешний вид") {
                        Picker("Тема", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                            ForEach(WorkspaceViewModel.Appearance.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Локальные уведомления") {
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
                                    Text("Состояние macOS: \(status.authorization) · alerts: \(status.alertSetting) · sound: \(status.soundSetting)")
                                    Text("Ожидают: \(status.pendingCount) · доставлено в Notification Center: \(status.deliveredCount)")
                                    Text("Foreground-показатель приложения: \(status.foregroundDelegateReady ? "готов" : "не готов")")
                                }
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Уведомления: \(status.authorization), alerts \(status.alertSetting), sound \(status.soundSetting), ожидают \(status.pendingCount), доставлено \(status.deliveredCount), foreground delegate \(status.foregroundDelegateReady ? "готов" : "не готов")")
                            } else {
                                ProgressView("Проверяется статус macOS…").font(.caption)
                            }
                            if let reminderStatus = local.reminderStatus {
                                Text(reminderStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
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
        .padding(16)
        .frame(minWidth: 400, idealWidth: 500, minHeight: 430)
        .task { await model.refreshNotificationStatus() }
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
                local.reminderStatus = "Статус macOS — denied. Это не доказывает, что пользователь нажал «Не разрешать»; проверьте настройки уведомлений приложения в System Settings."
            }
        }
    }
}
