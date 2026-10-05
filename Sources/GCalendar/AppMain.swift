import AppKit
import Foundation
import SwiftUI

private enum NormalRefreshPayload {
    case full(GWSCompletedFullSync)
    case calendarRange(WorkspaceSnapshot)
    case tasks(GWSCompletedTasksSync)
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    enum Section: String, CaseIterable { case calendar = "Календарь", tasks = "Задачи" }
    enum CalendarMode: String, CaseIterable { case week = "Неделя", day = "День" }
    typealias TaskFilter = TaskWorkspaceFilter
    typealias SyncState = WorkspaceSyncState
    enum Appearance: String, CaseIterable, Identifiable { case system = "Система", light = "Светлая", dark = "Тёмная"; var id: String { rawValue } }

    @Published var snapshot: WorkspaceSnapshot
    @Published var section: Section = .calendar
    @Published var calendarMode: CalendarMode = .week
    @Published var taskFilter: TaskFilter = .all
    @Published var selectedCalendarID: String?
    @Published var visibleCalendarIDs: Set<String>?
    @Published var selectedTaskListID: String?
    @Published var activeDate = Date()
    @Published private(set) var localToday = DateOnly(date: Date())
    @Published var searchText = ""
    @Published var syncState: SyncState = .idle
    @Published var statusMessage = ""
    @Published var gwsPath: String
    @Published var appearance: Appearance
    @Published var mutationInFlight = false
    @Published private(set) var pendingMutation: PendingMutation?
    @Published private(set) var mutationRecoveryProblem: String?
    @Published var notificationPermission: ReminderPermission = .notDetermined
    @Published var notificationRuntimeStatus: NotificationRuntimeStatus?
    @Published var searchFocusRequestID = 0
    @Published var newItemRequestID = 0

    let launchMode: AppLaunchMode
    let metadataStore: LocalMetadataStoring
    let reminderCoordinator: ReminderCoordinator
    let eventReminderCoordinator: EventReminderCoordinator
    private let snapshotStore: SnapshotStoring
    private let runner: GWSProcessRunning?
    private let mutationJournal: MutationJournal
    private let defaults: UserDefaults
    private let demoAdapter: DemoWorkspaceAdapter?
    private var ledgerAcceptanceSession: SyntheticLedgerAcceptanceSession? = nil
    private let notificationStatusProvider: NotificationStatusProviding?
    private var refreshCoordinator = LatestWinsRefreshCoordinator<WorkspaceRefreshQuery>()
    private var refreshRequestSequence = 0

