import SwiftUI

/// The quiet macOS sidebar: fixed navigation and account, independently scrolling sources.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Binding var showTaskLists: Bool
    @Binding var showCalendars: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(WorkspaceViewModel.Section.allCases, id: \.self) { section in
                    navigationRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)

            separator
            sourceHeader

            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.section == .calendar {
                        ForEach(model.sortedCalendars) { calendar in calendarRow(calendar) }
                    } else {
                        taskRow(title: "Все доски", id: nil, color: AppTheme.accent)
                            .accessibilityIdentifier("sidebar-all-task-boards")
                        ForEach(model.orderedTaskLists) { list in
                            taskRow(title: list.title, id: list.id, color: boardColor(list.id))
                                .accessibilityIdentifier("sidebar-task-list-option")
                                .contextMenu {
                                    Button("Управлять списками…", systemImage: "slider.horizontal.3") { showTaskLists = true }
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("sidebar-sources")

            separator
            accountFooter
        }
        .background(AppTheme.canvas)
        .foregroundStyle(AppTheme.textPrimary)
        .accessibilityIdentifier("workspace-sidebar")
        .navigationTitle("g-calendar")
    }

    private var separator: some View {
        Divider().padding(.horizontal, 12).accessibilityHidden(true)
    }

    private func navigationRow(_ section: WorkspaceViewModel.Section) -> some View {
        let selected = model.section == section
        return SidebarButton(section == .tasks ? "section-tasks" : "section-calendar", action: { model.setSection(section) }) {
            HStack(spacing: 12) {
                Image(systemName: section == .calendar ? "calendar" : (selected ? "checkmark.square.fill" : "checkmark.square"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 22)
                Text(section.rawValue).font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(selected ? AppTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(section == .tasks ? "workspace-section-tasks" : "workspace-section-calendar")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sourceHeader: some View {
        HStack(spacing: 4) {
            Text(model.section == .calendar ? "Календари" : "Списки задач")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(model.section == .calendar ? "sidebar-calendar-selector" : "sidebar-task-list-selector")
            Spacer(minLength: 0)
            SidebarButton("manage", action: {
                if model.section == .calendar { showCalendars = true }
                else { showTaskLists = true }
            }) {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .accessibilityIdentifier("sidebar-manage-sources")
            .accessibilityLabel(model.section == .calendar ? "Создать календарь" : "Управлять списками задач")
            .help(model.section == .calendar ? "Создать календарь Google" : "Создать и управлять списками")
        }
        .padding(.leading, 20).padding(.trailing, 12)
        .padding(.top, 10).padding(.bottom, 6)
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        let selected = model.selectedCalendarID == calendar.id
        let visible = Binding(
            get: { model.isCalendarVisible(calendar.id) },
            set: { model.setCalendarVisible(calendar.id, isVisible: $0) }
        )
        return HStack(spacing: 0) {
            SidebarButton("calendar-\(calendar.id)", action: { model.selectedCalendarID = calendar.id }) {
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: calendar.colorHex) ?? AppTheme.event)
                        .frame(width: 10, height: 10).frame(width: 22)
                    Text(calendar.title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                    if !calendar.isWritable {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .help("Google предоставляет только просмотр этого календаря. Изменение событий недоступно и в Google Calendar.")
                    }
                }
                .padding(.leading, 12).padding(.trailing, 6)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("sidebar-calendar-\(calendar.id)")
            .accessibilityLabel("Выбрать календарь: \(calendar.title), \(calendar.isWritable ? "доступна запись" : "только просмотр")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help("\(calendar.title) — выбрать календарь для создания событий")

            Toggle("Показывать календарь \(calendar.title)", isOn: visible)
            .pointingHandCursor().labelsHidden().toggleStyle(.checkbox).controlSize(.small)
            .padding(.trailing, 12)
            .sidebarFrameProbe("visible-\(calendar.id)", action: { visible.wrappedValue.toggle() })
            .accessibilityIdentifier("sidebar-visible-\(calendar.id)")
            .accessibilityLabel("Показывать календарь \(calendar.title)")
        }
        .font(.system(size: 13, weight: selected ? .medium : .regular))
        .background(SidebarSourceSelection(selected: selected))
    }

    private func taskRow(title: String, id: String?, color: Color) -> some View {
        let selected = model.selectedTaskListID == id
        return SidebarButton("task-\(id ?? "all")", action: { model.selectedTaskListID = id }) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color).frame(width: 22)
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: selected ? .medium : .regular))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(SidebarSourceSelection(selected: selected))
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }

    private var accountFooter: some View {
        SidebarButton("account", action: openSettings) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.launchMode == .demo ? "Демо-пространство" : "Аккаунт Google")
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusTitle).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .sidebarFrameProbe("status-\(statusTitle)", action: {})
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sidebar-account-settings")
        .accessibilityLabel("Настройки аккаунта. \(statusTitle)")
        .help(model.statusMessage)
    }

    private var statusTitle: String {
        if model.pendingMutation != nil || model.mutationRecoveryProblem != nil { return "Нужна проверка записи" }
        if model.mutationInFlight { return "Сохранение…" }
        switch model.syncState {
        case .updated: return "Синхронизировано"
        case .syncing: return "Синхронизация…"
        case .stale: return "Сохранённые данные"
        case .offline: return "Нет подключения"
        case .failed: return "Ошибка синхронизации"
        case .setupRequired: return "Нужна настройка"
        case .idle: return "Ожидание синхронизации"
        }
    }

    private var statusColor: Color {
        if model.pendingMutation != nil || model.mutationRecoveryProblem != nil { return AppTheme.warning }
        if model.mutationInFlight { return AppTheme.accent }
        switch model.syncState {
        case .updated: return AppTheme.success
        case .syncing: return AppTheme.accent
        case .stale, .offline: return AppTheme.warning
        case .failed, .setupRequired: return AppTheme.overdue
        case .idle: return AppTheme.textSecondary
        }
    }

    private func boardColor(_ id: String) -> Color {
        // Stable by identity, so changing board order does not change its accent.
        let hash = id.utf8.reduce(UInt64(2166136261)) { ($0 ^ UInt64($1)) &* 16777619 }
        let colors = [AppTheme.accent, AppTheme.overdue, AppTheme.warning, AppTheme.success, AppTheme.task]
        return colors[Int(hash % UInt64(colors.count))]
    }
}

/// One action closure drives the native Button and the isolated fixture hook.
private struct SidebarButton<Label: View>: View {
    let identifier: String
    let action: () -> Void
    let label: Label

    init(_ identifier: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.identifier = identifier
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) { label }
            .pointingHandCursor().buttonStyle(.plain)
            .sidebarFrameProbe(identifier, action: action)
    }
}

private extension View {
    @ViewBuilder func sidebarFrameProbe(_ identifier: String, action: @escaping () -> Void) -> some View {
        #if G_CALENDAR_SIDEBAR_TEST
        background(SidebarFrameProbe(identifier: identifier, action: action).allowsHitTesting(false))
        #else
        self
        #endif
    }
}

private struct SidebarSourceSelection: View {
    let selected: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? AppTheme.selection.opacity(0.65) : .clear)
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(AppTheme.accent).frame(width: 3).padding(.vertical, 3) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
