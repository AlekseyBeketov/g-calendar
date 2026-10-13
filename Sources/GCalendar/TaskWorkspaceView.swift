import SwiftUI
import UniformTypeIdentifiers

struct TaskWorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var local = ViewLocalState()
    @AppStorage("taskWorkspacePresentation") private var presentationRawValue = TaskWorkspacePresentation.defaultMode.rawValue
    @StateObject private var interaction = TaskWorkspaceInteraction()

    private var presentation: TaskWorkspacePresentation {
        TaskWorkspacePresentation(rawValue: presentationRawValue) ?? .defaultMode
    }
    private var boardGroups: [TaskBoardGroup] {
        let lists = model.orderedTaskLists.filter { model.selectedTaskListID == nil || $0.id == model.selectedTaskListID }
        return TaskWorkspaceLayout.boardGroups(model.visibleTasks, lists: lists).map {
            TaskBoardGroup(board: $0.board, tasks: TaskOrdering.sorted($0.tasks, mode: model.taskSortMode(for: $0.id)))
        }
    }
    private var keyboardVisibleTasks: [GoogleTask] {
        boardGroups.filter { local.taskColumnsVisible || !local.collapsedGroups.contains("board:" + $0.id) }.flatMap(\.tasks)
    }
    private var visibleTaskIdentities: [TaskSelectionIdentity] { keyboardVisibleTasks.map(\.selectionIdentity) }

    var body: some View {
        GeometryReader { viewport in
            VStack(spacing: 16) {
                workspaceHeader
                if model.snapshot.taskLists.isEmpty {
                    WorkspaceEmptyState(title: "Списков задач нет", symbol: "checklist", description: "Создайте список, чтобы добавлять задачи.", actionTitle: "Управлять списками") { local.showTaskLists = true }
                } else {
                    taskBoards
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
        }
        .background(TaskKeyboardFocusView(focusRequest: local.taskKeyboardFocusRequest, onFocusChange: taskKeyboardFocusChanged, onCommand: handleTaskKeyboardCommand))
        .sheet(isPresented: $local.showingNewTask, onDismiss: { local.newTaskBoardID = nil }) {
            TaskEditorView(task: nil, taskListID: local.newTaskBoardID).environmentObject(model)
        }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView().environmentObject(model) }
        .sheet(item: $local.keyboardTaskEditor, onDismiss: restoreTaskKeyboardFocus) { task in
            TaskEditorView(task: task, taskListID: task.taskListID).environmentObject(model)
        }
        .onAppear { reconcileTaskSelection() }
        .onChange(of: visibleTaskIdentities) { _ in reconcileTaskSelection() }
        .onChange(of: model.newItemRequestID) { _ in
            guard model.section == .tasks, !model.snapshot.taskLists.isEmpty else { return }
            beginNewTask(on: model.selectedTaskListID)
        }
        .accessibilityIdentifier("task-workspace")
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { listSelector; Spacer(minLength: 16); workspaceActions }
                VStack(alignment: .leading, spacing: 12) { listSelector; workspaceActions }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(WorkspaceViewModel.TaskFilter.allCases, id: \.self) { filter in
                        Button { model.taskFilter = filter } label: {
                            Text(filter.rawValue).font(.callout.weight(.medium)).padding(.horizontal, 12).frame(height: 32)
                                .background(model.taskFilter == filter ? AppTheme.selection : AppTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(.interaction, Rectangle())
                        }.pointingHandCursor().buttonStyle(.plain)
                        .foregroundStyle(model.taskFilter == filter ? AppTheme.accent : AppTheme.textSecondary)
                        .accessibilityAddTraits(model.taskFilter == filter ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 24).padding(.top, 16)
    }

    private var taskBoards: some View {
        GeometryReader { geometry in
            let columns = TaskWorkspaceLayout.usesColumnBoard(presentation: presentation, availableWidth: Double(geometry.size.width), selectedTaskListID: model.selectedTaskListID)
            let width = CGFloat(TaskWorkspaceLayout.boardColumnWidth(availableWidth: Double(geometry.size.width), boardCount: boardGroups.count))
            ScrollViewReader { proxy in
                ScrollView(columns ? .horizontal : .vertical) {
                    if columns {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(boardGroups) { group in
                                TaskBoardView(group: group, selectedIdentity: local.selectedTaskIdentity, keyboardFocused: local.taskKeyboardFocused,
                                              draggedTask: $interaction.draggedTask, draggedBoard: $interaction.draggedBoard,
                                              onSelect: selectTask, onEditorDismiss: restoreTaskKeyboardFocus,
                                              onAddTask: { beginNewTask(on: group.id) })
                                    .frame(width: width, height: max(120, geometry.size.height - 8)).id(group.id)
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 4)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(boardGroups) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Button {
                                            let id = "board:" + group.id
                                            if local.collapsedGroups.contains(id) { local.collapsedGroups.remove(id) }
                                            else { local.collapsedGroups.insert(id) }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: local.collapsedGroups.contains("board:" + group.id) ? "chevron.right" : "chevron.down").font(.caption)
                                                Text(group.board.title).font(.callout.weight(.semibold))
                                                Text("\(group.tasks.count)").font(.caption).foregroundStyle(AppTheme.textSecondary)
                                                Spacer()
                                            }.frame(minHeight: 32).contentShape(Rectangle())
                                        }.pointingHandCursor().buttonStyle(.plain)
                                        .accessibilityLabel("\(group.board.title), \(group.tasks.count), \(local.collapsedGroups.contains("board:" + group.id) ? "свёрнуто" : "развёрнуто")")
                                        TaskBoardMenu(board: group.board)
                                    }
                                    TaskBoardAddButton(board: group.board) { beginNewTask(on: group.id) }
                                    if !local.collapsedGroups.contains("board:" + group.id) {
                                        TaskBoardRows(boardID: group.id, tasks: group.tasks, selectedIdentity: local.selectedTaskIdentity, keyboardFocused: local.taskKeyboardFocused,
                                                      draggedTask: $interaction.draggedTask, onSelect: selectTask, onEditorDismiss: restoreTaskKeyboardFocus)
                                    }
                                }.id(group.id)
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                }
                .scrollIndicators(.visible)
                .onChange(of: local.selectedTaskIdentity) { identity in
                    if let identity {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                            if columns { proxy.scrollTo(identity.taskListID, anchor: .leading) }
                            else { proxy.scrollTo(identity) }
                        }
                    }
                }
                .onAppear { local.taskColumnsVisible = columns }
                .onChange(of: columns) { local.taskColumnsVisible = $0 }
            }
        }
    }

    private var listSelector: some View {
        Menu {
            Button { model.selectedTaskListID = nil } label: {
                if model.selectedTaskListID == nil { Label("Все доски", systemImage: "checkmark") } else { Text("Все доски") }
            }
            Divider()
            ForEach(model.orderedTaskLists) { list in
                Button { model.selectedTaskListID = list.id } label: {
                    if model.selectedTaskListID == list.id { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                }
            }
            Divider()
            Button("Управлять списками…") { local.showTaskLists = true }
        } label: { Text(model.selectedTaskList?.title ?? "Все доски").font(.title2.weight(.semibold)).lineLimit(1) }
        .pointingHandCursor().menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Список задач: \(model.selectedTaskList?.title ?? "Все доски")")
    }

    private var workspaceActions: some View {
        HStack(spacing: 12) {
            if model.selectedTaskListID == nil {
                Picker("Представление задач", selection: $presentationRawValue) {
                    ForEach(TaskWorkspacePresentation.allCases, id: \.self) { mode in Label(mode.rawValue, systemImage: mode.symbol).tag(mode.rawValue) }
                }.pointingHandCursor().labelsHidden().pickerStyle(.menu).frame(width: 112)
                .accessibilityIdentifier("task-presentation-picker")
            }
            TaskBoardMenu(board: model.selectedTaskList)
            Button { beginNewTask(on: model.selectedTaskListID) } label: { Label("Создать", systemImage: "plus") }
                .pointingHandCursor().buttonStyle(.borderedProminent).disabled(model.snapshot.taskLists.isEmpty || model.mutationsBlocked).help("Создать задачу")
        }
    }

    private func selectTask(_ task: GoogleTask) { DemoPerformanceProbe.shared.begin(.selection); local.selectedTaskIdentity = task.selectionIdentity }
    private func beginNewTask(on boardID: String?) {
        guard !model.mutationsBlocked, !model.snapshot.taskLists.isEmpty,
              boardID == nil || model.snapshot.taskLists.contains(where: { $0.id == boardID }) else { return }
        DemoPerformanceProbe.shared.begin(.form)
        local.newTaskBoardID = boardID
        local.showingNewTask = true
    }
    private func reconcileTaskSelection() {
        let visible = visibleTaskIdentities
        local.selectedTaskIdentity = TaskKeyboardNavigation.reconciledSelection(local.selectedTaskIdentity, previous: local.previousVisibleTaskIdentities, visible: visible)
        local.previousVisibleTaskIdentities = visible
    }
    private func taskKeyboardFocusChanged(_ focused: Bool) {
        local.taskKeyboardFocused = focused
        if focused, local.selectedTaskIdentity == nil { local.selectedTaskIdentity = visibleTaskIdentities.first }
    }
    private func restoreTaskKeyboardFocus() { local.taskKeyboardFocusRequest = UUID() }
    private func handleTaskKeyboardCommand(_ command: TaskKeyboardCommand) {
        let tasks = keyboardVisibleTasks
        if command == .previous || command == .next {
            DemoPerformanceProbe.shared.begin(.selection)
            local.selectedTaskIdentity = TaskKeyboardNavigation.movedSelection(local.selectedTaskIdentity, in: tasks.map(\.selectionIdentity), command: command)
            return
        }
        guard let identity = local.selectedTaskIdentity, let task = tasks.first(where: { $0.selectionIdentity == identity }) else { return }
        if command == .edit { DemoPerformanceProbe.shared.begin(.form); local.keyboardTaskEditor = task; return }
        guard !model.mutationsBlocked else { return }
        do {
            let invocation = try model.commandFactory().taskPatch(task: task, title: task.title, notes: task.notes, due: task.due,
                                                                  completed: !task.completed, authorization: .userCompletionToggle)
            model.performMutation(invocation)
        } catch { model.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить задачу." }
    }
}

private struct TaskBoardMenu: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let board: TaskList?
    var allowsBoardReordering = false
    @StateObject private var interaction = TaskWorkspaceInteraction()

    private var completedTasks: [GoogleTask] {
        model.snapshot.tasks.filter { $0.completed && !$0.deleted && (board == nil || $0.taskListID == board?.id) }
    }
    private var chosenMode: TaskSortMode? {
        if let board { return model.taskSortMode(for: board.id) }
        let modes = Set(model.snapshot.taskLists.map { model.taskSortMode(for: $0.id) })
        return modes.count == 1 ? modes.first : nil
    }
    var body: some View {
        Menu {
            Text(board == nil ? "Сортировать все доски" : "Сортировать")
            ForEach(TaskSortMode.allCases, id: \.self) { mode in
                Button { model.setTaskSortMode(mode, for: board?.id) } label: {
                    if chosenMode == mode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                }
            }
            Divider()
            if allowsBoardReordering, let board {
                Button("Переместить доску левее", systemImage: "arrow.left") { model.shiftTaskBoard(board.id, direction: -1) }
                    .disabled(!model.canShiftTaskBoard(board.id, direction: -1))
                Button("Переместить доску правее", systemImage: "arrow.right") { model.shiftTaskBoard(board.id, direction: 1) }
                    .disabled(!model.canShiftTaskBoard(board.id, direction: 1))
                Divider()
            }
            Button("Удалить выполненные…", role: .destructive) {
                interaction.confirmedTasks = completedTasks
                interaction.showingDelete = true
            }.disabled(completedTasks.isEmpty || model.mutationsBlocked)
        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle()) }
        .pointingHandCursor().menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Настройки задач: \(board?.title ?? "Все доски")").help("Сортировка и выполненные задачи")
        .alert("Удалить выполненные задачи?", isPresented: $interaction.showingDelete) {
            Button("Отмена", role: .cancel) { interaction.confirmedTasks = [] }
            Button("Удалить", role: .destructive) { model.deleteCompletedTasks(interaction.confirmedTasks); interaction.confirmedTasks = [] }
        } message: { Text("\(board?.title ?? "Все доски"): \(interaction.confirmedTasks.count) задач. Они будут удалены из Google. Поиск и фильтр не ограничивают этот набор.") }
    }
}