    init(mode: AppLaunchMode = .normal, defaults suppliedDefaults: UserDefaults? = nil, scheduler suppliedScheduler: ReminderScheduling? = nil) {
        launchMode = mode
        let journalURL = mode == .normal ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("g-calendar/pending-verification.json") : nil
        mutationJournal = MutationJournal(fileURL: journalURL)
        pendingMutation = mutationJournal.pending
        mutationRecoveryProblem = mutationJournal.isBlocked && mutationJournal.pending == nil ? MutationRecoveryFailure.corruptJournal.errorDescription : nil
        let defaults = suppliedDefaults ?? (mode == .normal
            ? .standard
            : UserDefaults(suiteName: "com.alexbeketov.gcalendar.session.\(UUID().uuidString)")!)
        self.defaults = defaults
        gwsPath = mode == .normal ? (defaults.string(forKey: "gwsExecutablePath") ?? "") : ""
        appearance = mode == .normal ? (Appearance(rawValue: defaults.string(forKey: "appAppearance") ?? "Система") ?? .system) : .system

        if mode == .normal {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
            let appDirectory = appSupport.appendingPathComponent("g-calendar", isDirectory: true)
            let diskStore: SnapshotStoring
            if let store = try? FileSnapshotStore.applicationDefault() { diskStore = store } else { diskStore = MemorySnapshotStore() }
            snapshotStore = diskStore
            let loaded = diskStore.load() ?? .empty
            snapshot = loaded
            let metadata = FileLocalMetadataStore(fileURL: appDirectory.appendingPathComponent("local-task-metadata.json"))
            let eventMetadata = FileLocalEventReminderStore(fileURL: appDirectory.appendingPathComponent("local-event-reminders.json"))
            metadataStore = metadata
            let scheduler = suppliedScheduler ?? UserNotificationScheduler()
            reminderCoordinator = ReminderCoordinator(store: metadata, scheduler: scheduler, defaults: defaults)
            eventReminderCoordinator = EventReminderCoordinator(store: eventMetadata, scheduler: scheduler)
            notificationStatusProvider = scheduler as? NotificationStatusProviding
            runner = RuntimeProcessBoundary.runner(for: mode) { FoundationProcessRunner() }
            demoAdapter = nil
            syncState = loaded.fetchedAt == .distantPast ? .idle : .stale
            statusMessage = loaded.fetchedAt == .distantPast ? "Нажмите «Синхронизировать», чтобы загрузить данные." : "Показан последний сохранённый снимок."
        } else if mode == .ledgerAcceptance {
            let session = try? SyntheticLedgerAcceptanceSession()
            let memorySnapshot = MemorySnapshotStore()
            let metadata = MemoryLocalMetadataStore()
            let eventMetadata = MemoryLocalEventReminderStore()
            let scheduler = NoopReminderScheduler()
            snapshotStore = memorySnapshot
            snapshot = .empty
            metadataStore = metadata
            reminderCoordinator = ReminderCoordinator(store: metadata, scheduler: scheduler, defaults: defaults)
            eventReminderCoordinator = EventReminderCoordinator(store: eventMetadata, scheduler: scheduler)
            notificationStatusProvider = nil
            runner = session?.runner
            demoAdapter = nil
            ledgerAcceptanceSession = session
            syncState = session == nil ? .setupRequired : .idle
            statusMessage = session == nil
                ? "Synthetic acceptance ledger недоступен; Google-запросы и изменения отключены."
                : "Будут проверены только точные synthetic IDs из приватного ledger; кэш и широкие списки не читаются."
        } else {
            let demo = mode == .demo ? DemoWorkspaceAdapter() : nil
            let initial = demo?.snapshot() ?? .empty
            let memorySnapshot = MemorySnapshotStore(initial)
            let metadata = MemoryLocalMetadataStore()
            let eventMetadata = MemoryLocalEventReminderStore()
            let scheduler: ReminderScheduling = suppliedScheduler ?? ([.notificationStatus, .notificationTest].contains(mode) ? UserNotificationScheduler() : NoopReminderScheduler())
            snapshotStore = memorySnapshot
            snapshot = initial
            if mode == .demo {
                selectedCalendarID = initial.calendars.first?.id
                selectedTaskListID = initial.taskLists.first?.id
                visibleCalendarIDs = Set(initial.calendars.map(\.id))
            }
            metadataStore = metadata
            reminderCoordinator = ReminderCoordinator(store: metadata, scheduler: scheduler, defaults: defaults)
            eventReminderCoordinator = EventReminderCoordinator(store: eventMetadata, scheduler: scheduler)
            notificationStatusProvider = scheduler as? NotificationStatusProviding
            runner = RuntimeProcessBoundary.runner(for: mode) { FoundationProcessRunner() }
            demoAdapter = demo
            ledgerAcceptanceSession = nil
            syncState = mode == .demo ? .updated : .idle
            statusMessage = mode == .demo ? "ДЕМО · синтетические данные; сеть, кэш пользователя и уведомления отключены." : "Проверка состояния уведомлений…"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }

    var presentationDefaults: UserDefaults { defaults }
    var mutationsBlocked: Bool { mutationInFlight || mutationJournal.isBlocked }

    var selectedCalendar: CalendarInfo? { snapshot.calendars.first(where: { $0.id == selectedCalendarID }) }
    var selectedTaskList: TaskList? { snapshot.taskLists.first(where: { $0.id == selectedTaskListID }) }
    var calendarRangeIsCovered: Bool { snapshot.calendarCoverage?.covers(currentRange()) ?? false }
    var eventsInVisibleRange: [CalendarEvent] {
        let range = currentRange()
        let dates: [Date]
        if calendarMode == .day { dates = [range.start] }
        else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = selectedTimeZone
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
        }
        return dates.flatMap(events(on:))
    }
    var cacheDateText: String? {
        guard snapshot.fetchedAt != .distantPast else { return nil }
        return snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
    }

    func commandFactory() throws -> GWSCommandFactory {
        if launchMode == .demo { return GWSCommandFactory(executableURL: URL(fileURLWithPath: "/usr/bin/true")) }
        if launchMode == .ledgerAcceptance {
            guard let ledgerAcceptanceSession else { throw GWSFailure.forbiddenOperation }
            return ledgerAcceptanceSession.factory
        }
        guard launchMode == .normal else { throw GWSFailure.forbiddenOperation }
        let resolver = GWSExecutableResolver()
        let url = try resolver.resolve(configuredPath: gwsPath.isEmpty ? nil : gwsPath)
        return GWSCommandFactory(executableURL: url)
    }

