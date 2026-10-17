import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()

    var body: some View {
        Group {
            if model.requiresGoogleOnboarding {
                GoogleOnboardingView(
                    isSigningIn: model.googleTransportSettings.signingIn,
                    canSignIn: model.googleTransportSettings.canStartSignIn,
                    statusMessage: onboardingStatusMessage,
                    errorMessage: model.googleTransportSettings.signInError,
                    onSignIn: { model.signInToGoogle() },
                    onCancel: { model.googleTransportSettings.cancelSignIn() },
                    onOpenSettings: { local.showSettings = true }
                )
            } else if model.requiresStartupPreferences {
                StartupPreferencesView(updates: model.applicationUpdates, onComplete: { model.completeStartupPreferences() })
            } else {
                workspace
            }
        }
        .onChange(of: model.sidebarToggleRequestID) { _ in
            local.columnVisibility = local.columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: $local.showSettings) { SettingsView() }
        .sheet(isPresented: $local.showTaskLists) { TaskListManagerView() }
        .sheet(isPresented: $local.showCalendars) { CalendarCreatorView() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshMutationRecoveryState()
            model.updateLocalDate()
            model.reconcileLocalReminders(trigger: .appActivation)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.updateLocalDate()
            model.reconcileLocalReminders(trigger: .systemWake)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            model.updateLocalDate(now: now)
        }
    }

    private var onboardingStatusMessage: String? {
        let settings = model.googleTransportSettings
        guard settings.signingIn || settings.requiresRestart || settings.signInError != nil else { return nil }
        return settings.status
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $local.columnVisibility) {
            WorkspaceSidebarView(showTaskLists: $local.showTaskLists, showCalendars: $local.showCalendars,
                                 openSettings: { local.showSettings = true })
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
            .overlay(alignment: .leading) {
                if local.columnVisibility != .detailOnly {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
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
        .navigationSplitViewStyle(.balanced)
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
