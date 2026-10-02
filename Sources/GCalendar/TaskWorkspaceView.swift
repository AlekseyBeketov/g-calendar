import SwiftUI

struct TaskWorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedTaskList?.title ?? "Задачи").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    Text("Срок Google Tasks — дата без времени. Напоминания хранятся только на этом устройстве.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Picker("Фильтр задач", selection: $model.taskFilter) {
                    ForEach(WorkspaceViewModel.TaskFilter.allCases, id: \.self) { filter in Text(filter.rawValue).tag(filter) }
                }
                .pickerStyle(.menu)
                Button { local.showTaskLists = true } label: { Label("Списки", systemImage: "list.bullet") }
                Button { local.showingNewTask = true } label: { Label("Задача", systemImage: "plus") }
                    .disabled(model.selectedTaskListID == nil || model.mutationInFlight)
            }
            .padding(.horizontal, 18)

            if model.snapshot.taskLists.isEmpty {
                WorkspaceEmptyState(title: "Списков задач нет", symbol: "checklist", description: "Создайте список, чтобы добавлять задачи.", actionTitle: "Управлять списками") {
                    local.showTaskLists = true
                }
            } else if model.visibleTasks.isEmpty {
                WorkspaceEmptyState(title: emptyTitle,
                                    symbol: "checkmark.circle",
                                    description: emptyDescription,
                                    actionTitle: model.searchText.isEmpty ? nil : "Очистить поиск") {
                    model.searchText = ""
                }
            } else if model.taskFilter == .all {
                GeometryReader { geometry in
                    if TaskWorkspaceLayout.usesSingleColumn(availableWidth: Double(geometry.size.width)) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    ForEach(model.taskGroups(), id: \.0) { title, tasks in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(title).font(.headline)
                                                Spacer()
                                                Text("\(tasks.count)").font(.caption).foregroundStyle(AppTheme.textSecondary)
                                            }
                                            if tasks.isEmpty {
                                                Text("Пока пусто").font(.caption).foregroundStyle(AppTheme.textSecondary).padding(.vertical, 4)
                                            } else {
                                                ForEach(tasks) { TaskRowView(task: $0) }
                                            }
                                        }
                                    }
                                    .id(TaskWorkspaceLayout.topScrollAnchorID)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                            }
                            .scrollIndicators(.visible)
                            .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .top) }
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView([.horizontal, .vertical]) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(model.taskGroups(), id: \.0) { title, tasks in
                                        TaskColumn(title: title, tasks: tasks)
                                            .frame(minWidth: 230, idealWidth: max(230, geometry.size.width / 4 - 14), maxWidth: 360)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 4)
                                .id(TaskWorkspaceLayout.topScrollAnchorID)
                            }
                            .scrollIndicators(.visible)
                            .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .topLeading) }
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.visibleTasks) { task in TaskRowView(task: task) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .id(TaskWorkspaceLayout.topScrollAnchorID)
                    }
                    .scrollIndicators(.visible)
                    .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .top) }
                }
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $local.showingNewTask) {
            TaskEditorView(task: nil, taskListID: model.selectedTaskListID).environmentObject(model)
        }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView().environmentObject(model) }
        .onChange(of: model.newItemRequestID) { _ in
            guard model.section == .tasks, model.selectedTaskListID != nil else { return }
            local.showingNewTask = true
        }
        .accessibilityIdentifier("task-workspace")
    }

    private var tasksInSelectedList: [GoogleTask] {
        model.snapshot.tasks.filter {
            !$0.deleted && (model.selectedTaskListID == nil || $0.taskListID == model.selectedTaskListID)
        }
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return tasksInSelectedList.isEmpty ? "Задач нет" : "Ничего не найдено" }
        if tasksInSelectedList.isEmpty { return "В этом списке нет задач" }
        return "Нет задач по выбранному фильтру"
    }

    private var emptyDescription: String {
        if !model.searchText.isEmpty && !tasksInSelectedList.isEmpty { return "Измените запрос или очистите поиск." }
        if tasksInSelectedList.isEmpty { return "Создайте задачу или выберите другой список." }
        return "Выберите другой фильтр, чтобы увидеть задачи."
    }
}