private struct TaskDragSession {
    let token = UUID().uuidString
    let task: GoogleTask
}

private struct TaskBoardDragSession {
    let token = UUID().uuidString
    let boardID: String
}

private final class TaskWorkspaceInteraction: ObservableObject {
    @Published var draggedTask: TaskDragSession?
    @Published var draggedBoard: TaskBoardDragSession?
    @Published var isDropTargeted = false
    @Published var confirmedTasks: [GoogleTask] = []
    @Published var showingDelete = false
}

private struct TaskBoardView: View {
    let group: TaskBoardGroup
    let selectedIdentity: TaskSelectionIdentity?
    let keyboardFocused: Bool
    @Binding var draggedTask: TaskDragSession?
    @Binding var draggedBoard: TaskBoardDragSession?
    let onSelect: (GoogleTask) -> Void
    let onEditorDismiss: () -> Void
    let onAddTask: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TaskBoardHeader(board: group.board, taskCount: group.tasks.count, draggedBoard: $draggedBoard)
            TaskBoardAddButton(board: group.board, action: onAddTask)
            ScrollViewReader { proxy in
                ScrollView {
                    TaskBoardRows(boardID: group.id, tasks: group.tasks, selectedIdentity: selectedIdentity, keyboardFocused: keyboardFocused,
                                  draggedTask: $draggedTask, onSelect: onSelect, onEditorDismiss: onEditorDismiss)
                }.scrollIndicators(.visible)
                .onChange(of: selectedIdentity) { identity in
                    if let identity, group.tasks.contains(where: { $0.selectionIdentity == identity }) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { proxy.scrollTo(identity) }
                    }
                }
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outline.opacity(0.45), lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true))
        .accessibilityElement(children: .contain)
    }
}

