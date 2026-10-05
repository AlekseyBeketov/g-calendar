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
                SyncStatusBar(onOpenSettings: { local.showSettings = true })
                if model.pendingMutation != nil || model.mutationRecoveryProblem != nil {
                    MutationRecoveryPanel()
                }
                Group {
                    if model.snapshot.fetchedAt == .distantPast && model.syncState == .syncing {
                        ProgressView("Загрузка календарей и задач…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.snapshot.fetchedAt == .distantPast && model.syncState == .setupRequired {
                        WorkspaceEmptyState(title: "Настройте подключение", symbol: "gearshape",
                                            description: model.statusMessage, actionTitle: "Открыть настройки") { local.showSettings = true }
                    } else if model.snapshot.fetchedAt == .distantPast && (model.syncState == .failed || model.syncState == .offline) {
                        WorkspaceEmptyState(title: model.syncState == .offline ? "Нет связи с Google" : "Данные не загружены",
                                            symbol: "exclamationmark.arrow.circlepath", description: model.statusMessage,
                                            actionTitle: "Повторить") { model.refresh() }
                    } else if model.section == .calendar { CalendarWorkspaceView() }
                    else { TaskWorkspaceView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.surface)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if model.section == .calendar {
                    Button { model.moveDate(-1) } label: { Image(systemName: "chevron.left") }.help("Назад · ⌘[").accessibilityLabel("Предыдущий период")
                    Button { model.goToToday() } label: { Text("Сегодня") }
                    Button { model.moveDate(1) } label: { Image(systemName: "chevron.right") }.help("Вперёд · ⌘]").accessibilityLabel("Следующий период")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
                        TextField(model.section == .calendar ? "Поиск событий" : "Поиск задач", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .onExitCommand { model.searchText = "" }
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
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? AppTheme.accent : AppTheme.outline.opacity(0.4), lineWidth: searchFocused ? 2 : 1))
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
        .tint(AppTheme.accent)
        .sheet(isPresented: $local.showSettings) { SettingsView() }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView() }
        .onChange(of: model.searchFocusRequestID) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.updateLocalDate()
            model.reconcileLocalReminders(trigger: .appActivation)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.updateLocalDate()
            model.reconcileLocalReminders(trigger: .systemWake)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in model.updateLocalDate(now: now) }
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
                            .padding(.horizontal, 8)
                            .frame(minHeight: 36)
                            .contentShape(.interaction, Rectangle())
                            .background(model.section == section ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(.interaction, Rectangle())
                                .background(model.selectedCalendarID == calendar.id ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                            Label(list.title, systemImage: "list.bullet")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(minHeight: 36)
                                .contentShape(.interaction, Rectangle())
                                .background(model.selectedTaskListID == list.id ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                        Button { showTaskLists = true } label: { Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Управлять списками задач").help("Создать и управлять списками")
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

    }

    private func sectionSymbol(_ section: WorkspaceViewModel.Section) -> String {
        switch section {
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        }
    }

}

struct SyncStatusBar: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(model.statusMessage).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(2)
                .help(model.statusMessage)
                .accessibilityLabel("Состояние синхронизации: \(model.statusMessage)")
                .accessibilityAddTraits(.updatesFrequently)
            if let date = model.cacheDateText {
                Text("· Кэш: \(date)").font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
            }
            Spacer()
            if model.cacheDateText != nil && [.stale, .offline, .failed].contains(model.syncState) {
                Label("Показаны сохранённые данные", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption).foregroundStyle(AppTheme.warning)
            }
            if model.syncState == .setupRequired {
                Button("Настройки", action: onOpenSettings)
            } else if [.stale, .offline, .failed].contains(model.syncState) {
                Button("Повторить") { model.refresh() }.disabled(model.mutationInFlight)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceRaised)
        .accessibilityElement(children: .contain)
    }

    private var color: Color {
        switch model.syncState {
        case .updated: return AppTheme.success
        case .syncing: return AppTheme.accent
        case .stale: return AppTheme.warning
        case .offline: return AppTheme.warning
        case .failed: return AppTheme.overdue
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