    func saveSettings() {
        defaults.set(gwsPath, forKey: "gwsExecutablePath")
        defaults.set(appearance.rawValue, forKey: "appAppearance")
        objectWillChange.send()
    }

    func refresh() {
        if launchMode == .demo {
            guard let demoAdapter else { return }
            snapshot = demoAdapter.snapshot()
            syncState = .updated
            statusMessage = "ДЕМО · показаны только синтетические fixtures; сеть, кэш пользователя и уведомления отключены."
            switch DemoScenario.parse(arguments: ProcessInfo.processInfo.arguments) {
            case .ready: break
            case .loading: snapshot = .empty; syncState = .syncing; statusMessage = "ДЕМО · загрузка…"
            case .setup: snapshot = .empty; syncState = .setupRequired; statusMessage = "ДЕМО · укажите путь к gws в настройках."
            case .offline: syncState = .offline; statusMessage = "ДЕМО · нет связи с Google; сохранённые данные доступны."
            case .stale: syncState = .stale; statusMessage = "ДЕМО · данные требуют обновления."
            case .failed: syncState = .failed; statusMessage = "ДЕМО · ответ не удалось прочитать; сохранённые данные доступны."
            case .empty: snapshot = .empty; snapshot.fetchedAt = Date(); statusMessage = "ДЕМО · синхронизация завершена, данных нет."
            case .recovery:
                if !mutationJournal.isBlocked, let invocation = try? GWSCommandFactory(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
                    .taskInsert(taskListID: "demo-task-list", title: "Демо: сохранённый черновик", notes: "Длинные синтетические заметки для проверки отступов и восстановления. \(String(repeating: "Содержимое черновика. ", count: 60))", due: nil, authorization: .userSave) {
                    try? mutationJournal.begin(invocation)
                    pendingMutation = mutationJournal.pending
                }
            }
            return
        }
        if launchMode == .ledgerAcceptance {
            refreshSyntheticAcceptance()
            return
        }
        guard launchMode == .normal else { return }
        requestNormalRefresh(scope: .full)
    }

    func refreshCalendarRangeIfNeeded(force: Bool = false) {
        guard launchMode == .normal else { refresh(); return }
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let range = currentRange()
        if !force, let active = refreshCoordinator.active,
           active.key.scope == .full, active.key.range == range {
            _ = refreshCoordinator.request(active.key)
            return
        }
        if !force, refreshCoordinator.active == nil, snapshot.calendarCoverage?.covers(range) == true { return }
        guard snapshot.fetchedAt != .distantPast else { refresh(); return }
        let query = makeRefreshQuery(range: range, scope: .calendarRange, force: force)
        guard let request = refreshCoordinator.request(query) else { return }
        startNormalRefresh(request, runner: runner)
    }

    private func requestNormalRefresh(scope: WorkspaceRefreshScope, force: Bool = false) {
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let query = makeRefreshQuery(range: currentRange(), scope: scope, force: force)
        guard let request = refreshCoordinator.request(query) else { return }
        startNormalRefresh(request, runner: runner)
    }

    private func makeRefreshQuery(range: DateRange, scope: WorkspaceRefreshScope, force: Bool) -> WorkspaceRefreshQuery {
        if force { refreshRequestSequence += 1 }
        return WorkspaceRefreshQuery(range: range, scope: scope, requestID: force ? refreshRequestSequence : nil)
    }

    private func startNormalRefresh(_ request: RefreshTicket<WorkspaceRefreshQuery>, runner: GWSProcessRunning) {
        syncState = .syncing
        switch request.key.scope {
        case .full: statusMessage = "Полная синхронизация…"
        case .calendarRange: statusMessage = "Обновление календарного диапазона…"
        case .tasks: statusMessage = "Обновление задач…"
        }
        let path = gwsPath
        let cache = snapshotStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<NormalRefreshPayload, Error>
            do {
                let executable = try GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path)
                let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
                let service = GWSWorkspaceService(reader: reader, cache: cache)
                switch request.key.scope {
                case .full:
                    outcome = .success(.full(try service.refreshCompletedFullSync(range: request.key.range)))
                case .calendarRange:
                    outcome = .success(.calendarRange(try service.refreshCalendarRange(range: request.key.range)))
                case .tasks:
                    outcome = .success(.tasks(try service.refreshTasks()))
                }
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.refreshCoordinator.finish(request) {
                case .ignored:
                    return
                case .superseded(let latestRequest):
                    if latestRequest.key.scope == .calendarRange,
                       case .success(.full(let completedSync)) = outcome {
                        Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulFullSync: completedSync) }
                        self.reconcileEventReminders()
                    }
                    if latestRequest.key.scope == .calendarRange,
                       case .success(.tasks(let completedSync)) = outcome {
                        Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulTasksSync: completedSync) }
                    }
                    self.startNormalRefresh(latestRequest, runner: runner)
                    return
                case .accepted:
                    break
                }
                switch outcome {
                case .success(.full(let completedFullSync)):
                    let refreshed = completedFullSync.snapshot
                    self.installRefreshedSnapshot(refreshed)
                    self.syncState = .updated
                    self.statusMessage = "Полностью обновлено · \(refreshed.fetchedAt.formatted(date: .omitted, time: .shortened))"
                    Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulFullSync: completedFullSync) }
                    self.reconcileEventReminders()
                    if refreshed.calendarCoverage?.covers(self.currentRange()) != true { self.refreshCalendarRangeIfNeeded() }
                case .success(.calendarRange(let refreshed)):
                    self.installRefreshedSnapshot(refreshed)
                    self.syncState = .updated
                    let calendarDate = (refreshed.calendarFetchedAt ?? refreshed.fetchedAt).formatted(date: .omitted, time: .shortened)
                    let taskDate = refreshed.tasksFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "не загружались"
                    self.statusMessage = "Календарь обновлён · \(calendarDate) · задачи из кэша от \(taskDate)"
                    if refreshed.calendarCoverage?.covers(self.currentRange()) != true { self.refreshCalendarRangeIfNeeded() }
                case .success(.tasks(let completedTasksSync)):
                    let refreshed = completedTasksSync.snapshot
                    self.installRefreshedSnapshot(refreshed)
                    self.syncState = .updated
                    let tasksDate = (refreshed.tasksFetchedAt ?? refreshed.fetchedAt).formatted(date: .omitted, time: .shortened)
                    let calendarDate = refreshed.calendarFetchedAt?.formatted(date: .omitted, time: .shortened) ?? "не загружен"
                    self.statusMessage = "Задачи обновлены · \(tasksDate) · календарь из кэша от \(calendarDate)"
                    Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulTasksSync: completedTasksSync) }
                    if refreshed.calendarCoverage?.covers(self.currentRange()) != true { self.refreshCalendarRangeIfNeeded() }
                case .failure(let error):
                    self.syncState = .afterFailure(error as? GWSFailure)
                    self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Синхронизация не выполнена. Сохранённые данные не изменены."
                }
            }
        }
    }

    private func installRefreshedSnapshot(_ refreshed: WorkspaceSnapshot) {
        let oldCalendarIDs = Set(snapshot.calendars.map(\.id))
        let refreshedCalendarIDs = Set(refreshed.calendars.map(\.id))
        snapshot = refreshed
        if let visible = visibleCalendarIDs {
            visibleCalendarIDs = visible.intersection(refreshedCalendarIDs).union(refreshedCalendarIDs.subtracting(oldCalendarIDs))
        } else {
            visibleCalendarIDs = refreshedCalendarIDs
        }
        if !refreshedCalendarIDs.contains(selectedCalendarID ?? "") {
            selectedCalendarID = refreshed.calendars.first?.id
        }
        selectedTaskListID = TaskWorkspaceLayout.validSelectedListID(selectedTaskListID, lists: refreshed.taskLists)
    }

    private func refreshSyntheticAcceptance() {
        guard let ledgerAcceptanceSession else {
            syncState = .setupRequired
            statusMessage = "Synthetic acceptance ledger недоступен; изменения отключены."
            return
        }
        guard syncState != .syncing else { return }
        syncState = .syncing
        statusMessage = "Проверяются точные synthetic resources…"
        let requireAll = snapshot.fetchedAt == .distantPast
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<WorkspaceSnapshot, Error>
            do { outcome = .success(try ledgerAcceptanceSession.loadSnapshot(requireAll: requireAll)) }
            catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let refreshed):
                    self.snapshot = refreshed
                    if !refreshed.calendars.contains(where: { $0.id == self.selectedCalendarID ?? "" }) {
                        self.selectedCalendarID = refreshed.calendars.first?.id
                    }
                    if !refreshed.taskLists.contains(where: { $0.id == self.selectedTaskListID ?? "" }) {
                        self.selectedTaskListID = refreshed.taskLists.first?.id
                    }
                    self.visibleCalendarIDs = Set(refreshed.calendars.map(\.id))
                    if let event = refreshed.events.first {
                        self.activeDate = event.start.instant
                            ?? event.start.dateOnly?.startOfDay(in: self.selectedTimeZone)
                            ?? self.activeDate
                    }
                    self.syncState = .updated
                    self.statusMessage = "Synthetic acceptance · exact resources checked · event \(refreshed.events.count), task \(refreshed.tasks.count), list \(refreshed.taskLists.count)."
                case .failure(let error):
                    self.syncState = self.snapshot.fetchedAt == .distantPast ? .setupRequired : .stale
                    self.statusMessage = (error as? GWSFailure)?.errorDescription
                        ?? "Проверка synthetic ledger не выполнена; изменение не отправлено."
                }
            }
        }
    }

    func performMutation(_ invocation: ProcessInvocation, thenRefresh: Bool = true,
                         onSuccess: (() -> Void)? = nil, onFailure: ((String) -> Void)? = nil) {
        if launchMode == .demo {
            guard !mutationJournal.isBlocked else { onFailure?(MutationRecoveryFailure.pendingVerification.errorDescription ?? "Требуется проверка."); return }
            do {
                try demoAdapter?.perform(invocation)
                if let demoAdapter {
                    snapshot = demoAdapter.snapshot()
                    if !snapshot.calendars.contains(where: { $0.id == selectedCalendarID }) {
                        selectedCalendarID = snapshot.calendars.first?.id
                    }
                    if !snapshot.taskLists.contains(where: { $0.id == selectedTaskListID }) {
                        selectedTaskListID = snapshot.taskLists.first?.id
                    }
                    visibleCalendarIDs = Set(snapshot.calendars.map(\.id))
                }
                statusMessage = "ДЕМО · действие обработано локальным fixture-адаптером; Google не вызывался."
                onSuccess?()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Демо-действие не выполнено."
                statusMessage = message
                onFailure?(message)
            }
            return
        }
        guard launchMode == .normal || launchMode == .ledgerAcceptance else {
            onFailure?("В этом режиме изменения отключены.")
            return
        }
        guard !mutationInFlight else { return }
        guard !mutationJournal.isBlocked else {
            onFailure?(MutationRecoveryFailure.pendingVerification.errorDescription ?? "Требуется проверка изменения.")
            return
        }
        mutationInFlight = true
        statusMessage = "Сохранение…"
        let path = gwsPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<GWSMutationResult, Error>
            do {
                guard let self, let runner = self.runner else { throw GWSFailure.forbiddenOperation }
                let executable = try GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path)
                let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
                outcome = .success(try RecoverableMutationService(runner: runner, journal: self.mutationJournal).perform(invocation, reader: reader))
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationInFlight = false
                self.pendingMutation = self.mutationJournal.pending
                switch outcome {
                case .success(let result) where result.isReadBackVerified:
                    self.statusMessage = "Изменение подтверждено точным чтением Google."
                    if case .taskVerified(let task) = result {
                        Task { await self.reminderCoordinator.reconcile(tasks: [task]) }
                    }
                    if case .resourceDeleted = result {
                        if invocation.operation == .taskDelete, let taskID = Self.argument("task", in: invocation) {
                            Task { try? await self.reminderCoordinator.delete(taskID: taskID) }
                        } else if invocation.operation == .eventDelete,
                                  let calendarID = Self.argument("calendarId", in: invocation),
                                  let eventID = Self.argument("eventId", in: invocation) {
                            let identity = CalendarEventIdentity(calendarID: calendarID, eventID: eventID)
                            Task { try? await self.eventReminderCoordinator.remove(identity: identity) }
                        }
                    }
                    onSuccess?()
                    if thenRefresh { self.refreshAfterMutation(invocation.operation) }
                case .success:
                    let message = "Запрос принят, но точное чтение не подтвердило результат. Форма оставлена открытой."
                    self.statusMessage = message
                    onFailure?(message)
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? "Изменение не подтверждено."
                    self.statusMessage = message
                    onFailure?(message)
                }
            }
        }
    }

    func recheckPendingMutation(onSuccess: (() -> Void)? = nil) {
        guard !mutationInFlight, pendingMutation?.resourceID != nil, let runner else { return }
        mutationInFlight = true
        statusMessage = "Проверяем сохранение…"
        let path = gwsPath
        let journal = mutationJournal
        let pendingOperation = pendingMutation?.operation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<GWSMutationResult, Error>
            do {
                let executable = try GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path)
                let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
                result = .success(try RecoverableMutationService(runner: runner, journal: journal).recheck(reader: reader))
            } catch { result = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationInFlight = false
                self.pendingMutation = journal.pending
                switch result {
                case .success(let verified):
                    self.statusMessage = "Изменение подтверждено точным чтением Google."
                    if case .taskVerified(let task) = verified { Task { await self.reminderCoordinator.reconcile(tasks: [task]) } }
                    onSuccess?()
                    // A domain refresh reconciles deletion reminders using complete, confirmed data.
                    if let pendingOperation { self.refreshAfterMutation(pendingOperation) }
                case .failure(let error):
                    self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Проверка пока не завершена."
                }
            }
        }
    }

    func acknowledgeManuallyReconciledMutation() {
        guard !mutationInFlight else { return }
        do {
            try mutationJournal.releaseAfterManualReview()
            pendingMutation = nil
            mutationRecoveryProblem = nil
            statusMessage = "Проверка вручную отмечена пользователем. Автоматическое подтверждение Google не заявляется."
            refresh()
        } catch { mutationRecoveryProblem = "Не удалось обновить журнал проверки. Запись остаётся заблокированной." }
    }

    private func refreshAfterMutation(_ operation: GWSOperation) {
        guard launchMode == .normal else { refresh(); return }
        guard let scope = WorkspaceRefreshScope.afterVerifiedMutation(operation) else { refresh(); return }
        switch scope {
        case .calendarRange:
            reconcileEventReminders()
            refreshCalendarRangeIfNeeded(force: true)
        case .tasks:
            requestNormalRefresh(scope: scope, force: true)
        case .full:
            refresh()
        }
    }

    func queryNotificationStatusAndExit() async {
        guard launchMode == .notificationStatus else { return }
        let status = await notificationStatusProvider?.notificationStatus()
            ?? NotificationRuntimeStatus(authorization: "unavailable", pendingCount: 0, deliveredCount: 0,
                                         alertSetting: "unavailable", soundSetting: "unavailable",
                                         foregroundDelegateReady: false)
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        print("G_CALENDAR_NOTIFICATION_STATUS bundle_identifier=\(bundleIdentifier) \(status.safeSummary)")
        fflush(stdout)
        NSApp.terminate(nil)
    }

    func runNotificationTestAndExit() async {
        guard launchMode == .notificationTest, let scheduler = reminderCoordinator.scheduler as? UserNotificationScheduler else { return }
        do {
            let request = try await NotificationAcceptance.scheduleOneTest(using: scheduler)
            var delivered = false
            for _ in 0..<8 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if await scheduler.wasDelivered(identifier: request.identifier) { delivered = true; break }
            }
            if !delivered { await scheduler.cancel(identifier: request.identifier) }
            print("G_CALENDAR_NOTIFICATION_TEST bundle_identifier=\(Bundle.main.bundleIdentifier ?? "unknown") scheduled=1 own_notification_delivered=\(delivered) visible_banner=needs_human_verification")
            fflush(stdout)
            Darwin.exit(delivered ? 0 : 1)
        } catch {
            print("G_CALENDAR_NOTIFICATION_TEST status=blocked authorization_or_scheduler_failure=true permission_requested=false")
            fflush(stdout)
            Darwin.exit(1)
        }
    }

    func runSyntheticAcceptanceAndExit() async {
        guard launchMode == .syntheticAcceptance else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--acceptance-dir"), arguments.indices.contains(index + 1) else {
            print("G_CALENDAR_LIVE status=blocked reason=fresh_private_directory_required")
            fflush(stdout)
            Darwin.exit(2)
        }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        let finishExistingCleanup = arguments.contains("--finish-existing-cleanup")
        let code = await Task.detached(priority: .userInitiated) { () -> Int32 in
            do {
                let executable = try GWSExecutableResolver().resolve(configuredPath: nil)
                let run = try SyntheticAcceptanceRun(directory: directory, factory: GWSCommandFactory(executableURL: executable), runner: FoundationProcessRunner(), finishExistingCleanup: finishExistingCleanup)
                let steps = try finishExistingCleanup ? run.finishExistingCleanup() : run.run()
                let samples = run.stepMilliseconds.sorted()
                let median = samples.isEmpty ? 0 : samples[samples.count / 2]
                let maximum = samples.last ?? 0
                print(String(format: "G_CALENDAR_LIVE status=passed verified_steps=%d current_run_objects=3 deleted=3 mutation_plus_exact_get_p50_ms=%.1f max_ms=%.1f", steps, median, maximum))
                return 0
            } catch {
                // IDs/drafts remain exclusively in the private journal/ledger, never stdout.
                let reason: String
                switch error {
                case GWSFailure.invalidResponse: reason = "invalid_response"
                case GWSFailure.mutationNotVerified: reason = "read_back_mismatch"
                case GWSFailure.resourceNotFound: reason = "not_found"
                case GWSFailure.forbiddenOperation: reason = "scope_guard"
                case GWSFailure.processFailed: reason = "process_failed"
                case GWSFailure.timedOut: reason = "timeout"
                case MutationRecoveryFailure.pendingVerification: reason = "pending_verification"
                default: reason = "other"
                }
                print("G_CALENDAR_LIVE status=failed reason=\(reason) private_ledger_retained=true automatic_retry=false")
                return 1
            }
        }.value
        fflush(stdout)
        Darwin.exit(code)
    }

    func refreshNotificationStatus() async {
        guard let notificationStatusProvider else {
            notificationRuntimeStatus = NotificationRuntimeStatus(authorization: "unavailable", pendingCount: 0,
                                                                  deliveredCount: 0, alertSetting: "unavailable",
                                                                  soundSetting: "unavailable", foregroundDelegateReady: false)
            return
        }
        notificationRuntimeStatus = await notificationStatusProvider.notificationStatus()
    }

    func reconcileLocalReminders(trigger: ReminderLifecycleTrigger) {
        guard launchMode == .normal, let runner else { return }
        let path = gwsPath
        let tasks = snapshot.tasks
        let taskCoordinator = reminderCoordinator
        let eventCoordinator = eventReminderCoordinator
        Task {
            await ReminderLifecycleReconciliation.perform(for: trigger) {
                await taskCoordinator.reconcile(tasks: tasks)
                guard let executable = try? GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path) else { return }
                let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
                await eventCoordinator.reconcile(using: reader)
            }
        }
    }

    private static func argument(_ name: String, in invocation: ProcessInvocation) -> String? {
        guard let index = invocation.arguments.firstIndex(of: "--params"), invocation.arguments.indices.contains(index + 1),
              let data = invocation.arguments[index + 1].data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return values[name]
    }

    private func reconcileEventReminders() {
        guard let runner else { return }
        let path = gwsPath
        Task {
            guard let executable = try? GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path) else { return }
            let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
            await eventReminderCoordinator.reconcile(using: reader)
        }
    }

    func updatePath(_ value: String) {
        gwsPath = value
        saveSettings()
    }

    func setAppearance(_ value: Appearance) {
        appearance = value
        saveSettings()
    }

    func setSection(_ value: Section) {
        section = value
        searchText = ""
    }

    func requestSearchFocus() { searchFocusRequestID += 1 }
    func requestNewItem() { newItemRequestID += 1 }

    func moveDate(_ amount: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = selectedTimeZone
        let component: Calendar.Component = calendarMode == .week ? .weekOfYear : .day
        if let date = calendar.date(byAdding: component, value: amount, to: activeDate) {
            activeDate = date
            refreshCalendarRangeIfNeeded()
        }
    }

    func updateLocalDate(now: Date = Date()) {
        let today = DateOnly(date: now)
        if today != localToday { localToday = today }
    }

    func goToToday() { updateLocalDate(); activeDate = Date(); refreshCalendarRangeIfNeeded() }

    func currentRange() -> DateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = selectedTimeZone
        let component: Calendar.Component = calendarMode == .week ? .weekOfYear : .day
        let interval = calendar.dateInterval(of: component, for: activeDate)
        let start = interval?.start ?? calendar.startOfDay(for: activeDate)
        let end = interval?.end ?? calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (try? DateRange(start: start, endExclusive: end, timeZone: selectedTimeZone)) ?? (try! DateRange(start: start, endExclusive: end, timeZone: calendar.timeZone))
    }

    var selectedTimeZone: TimeZone {
        if let id = selectedCalendar?.timeZoneID, let zone = TimeZone(identifier: id) { return zone }
        return .current
    }

    func events(on date: Date) -> [CalendarEvent] {
        let day = DateOnly(date: date, timeZone: selectedTimeZone)
        return snapshot.events.filter { event in
            guard visibleCalendarIDs?.contains(event.calendarID) ?? true else { return false }
            if event.isAllDay, let start = event.start.dateOnly, let end = event.end.dateOnly {
                return day >= start && day < end
            }
            guard let start = event.start.instant, let end = event.end.instant else { return false }
            let startDay = DateOnly(date: start, timeZone: selectedTimeZone)
            let endDay = DateOnly(date: end.addingTimeInterval(-1), timeZone: selectedTimeZone)
            return day >= startDay && day <= endDay
        }.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func tasks(on date: Date) -> [GoogleTask] {
        let day = DateOnly(date: date, timeZone: selectedTimeZone)
        return snapshot.tasks.filter { task in
            !task.deleted && (selectedTaskListID == nil || task.taskListID == selectedTaskListID) && task.due == day &&
            (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var undatedTasks: [GoogleTask] {
        CalendarTimeGridLayout.undatedTasks(snapshot.tasks, selectedTaskListID: selectedTaskListID, searchText: searchText)
    }

    func setCalendarVisible(_ calendarID: String, isVisible: Bool) {
        var visible = visibleCalendarIDs ?? Set(snapshot.calendars.map(\.id))
        if isVisible { visible.insert(calendarID) }
        else { visible.remove(calendarID) }
        visibleCalendarIDs = visible
    }

    func isCalendarVisible(_ calendarID: String) -> Bool {
        visibleCalendarIDs?.contains(calendarID) ?? true
    }

    var visibleTasks: [GoogleTask] {
        TaskWorkspaceLayout.filteredTasks(snapshot.tasks, filter: taskFilter, selectedTaskListID: selectedTaskListID,
                                          searchText: searchText, today: localToday)
    }

    func taskGroups() -> [(String, [GoogleTask])] {
        TaskWorkspaceLayout.groups(visibleTasks, today: localToday)
    }
}

final class GCalendarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#if !G_CALENDAR_TEST
@main
struct GCalendarApp: App {
    @NSApplicationDelegateAdaptor(GCalendarAppDelegate.self) private var appDelegate
    private let launchMode: AppLaunchMode
    @StateObject private var model: WorkspaceViewModel

    init() {
        let mode = AppLaunchMode.parse(arguments: ProcessInfo.processInfo.arguments)
        launchMode = mode
        _model = StateObject(wrappedValue: WorkspaceViewModel(mode: mode))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .defaultAppStorage(model.presentationDefaults)
                .frame(minWidth: 760, minHeight: 560)
                .preferredColorScheme(model.preferredColorScheme)
                .task {
                    if launchMode == .notificationStatus { await model.queryNotificationStatusAndExit() }
                    else if launchMode == .notificationTest { await model.runNotificationTestAndExit() }
                    else if launchMode == .syntheticAcceptance { await model.runSyntheticAcceptanceAndExit() }
                    else {
                        model.refresh()
                        if launchMode == .demo {
                            print("G_CALENDAR_DEMO \(model.statusMessage) calendar_count=\(model.snapshot.calendars.count) event_count=\(model.snapshot.events.count) task_list_count=\(model.snapshot.taskLists.count) task_count=\(model.snapshot.tasks.count)")
                            fflush(stdout)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Завершить g-calendar") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            CommandGroup(after: .newItem) {
                Button("Поиск") { model.requestSearchFocus() }.keyboardShortcut("f", modifiers: .command)
                Button("Сегодня") { model.goToToday() }.keyboardShortcut("t", modifiers: .command)
                Button("Новое событие или задача") { model.requestNewItem() }.keyboardShortcut("n", modifiers: .command)
                Button("Синхронизировать") { model.refresh() }.keyboardShortcut("r", modifiers: .command)
                    .disabled(model.syncState == .syncing || model.mutationInFlight)
            }
            CommandMenu("Навигация") {
                Button("Календарь") { model.setSection(.calendar) }.keyboardShortcut("1", modifiers: .command)
                Button("Задачи") { model.setSection(.tasks) }.keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Предыдущий период") { model.moveDate(-1) }.keyboardShortcut("[", modifiers: .command)
                Button("Следующий период") { model.moveDate(1) }.keyboardShortcut("]", modifiers: .command)
            }
        }
    }
}
#endif