private struct TaskBoardAddButton: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let board: TaskList
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Добавить задачу", systemImage: "plus.circle")
                .font(.callout.weight(.medium)).foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 8).contentShape(Rectangle())
        }.pointingHandCursor().buttonStyle(.plain).disabled(model.mutationsBlocked)
        .accessibilityLabel("Добавить задачу в доску: \(board.title)")
        .help("Создать задачу в доске «\(board.title)»")
    }
}

private struct TaskBoardHeader: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let board: TaskList
    let taskCount: Int
    @Binding var draggedBoard: TaskBoardDragSession?
    @StateObject private var interaction = TaskWorkspaceInteraction()

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(AppTheme.textSecondary).accessibilityHidden(true)
                Text(board.title).font(.headline).lineLimit(2)
                Spacer()
                Text("\(taskCount)").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.vertical, 4).contentShape(Rectangle())
            .background(interaction.isDropTargeted ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .pointingHandCursor().help("Перетащите заголовок, чтобы изменить порядок досок")
            .onDrag {
                let session = TaskBoardDragSession(boardID: board.id)
                draggedBoard = session
                return NSItemProvider(object: ("g-calendar-board:" + session.token) as NSString)
            }
            .onDrop(of: [UTType.plainText], isTargeted: $interaction.isDropTargeted) { providers in
                guard let session = draggedBoard, session.boardID != board.id,
                      let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
                provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let value = value as? String, value == "g-calendar-board:" + session.token else { return }
                    DispatchQueue.main.async {
                        guard draggedBoard?.token == session.token else { return }
                        draggedBoard = nil
                        model.moveTaskBoard(session.boardID, toward: board.id)
                    }
                }
                return true
            }
            TaskBoardMenu(board: board, allowsBoardReordering: true)
        }
    }
}

