import SwiftUI

struct TaskWorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()
    @AppStorage("taskWorkspacePresentation") private var presentationRawValue = TaskWorkspacePresentation.defaultMode.rawValue

    var body: some View {
        GeometryReader { viewport in
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { listSelector; Spacer(minLength: 16); workspaceActions }
                    VStack(alignment: .leading, spacing: 12) { listSelector; workspaceActions }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(WorkspaceViewModel.TaskFilter.allCases, id: \.self) { filter in
                            Button { model.taskFilter = filter } label: {
                                Text(filter.rawValue).font(.callout.weight(.medium))
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .background(model.taskFilter == filter ? AppTheme.selection : AppTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(.interaction, Rectangle())
                            }.pointingHandCursor()
                            .buttonStyle(.plain)
                            .foregroundStyle(model.taskFilter == filter ? AppTheme.accent : AppTheme.textSecondary)
                            .accessibilityAddTraits(model.taskFilter == filter ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

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
            } else if usesBoardGroups || model.taskFilter == .all {
                GeometryReader { geometry in
                    let usesColumns = TaskWorkspaceLayout.usesColumnBoard(presentation: presentation, availableWidth: Double(geometry.size.width), selectedTaskListID: model.selectedTaskListID)
                    Group {
                        if !usesColumns {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 16) {
                                        ForEach(workspaceGroups.filter { !$0.tasks.isEmpty }) { group in
                                            let title = group.title
                                            let tasks = group.tasks
                                            VStack(alignment: .leading, spacing: 4) {
                                                Button {
                                                    if local.collapsedGroups.contains(group.id) { local.collapsedGroups.remove(group.id) }
                                                    else { local.collapsedGroups.insert(group.id) }
                                                } label: {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: local.collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down").font(.caption)
                                                        Text(title).font(.callout.weight(.semibold))
                                                        Text("\(tasks.count)").font(.caption).foregroundStyle(AppTheme.textSecondary)
                                                        Spacer()
                                                    }.frame(minHeight: 32).contentShape(.interaction, Rectangle())
                                                }.pointingHandCursor().buttonStyle(.plain).accessibilityLabel("\(title), \(tasks.count), \(local.collapsedGroups.contains(group.id) ? "свёрнуто" : "развёрнуто")")
                                                if !local.collapsedGroups.contains(group.id) {
                                                    LazyVStack(spacing: 0) { ForEach(tasks, id: \.selectionIdentity) { task in taskRow(task) } }
                                                }
                                            }
                                        }
                                        .id(TaskWorkspaceLayout.topScrollAnchorID)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                }
                                .scrollIndicators(.visible)
                                .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .top) }
                                .onChange(of: local.selectedTaskIdentity) { identity in
                                    if let identity { proxy.scrollTo(identity) }
                                }
                            }
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal) {
                                    HStack(alignment: .top, spacing: 16) {
                                        ForEach(boardGroups) { group in
                                            TaskColumn(title: group.board.title, tasks: group.tasks, selectedIdentity: local.selectedTaskIdentity,
                                                       keyboardFocused: local.taskKeyboardFocused,
                                                       onSelect: selectTask, onEditorDismiss: restoreTaskKeyboardFocus)
                                                .frame(width: CGFloat(TaskWorkspaceLayout.boardColumnWidth(availableWidth: Double(geometry.size.width), boardCount: boardGroups.count)),
                                                       height: max(120, geometry.size.height - 8))
                                                .id(group.id)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 4)
                                    .id(TaskWorkspaceLayout.topScrollAnchorID)
                                }
                                .scrollIndicators(.visible)
                                .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .topLeading) }
                                .onChange(of: local.selectedTaskIdentity) { identity in
                                    if let identity { proxy.scrollTo(identity.taskListID, anchor: .leading) }
                                }
                            }
                        }
                    }
                    .onAppear { local.taskColumnsVisible = usesColumns }
                    .onChange(of: usesColumns) { local.taskColumnsVisible = $0 }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visibleTasks, id: \.selectionIdentity) { task in taskRow(task) }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                        .id(TaskWorkspaceLayout.topScrollAnchorID)
                    }
                    .scrollIndicators(.visible)
                    .onAppear { proxy.scrollTo(TaskWorkspaceLayout.topScrollAnchorID, anchor: .top) }
                    .onChange(of: local.selectedTaskIdentity) { identity in
                        if let identity { proxy.scrollTo(identity) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
        }
        .background(TaskKeyboardFocusView(focusRequest: local.taskKeyboardFocusRequest,
                                         onFocusChange: taskKeyboardFocusChanged, onCommand: handleTaskKeyboardCommand))
        .sheet(isPresented: $local.showingNewTask) {
            TaskEditorView(task: nil, taskListID: model.selectedTaskListID).environmentObject(model)
        }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView().environmentObject(model) }
        .sheet(item: $local.keyboardTaskEditor, onDismiss: restoreTaskKeyboardFocus) { task in
            TaskEditorView(task: task, taskListID: task.taskListID).environmentObject(model)
        }
        .onAppear { reconcileTaskSelection() }
        .onChange(of: visibleTaskIdentities) { _ in reconcileTaskSelection() }
        .onChange(of: model.newItemRequestID) { _ in
            guard model.section == .tasks, !model.snapshot.taskLists.isEmpty else { return }
            local.showingNewTask = true
        }
        .accessibilityIdentifier("task-workspace")
    }

    private var listSelector: some View {
        Menu {
            Button { model.selectedTaskListID = nil } label: {
                if model.selectedTaskListID == nil { Label("Все доски", systemImage: "checkmark") }
                else { Text("Все доски") }
            }
            Divider()
            ForEach(model.snapshot.taskLists) { list in
                Button { model.selectedTaskListID = list.id } label: {
                    if model.selectedTaskListID == list.id { Label(list.title, systemImage: "checkmark") }
                    else { Text(list.title) }
                }
            }
            Divider()
            Button("Управлять списками…") { local.showTaskLists = true }
        } label: {
            Text(model.selectedTaskList?.title ?? "Все доски").font(.title2.weight(.semibold)).lineLimit(1)
        }.pointingHandCursor().menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Список задач: \(model.selectedTaskList?.title ?? "Все доски")")
    }

    private var workspaceActions: some View {
        HStack(spacing: 12) {
            if model.selectedTaskListID == nil {
                Picker("Представление задач", selection: $presentationRawValue) {
                    ForEach(TaskWorkspacePresentation.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.symbol).tag(mode.rawValue)
                    }
                }.pointingHandCursor().labelsHidden().pickerStyle(.menu).frame(width: 112)
                .accessibilityIdentifier("task-presentation-picker")
                .help("Колонки показывают доски. В узком окне доски отображаются вертикальным списком.")
            }
            Button { DemoPerformanceProbe.shared.begin(.form); local.showingNewTask = true } label: { Label("Создать", systemImage: "plus") }.pointingHandCursor()
                .buttonStyle(.borderedProminent).disabled(model.snapshot.taskLists.isEmpty || model.mutationsBlocked)
                .help("Создать задачу")
        }
    }

    private var presentation: TaskWorkspacePresentation {
        TaskWorkspacePresentation(rawValue: presentationRawValue) ?? .defaultMode
    }

    private var usesBoardGroups: Bool { model.selectedTaskListID == nil && presentation == .columns }
    private var boardGroups: [TaskBoardGroup] { TaskWorkspaceLayout.boardGroups(model.visibleTasks, lists: model.snapshot.taskLists) }
    private var workspaceGroups: [TaskPresentationGroup] {
        if usesBoardGroups { return boardGroups.map { TaskPresentationGroup(id: "board:" + $0.id, title: $0.board.title, tasks: $0.tasks) } }
        return model.taskGroups().map { TaskPresentationGroup(id: $0.0, title: $0.0, tasks: $0.1) }
    }

    private var keyboardVisibleTasks: [GoogleTask] {
        TaskKeyboardNavigation.visibleTasks(filteredTasks: model.visibleTasks, groups: workspaceGroups.map { ($0.id, $0.tasks) },
                                            usesGroups: usesBoardGroups || model.taskFilter == .all,
                                            usesColumns: usesBoardGroups && local.taskColumnsVisible,
                                            collapsedGroups: local.collapsedGroups)
    }

    private var visibleTaskIdentities: [TaskSelectionIdentity] { keyboardVisibleTasks.map(\.selectionIdentity) }

    private func taskRow(_ task: GoogleTask) -> some View {
        TaskRowView(task: task, selectedIdentity: local.selectedTaskIdentity,
                    keyboardFocused: local.taskKeyboardFocused,
                    onSelect: selectTask, onEditorDismiss: restoreTaskKeyboardFocus)
            .id(task.selectionIdentity)
    }

    private func selectTask(_ task: GoogleTask) { DemoPerformanceProbe.shared.begin(.selection); local.selectedTaskIdentity = task.selectionIdentity }

    private func reconcileTaskSelection() {
        let visible = visibleTaskIdentities
        local.selectedTaskIdentity = TaskKeyboardNavigation.reconciledSelection(local.selectedTaskIdentity,
                                                                                 previous: local.previousVisibleTaskIdentities,
                                                                                 visible: visible)
        local.previousVisibleTaskIdentities = visible
    }

    private func taskKeyboardFocusChanged(_ focused: Bool) {
        local.taskKeyboardFocused = focused
        if focused, local.selectedTaskIdentity == nil { local.selectedTaskIdentity = visibleTaskIdentities.first }
    }

    private func restoreTaskKeyboardFocus() { local.taskKeyboardFocusRequest = UUID() }

    private func handleTaskKeyboardCommand(_ command: TaskKeyboardCommand) {
        guard model.section == .tasks, !local.showingNewTask, !local.showTaskLists, local.keyboardTaskEditor == nil else { return }
        let tasks = keyboardVisibleTasks
        if command == .previous || command == .next {
            DemoPerformanceProbe.shared.begin(.selection)
            local.selectedTaskIdentity = TaskKeyboardNavigation.movedSelection(local.selectedTaskIdentity,
                                                                               in: tasks.map(\.selectionIdentity), command: command)
            return
        }
        guard let identity = local.selectedTaskIdentity,
              let task = tasks.first(where: { $0.selectionIdentity == identity }) else { return }
        if command == .edit { DemoPerformanceProbe.shared.begin(.form); local.keyboardTaskEditor = task; return }
        guard !model.mutationsBlocked else { return }
        DemoPerformanceProbe.shared.begin(.taskCompletion)
        do {
            let invocation = try model.commandFactory().taskPatch(task: task, title: task.title, notes: task.notes,
                                                                  due: task.due, completed: !task.completed,
                                                                  authorization: .userCompletionToggle)
            model.performMutation(invocation)
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить задачу." }
    }

    private var tasksInSelectedList: [GoogleTask] {
        model.snapshot.tasks.filter {
            !$0.deleted && (model.selectedTaskListID == nil || $0.taskListID == model.selectedTaskListID)
        }
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return tasksInSelectedList.isEmpty ? "Задач нет" : "Ничего не найдено" }
        if tasksInSelectedList.isEmpty { return model.selectedTaskListID == nil ? "На досках нет задач" : "В этой доске нет задач" }
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
    let selectedIdentity: TaskSelectionIdentity?
    let keyboardFocused: Bool
    let onSelect: (GoogleTask) -> Void
    let onEditorDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.headline).lineLimit(2)
                Spacer()
                Text("\(tasks.count)").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if tasks.isEmpty {
                            Text("Пока пусто").font(.caption).foregroundStyle(AppTheme.textSecondary).padding(.vertical, 5)
                        }
                        ForEach(tasks, id: \.selectionIdentity) { task in
                            TaskRowView(task: task, selectedIdentity: selectedIdentity, keyboardFocused: keyboardFocused,
                                        onSelect: onSelect, onEditorDismiss: onEditorDismiss, showsListTag: false)
                                .id(task.selectionIdentity)
                        }
                    }
                }.scrollIndicators(.visible)
                .onChange(of: selectedIdentity) { identity in
                    if let identity, tasks.contains(where: { $0.selectionIdentity == identity }) { proxy.scrollTo(identity) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outline.opacity(0.45), lineWidth: 1)
            .allowsHitTesting(false).accessibilityHidden(true))
        .accessibilityElement(children: .contain)
    }
}

