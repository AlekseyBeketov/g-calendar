import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()

    var body: some View {
        NavigationSplitView(columnVisibility: $local.columnVisibility) {
            SidebarView(showTaskLists: $local.showTaskLists)
                .navigationSplitViewColumnWidth(min: 205, ideal: 245, max: 310)
        } detail: {
            GeometryReader { viewport in
            VStack(spacing: 0) {
                SyncStatusBar(onOpenSettings: { local.showSettings = true })
                    .fixedSize(horizontal: false, vertical: true)
                if model.pendingMutation != nil || model.mutationRecoveryProblem != nil {
                    MutationRecoveryPanel()
                        .fixedSize(horizontal: false, vertical: true)
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
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
            .clipped()
            }
            .background(AppTheme.surface)
            .toolbar {
                WorkspaceToolbar(isCalendar: model.section == .calendar,
                                 searchText: $model.searchText,
                                 focusRequest: model.searchFocusRequestID,
                                 searchFocused: $local.searchFocused,
                                 isSyncing: model.syncState == .syncing,
                                 mutationInFlight: model.mutationInFlight,
                                 moveDate: { model.moveDate($0) },
                                 goToToday: { model.goToToday() },
                                 refresh: { model.refresh() },
                                 openSettings: { DemoPerformanceProbe.shared.begin(.form); local.showSettings = true })
            }
        }
        .onChange(of: model.sidebarToggleRequestID) { _ in
            local.columnVisibility = local.columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.accent)
        .sheet(isPresented: $local.showSettings) { SettingsView() }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshMutationRecoveryState()
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
                    }.pointingHandCursor()
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(section == .tasks ? "workspace-section-tasks" : "workspace-section-calendar")
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }
            if model.section == .calendar {
                Section("Календари") {
                    ForEach(model.sortedCalendars) { calendar in
                        HStack(spacing: 4) {
                            Button { model.selectedCalendarID = calendar.id } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: calendar.colorHex) ?? AppTheme.event).frame(width: 9, height: 9)
                                    Text(calendar.title).lineLimit(1)
                                    Spacer(minLength: 2)
                                    if !calendar.isWritable { Image(systemName: "lock.fill").foregroundStyle(AppTheme.textSecondary).help("Google предоставляет только просмотр этого календаря. Изменение событий недоступно и в Google Calendar.") }
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(.interaction, Rectangle())
                                .background(model.selectedCalendarID == calendar.id ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }.pointingHandCursor()
                            .buttonStyle(.plain)
                            .accessibilityLabel("Выбрать календарь: \(calendar.title), \(calendar.isWritable ? "доступна запись" : "только просмотр")")
                            .accessibilityAddTraits(model.selectedCalendarID == calendar.id ? .isSelected : [])
                            .help("Выбрать календарь как контекст создания событий")

                            Toggle("Показывать календарь \(calendar.title)", isOn: Binding(
                                get: { model.isCalendarVisible(calendar.id) },
                                set: { model.setCalendarVisible(calendar.id, isVisible: $0) }
                            )).pointingHandCursor()
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .accessibilityLabel("Показывать календарь \(calendar.title)")
                        }
                    }
                }
            } else {
                Section {
                    Button { model.selectedTaskListID = nil } label: {
                        Label("Все доски", systemImage: "square.stack")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).frame(minHeight: 36)
                            .contentShape(.interaction, Rectangle())
                            .background(model.selectedTaskListID == nil ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }.pointingHandCursor().buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-all-task-boards")
                    .accessibilityAddTraits(model.selectedTaskListID == nil ? .isSelected : [])
                    ForEach(model.snapshot.taskLists) { list in
                        Button { model.selectedTaskListID = list.id } label: {
                            Label(list.title, systemImage: "list.bullet")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(minHeight: 36)
                                .contentShape(.interaction, Rectangle())
                                .background(model.selectedTaskListID == list.id ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.pointingHandCursor()
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
                        Button { showTaskLists = true } label: { Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle()) }.pointingHandCursor().buttonStyle(.plain).accessibilityLabel("Управлять списками задач").help("Создать и управлять списками")
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
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusMessage).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(2)
                    .help(model.statusMessage)
                    .accessibilityLabel("Состояние синхронизации: \(model.statusMessage)")
                    .accessibilityAddTraits(.updatesFrequently)
                if let date = model.cacheDateText {
                    Text("Кэш: \(date)").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1).help(date)
                }
                if model.cacheDateText != nil && [.stale, .offline, .failed].contains(model.syncState) {
                    Label("Показаны сохранённые данные", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption).foregroundStyle(AppTheme.warning)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.syncState == .setupRequired {
                Button("Настройки", action: onOpenSettings).pointingHandCursor()
            } else if [.stale, .offline, .failed].contains(model.syncState) {
                Button("Повторить") { model.refresh() }.pointingHandCursor().disabled(model.mutationInFlight)
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
