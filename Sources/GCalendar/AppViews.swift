import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $local.columnVisibility) {
            SidebarView(showTaskLists: $local.showTaskLists)
                .navigationSplitViewColumnWidth(min: 205, ideal: 245, max: 310)
        } detail: {
            VStack(spacing: 0) {
                SyncStatusBar()
                Group {
                    if model.section == .calendar { CalendarWorkspaceView() }
                    else { TaskWorkspaceView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.canvas)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button { model.moveDate(-1) } label: { Image(systemName: "chevron.left") }.help("Назад")
                    Button { model.goToToday() } label: { Text("Сегодня") }
                    Button { model.moveDate(1) } label: { Image(systemName: "chevron.right") }.help("Вперёд")
                }
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
                        TextField(model.section == .calendar ? "Поиск событий" : "Поиск задач", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .frame(width: 180)
                            .accessibilityLabel(model.section == .calendar ? "Поиск событий" : "Поиск задач")
                            .accessibilityIdentifier("workspace-search-field")
                        if !model.searchText.isEmpty {
                            Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Очистить поиск")
                                .help("Очистить поиск")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.refresh() } label: {
                        if model.syncState == .syncing { ProgressView().controlSize(.small) }
                        else { Label("Синхронизировать", systemImage: "arrow.clockwise") }
                    }
                    .disabled(model.syncState == .syncing || model.mutationInFlight)
                    .help("Обновить Calendar и Tasks")
                }
                ToolbarItem(placement: .automatic) {
                    Button { local.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Настройки")
                        .help("Настройки")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $local.showSettings) { SettingsView() }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView() }
        .onChange(of: model.searchFocusRequestID) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reconcileLocalReminders(trigger: .appActivation)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.reconcileLocalReminders(trigger: .systemWake)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Binding var showTaskLists: Bool

    var body: some View {
        List {
            Section("Пространство") {
                ForEach(WorkspaceViewModel.Section.allCases, id: \.self) { section in
                    Button {
                        model.setSection(section)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: sectionSymbol(section))
                            Text(section.rawValue)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .background(model.section == section ? AppTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(section == .tasks ? "workspace-section-tasks" : "workspace-section-calendar")
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }
            if model.section == .calendar {
                Section("Календари") {
                    ForEach(model.snapshot.calendars) { calendar in
                        HStack(spacing: 4) {
                            Button { model.selectedCalendarID = calendar.id } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: calendar.colorHex) ?? AppTheme.event).frame(width: 9, height: 9)
                                    Text(calendar.title).lineLimit(1)
                                    Spacer(minLength: 2)
                                    if !calendar.isWritable { Image(systemName: "lock.fill").foregroundStyle(AppTheme.textSecondary).help("Только просмотр") }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .background(model.selectedCalendarID == calendar.id ? AppTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Выбрать календарь: \(calendar.title), \(calendar.isWritable ? "доступна запись" : "только просмотр")")
                            .accessibilityAddTraits(model.selectedCalendarID == calendar.id ? .isSelected : [])
                            .help("Выбрать календарь как контекст создания событий")

                            Toggle("Показывать календарь \(calendar.title)", isOn: Binding(
                                get: { model.isCalendarVisible(calendar.id) },
                                set: { model.setCalendarVisible(calendar.id, isVisible: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .accessibilityLabel("Показывать календарь \(calendar.title)")
                        }
                    }
                }
            } else {
                Section {
                    ForEach(model.snapshot.taskLists) { list in
                        Button { model.selectedTaskListID = list.id } label: {
                            Label(list.title, systemImage: model.selectedTaskListID == list.id ? "checkmark.circle.fill" : "circle")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                                .background(model.selectedTaskListID == list.id ? AppTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar-task-list-option")
                        .accessibilityAddTraits(model.selectedTaskListID == list.id ? .isSelected : [])
                        .contextMenu {
                            Button("Управлять списками…", systemImage: "slider.horizontal.3") { showTaskLists = true }
                        }
                    }
                } header: {
                    HStack {
                        Text("Списки задач").accessibilityIdentifier("sidebar-task-list-selector")
                        Spacer()
                        Button { showTaskLists = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Создать и управлять списками")
                    }
                }
                Section("Фильтры") {
                    ForEach(WorkspaceViewModel.TaskFilter.allCases, id: \.self) { filter in
                        Button { model.taskFilter = filter } label: {
                            Label(filter.rawValue, systemImage: filterSymbol(filter))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .background(model.taskFilter == filter ? AppTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.taskFilter == filter ? .isSelected : [])
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppTheme.surface)
        .foregroundStyle(AppTheme.textPrimary)
        .accessibilityIdentifier("workspace-sidebar")
        .navigationTitle("g-calendar")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Google Tasks: срок — дата без времени").font(.caption2)
                Text("Локальные напоминания не синхронизируются").font(.caption2)
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(12)
        }
    }

    private func sectionSymbol(_ section: WorkspaceViewModel.Section) -> String {
        switch section {
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        }
    }

    private func filterSymbol(_ filter: WorkspaceViewModel.TaskFilter) -> String {
        switch filter { case .all: return "list.bullet"; case .today: return "sun.max"; case .upcoming: return "calendar.badge.clock"; case .overdue: return "exclamationmark.circle" }
    }
}

struct SyncStatusBar: View {
    @EnvironmentObject private var model: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(model.statusMessage).font(.callout).foregroundStyle(AppTheme.textPrimary).lineLimit(1)
            if let date = model.cacheDateText {
                Text("· Кэш: \(date)").font(.callout).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
            }
            Spacer()
            if model.syncState == .stale {
                Label("Показаны сохранённые данные", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption).foregroundStyle(AppTheme.warning)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(AppTheme.surfaceRaised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Состояние синхронизации: \(model.statusMessage)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var color: Color {
        switch model.syncState {
        case .updated: return AppTheme.success
        case .syncing: return AppTheme.accent
        case .stale: return AppTheme.warning
        case .setupRequired: return AppTheme.overdue
        case .idle: return AppTheme.textSecondary
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt64(value, radix: 16) else { return nil }
        let red, green, blue: Double
        if value.count == 6 {
            red = Double((number >> 16) & 0xff) / 255
            green = Double((number >> 8) & 0xff) / 255
            blue = Double(number & 0xff) / 255
        } else { return nil }
        self.init(red: red, green: green, blue: blue)
    }
}