private struct TaskBoardRows: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let boardID: String
    let tasks: [GoogleTask]
    let selectedIdentity: TaskSelectionIdentity?
    let keyboardFocused: Bool
    @Binding var draggedTask: TaskDragSession?
    let onSelect: (GoogleTask) -> Void
    let onEditorDismiss: () -> Void
    var body: some View {
        let firstCompleted = tasks.first(where: { $0.completed })?.selectionIdentity
        LazyVStack(alignment: .leading, spacing: 0) {
            if tasks.isEmpty {
                Text(emptyMessage).font(.caption).foregroundStyle(AppTheme.textSecondary).padding(.horizontal, 8).padding(.vertical, 8)
                if !model.searchText.isEmpty {
                    Button("Очистить поиск") { model.searchText = "" }.pointingHandCursor().buttonStyle(.link).padding(.horizontal, 8)
                }
            }
            if model.taskSortMode(for: boardID) == .date {
                let groups = TaskOrdering.dateGroups(tasks, today: model.localToday)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(group.title).font(.callout.weight(.semibold))
                            .foregroundStyle(group.isOverdue ? AppTheme.overdue : group.isToday ? AppTheme.accent : AppTheme.textSecondary)
                            .padding(.leading, 8).padding(.top, index == 0 ? 4 : 18).padding(.bottom, 6)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.tasks, id: \.selectionIdentity) { task in draggableRow(task) }
                    }
                }
            } else {
                ForEach(tasks, id: \.selectionIdentity) { task in
                    if task.completed && firstCompleted == task.selectionIdentity {
                        Text("Готово").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary).padding(.top, 12).padding(.bottom, 4)
                    }
                    draggableRow(task)
                }
            }
        }
    }
    private var emptyMessage: String {
        if !model.searchText.isEmpty { return "Ничего не найдено" }
        return model.snapshot.tasks.contains(where: { $0.taskListID == boardID && !$0.deleted }) ? "Нет задач по этому фильтру" : "Пока пусто"
    }
    @ViewBuilder private func draggableRow(_ task: GoogleTask) -> some View {
        let row = TaskRowView(task: task, selectedIdentity: selectedIdentity, keyboardFocused: keyboardFocused,
                              onSelect: onSelect, onEditorDismiss: onEditorDismiss, showsListTag: false).id(task.selectionIdentity)
        if model.taskSortMode(for: task.taskListID) == .manual && !task.completed && !model.mutationsBlocked {
            row.onDrag {
                let session = TaskDragSession(task: task)
                draggedTask = session
                return NSItemProvider(object: ("g-calendar-task:" + session.token) as NSString)
            }.onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                guard let session = draggedTask, session.task.taskListID == task.taskListID,
                      session.task.parent == task.parent, session.task.id != task.id,
                      let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
                provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let value = value as? String, value == "g-calendar-task:" + session.token else { return }
                    DispatchQueue.main.async {
                        guard draggedTask?.token == session.token else { return }
                        draggedTask = nil
                        model.reorderTask(session.task, before: task)
                    }
                }
                return true
            }
        } else { row }
    }
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
                    if model.taskSortMode(for: task.taskListID) == .manual && !task.completed {
                        Divider()
                        Button("Переместить выше", systemImage: "arrow.up") { model.shiftTask(task, direction: -1) }
                            .disabled(!model.canShiftTask(task, direction: -1))
                        Button("Переместить ниже", systemImage: "arrow.down") { model.shiftTask(task, direction: 1) }
                            .disabled(!model.canShiftTask(task, direction: 1))
                    }
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