private struct TaskPresentationGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [GoogleTask]
}

private struct TaskRowView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let task: GoogleTask
    let selectedIdentity: TaskSelectionIdentity?
    let keyboardFocused: Bool
    let onSelect: (GoogleTask) -> Void
    let onEditorDismiss: () -> Void
    var showsListTag = true
    @StateObject private var local = ViewLocalState()

    private var metadata: LocalTaskMetadata { model.metadataStore.metadata(for: task.id) }
    private var isOverdue: Bool { TaskWorkspaceLayout.isOverdue(task, today: model.localToday) }
    private var isSelected: Bool { selectedIdentity == task.selectionIdentity }


    private var listTitle: String { model.snapshot.taskLists.first { $0.id == task.taskListID }?.title ?? "Список" }
    private var dueColor: Color {
        if task.completed || task.due == nil { return AppTheme.textSecondary }
        if isOverdue { return AppTheme.overdue }
        return task.due == model.localToday ? AppTheme.warning : AppTheme.accent
    }
    private var dueText: String {
        guard let due = task.due, let date = due.startOfDay(in: .current) else { return "Без срока" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
    }

    private var metadataAccessibilityValue: String {
        var descriptions: [String] = []
        if task.notes?.isEmpty == false { descriptions.append("Есть заметки") }
        if metadata.favorite { descriptions.append("Локальное избранное") }
        if let reminder = metadata.reminderAt {
            descriptions.append("Локальное напоминание: \(reminder.formatted(date: .abbreviated, time: .shortened))")
        }
        return descriptions.joined(separator: "; ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Button(action: toggleCompletion) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16)).foregroundStyle(task.completed ? AppTheme.success : AppTheme.textSecondary)
                        .frame(width: 44, height: 44).contentShape(.interaction, Rectangle())
                }.pointingHandCursor().buttonStyle(.plain).disabled(model.mutationsBlocked)
                .help(task.completed ? "Вернуть задачу в работу" : "Завершить задачу")
                .accessibilityLabel(task.completed ? "Снять отметку выполнения: \(task.title)" : "Завершить задачу: \(task.title)")
                Button { onSelect(task); local.showEditor = true } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { taskTitle.frame(minWidth: 160, maxWidth: .infinity, alignment: .leading); taskMetadata }
                        VStack(alignment: .leading, spacing: 6) { taskTitle; taskMetadata }
                            .padding(.vertical, 6)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.interaction, Rectangle())
                }.pointingHandCursor().buttonStyle(.plain)
                .accessibilityLabel("Открыть задачу: \(task.title), список \(listTitle), срок \(dueText), \(isOverdue ? "просрочена, " : "")\(task.completed ? "выполнена" : "не выполнена")")
                .accessibilityValue(metadataAccessibilityValue)
                Menu {
                    Button("Редактировать…", systemImage: "pencil") { onSelect(task); local.showEditor = true }
                    Button("Локальное напоминание…", systemImage: "bell") { local.showReminderEditor = true }
                    Button(metadata.favorite ? "Убрать из избранного" : "В избранное", systemImage: "star") { toggleFavorite() }
                    Divider()
                    Button("Удалить…", systemImage: "trash", role: .destructive) { local.showingDeleteConfirmation = true }.disabled(model.mutationsBlocked)
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44).contentShape(Rectangle()) }.pointingHandCursor()
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Действия задачи: \(task.title)")
                .help("Действия задачи")
            }
            if let message = local.localMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption)
                    .foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44).padding(.bottom, 8).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, 4)
        .background(isSelected || local.isHovered || local.showEditor ? AppTheme.selection.opacity(0.65) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected && keyboardFocused {
                RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent, lineWidth: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected || local.showEditor {
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.accent).frame(width: 3).padding(.vertical, 6)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.outline.opacity(0.12)).frame(height: 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .onHover { local.isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sheet(isPresented: $local.showEditor, onDismiss: onEditorDismiss) { TaskEditorView(task: task, taskListID: task.taskListID).environmentObject(model) }
        .sheet(isPresented: $local.showReminderEditor) { ReminderEditorView(task: task).environmentObject(model) }
        .confirmationDialog("Удалить задачу?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить задачу", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) { }
        } message: { Text(model.launchMode == .demo ? "Будет удалена только тестовая задача в демо-режиме." : "Подтвердите удаление задачи из Google Tasks.") }
    }

    private var taskTitle: some View {
        HStack(spacing: 6) {
            Text(task.title).font(.body).foregroundStyle(AppTheme.textPrimary).strikethrough(task.completed).lineLimit(2)
            if task.notes?.isEmpty == false { Image(systemName: "text.alignleft").font(.caption2).foregroundStyle(AppTheme.textSecondary).help("Есть заметки") }
            if metadata.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(AppTheme.warning).accessibilityLabel("Локальное избранное") }
            if let reminder = metadata.reminderAt {
                Image(systemName: "bell").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    .help("Локальное напоминание: \(reminder.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    private var taskMetadata: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                if isOverdue {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(dueColor)
                        .accessibilityLabel("Просрочено")
                } else if task.due != nil { Circle().fill(dueColor).frame(width: 5, height: 5) }
                Text(dueText).font(.callout).foregroundStyle(dueColor)
            }.frame(width: 82, alignment: .leading)
            .help(isOverdue ? "Просрочено" : "Срок задачи — дата без времени")
            if showsListTag {
                Text(listTitle).font(.callout).foregroundStyle(AppTheme.accent).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: 150, alignment: .leading)
                    .background(AppTheme.selection.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func toggleCompletion() {
        DemoPerformanceProbe.shared.begin(.taskCompletion)
        onSelect(task)
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
        do { try model.metadataStore.set(LocalTaskMetadata(reminderAt: old.reminderAt, favorite: !old.favorite), for: task.id); model.objectWillChange.send() }
        catch { local.localMessage = "Локальное избранное не сохранено." }
    }

    private func delete() {
        do {
            let invocation = try model.commandFactory().taskDelete(task: task, authorization: .confirmedDelete)
            model.performMutation(invocation)
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось удалить задачу." }
    }
}