private struct TaskColumn: View {
    let title: String
    let tasks: [GoogleTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(tasks.count)").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if tasks.isEmpty {
                Text("Пока пусто").font(.caption).foregroundStyle(AppTheme.textSecondary).padding(.vertical, 5)
            } else {
                ForEach(tasks) { TaskRowView(task: $0) }
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outline.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct TaskRowView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let task: GoogleTask
    @StateObject private var local = ViewLocalState()

    private var metadata: LocalTaskMetadata { model.metadataStore.metadata(for: task.id) }
    private var isOverdue: Bool { task.due.map { $0 < DateOnly(date: Date()) && !task.completed } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: toggleCompletion) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17)).foregroundStyle(task.completed ? AppTheme.textSecondary : AppTheme.task)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.completed ? "Вернуть задачу в работу" : "Завершить задачу")
                .accessibilityLabel(task.completed ? "Снять отметку выполнения: \(task.title)" : "Завершить задачу: \(task.title)")
                Button { local.showEditor = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).font(.callout).foregroundStyle(AppTheme.textPrimary).strikethrough(task.completed).lineLimit(3)
                        HStack(spacing: 7) {
                            Text(task.due?.description ?? "Без срока").font(.caption).foregroundStyle(isOverdue ? AppTheme.overdue : AppTheme.textSecondary)
                            if isOverdue {
                                Label("Просрочено", systemImage: "exclamationmark.circle.fill")
                                    .font(.caption2).foregroundStyle(AppTheme.overdue)
                            }
                            if let reminder = metadata.reminderAt {
                                Label(reminder.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                                    .font(.caption2).foregroundStyle(AppTheme.textSecondary).help("Локальное напоминание")
                            }
                            if metadata.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(AppTheme.warning).accessibilityLabel("Избранное на этом устройстве") }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть задачу: \(task.title), список \(model.snapshot.taskLists.first(where: { $0.id == task.taskListID })?.title ?? "неизвестен"), срок \(task.due?.description ?? "без срока"), \(task.completed ? "выполнена" : "не выполнена")")
                Menu {
                    Button("Редактировать…", systemImage: "pencil") { local.showEditor = true }
                    Button("Локальное напоминание…", systemImage: "bell") { local.showReminderEditor = true }
                    Button(metadata.favorite ? "Убрать из избранного" : "В избранное", systemImage: "star") { toggleFavorite() }
                    Divider()
                    Button("Удалить…", systemImage: "trash", role: .destructive) { local.showingDeleteConfirmation = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton)
                .help("Действия задачи")
            }
            if let message = local.localMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.overdue)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(10)
        .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.outline.opacity(0.38), lineWidth: 1))
        .sheet(isPresented: $local.showEditor) { TaskEditorView(task: task, taskListID: task.taskListID).environmentObject(model) }
        .sheet(isPresented: $local.showReminderEditor) { ReminderEditorView(task: task).environmentObject(model) }
        .confirmationDialog("Удалить задачу?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить задачу", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Подтвердите удаление задачи из Google Tasks.") }
        .disabled(model.mutationInFlight)
    }

    private func toggleCompletion() {
        do {
            let factory = try model.commandFactory()
            let invocation = try factory.taskPatch(task: task, title: task.title, notes: task.notes, due: task.due,
                                                   completed: !task.completed, authorization: .userCompletionToggle)
            local.localMessage = nil
            model.performMutation(invocation,
                                  onSuccess: { local.localMessage = nil },
                                  onFailure: { local.localMessage = $0 })
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить задачу." }
    }

    private func toggleFavorite() {
        let old = metadata
        do { try model.metadataStore.set(LocalTaskMetadata(reminderAt: old.reminderAt, favorite: !old.favorite), for: task.id) }
        catch { local.localMessage = "Локальное избранное не сохранено." }
    }

    private func delete() {
        do {
            let invocation = try model.commandFactory().taskDelete(task: task, authorization: .confirmedDelete)
            model.performMutation(invocation)
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось удалить задачу." }
    }
}
