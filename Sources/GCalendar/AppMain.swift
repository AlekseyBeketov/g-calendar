import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class WorkspaceViewModel: ObservableObject {
    enum Section: String, CaseIterable { case calendar = "Календарь", tasks = "Задачи" }
    typealias CalendarMode = CalendarPresentationMode
    typealias TaskFilter = TaskWorkspaceFilter
    typealias SyncState = WorkspaceSyncState
    enum Appearance: String, CaseIterable, Identifiable { case system = "Система", light = "Светлая", dark = "Тёмная"; var id: String { rawValue } }

    @Published var snapshot: WorkspaceSnapshot
    @Published var section: Section = .calendar
    @Published var calendarMode: CalendarMode = .week { willSet { if newValue != calendarMode { DemoPerformanceProbe.shared.begin(.range) } } }
    @Published var taskFilter: TaskFilter = .all { willSet { if newValue != taskFilter { DemoPerformanceProbe.shared.begin(.filter) } } }
    @Published var selectedCalendarID: String?
    @Published var visibleCalendarIDs: Set<String>?
    @Published var selectedTaskListID: String? { willSet { if newValue != selectedTaskListID { DemoPerformanceProbe.shared.begin(.taskList) } } }
    @Published var activeDate = Date()
    @Published private(set) var localToday = DateOnly(date: Date())
    @Published var searchText = "" { willSet { if newValue != searchText { DemoPerformanceProbe.shared.begin(.search) } } }
    @Published var syncState: SyncState = .idle
    @Published var statusMessage = ""
    @Published var gwsPath: String
    @Published var appearance: Appearance
    @Published var mutationInFlight = false
    @Published private(set) var pendingMutation: PendingMutation?
    @Published private(set) var mutationRecoveryProblem: String?
    @Published private(set) var mutationJournalBusy = false
    @Published var notificationPermission: ReminderPermission = .notDetermined
    @Published var notificationRuntimeStatus: NotificationRuntimeStatus?
    @Published var searchFocusRequestID = 0
    @Published var newItemRequestID = 0
    @Published var sidebarToggleRequestID = 0
    @Published private(set) var shortcutSettings: WorkspaceShortcutSettings
    @Published private(set) var taskPreferences = TaskWorkspacePreferences()
    @Published private(set) var completedDeletionInProgress = false

    let launchMode: AppLaunchMode
    let metadataStore: LocalMetadataStoring
    let reminderCoordinator: ReminderCoordinator
    let eventReminderCoordinator: EventReminderCoordinator
    private let snapshotStore: SnapshotStoring
    private let runner: GWSProcessRunning?
    private let transportContext: WorkspaceTransportContext?
    private var transportSettingsObserver: AnyCancellable?
    let googleTransportSettings: GoogleTransportSettings
    private let mutationJournal: MutationJournal
    private let defaults: UserDefaults
    private let demoAdapter: DemoWorkspaceAdapter?
    private var ledgerAcceptanceSession: SyntheticLedgerAcceptanceSession? = nil
    private let notificationStatusProvider: NotificationStatusProviding?
    private var refreshCoordinator = WorkspaceRefreshCoordinator()
    private var refreshRequestSequence = 0
    private var snapshotAcceptance = WorkspaceSnapshotAcceptance()
    private var requiredVerifiedTaskListIDs = Set<String>()
    private var neighbourPrefetch = CalendarNeighbourPrefetch()
    private var backgroundRefreshQueue: [WorkspaceRefreshQuery] = []
    private var activeReadCancellation: GWSReadCancellation?

    init(mode: AppLaunchMode = .normal, defaults suppliedDefaults: UserDefaults? = nil, scheduler suppliedScheduler: ReminderScheduling? = nil) {
        launchMode = mode
        let defaults = suppliedDefaults ?? (mode == .normal ? .standard : UserDefaults(suiteName: "com.alexbeketov.gcalendar.session.\(UUID().uuidString)")!)
        let context = mode == .normal ? WorkspaceTransportContext.load(defaults: defaults) : nil
        transportContext = context
        googleTransportSettings = GoogleTransportSettings(active: context?.kind ?? .gws, defaults: defaults, activeProfile: context?.profile,
            secrets: mode == .normal ? GoogleKeychainSecretStore() : GoogleMemorySecretStore())
        let journalURL = context?.journalURL
        mutationJournal = MutationJournal(fileURL: journalURL)
        let journalState = mutationJournal.review()
        pendingMutation = journalState.pending
        mutationRecoveryProblem = journalState.pending == nil ? journalState.failure?.errorDescription : nil
        mutationJournalBusy = journalState.failure == .journalBusy
        self.defaults = defaults
        shortcutSettings = WorkspaceShortcutSettings.load(from: defaults)
        gwsPath = mode == .normal ? (defaults.string(forKey: "gwsExecutablePath") ?? "") : ""
        appearance = mode == .normal ? (Appearance(rawValue: defaults.string(forKey: "appAppearance") ?? "Система") ?? .system) : .system
        taskPreferences = TaskWorkspacePreferences.load(from: defaults, key: "taskWorkspacePreferences." + (context?.identity ?? "gws"))

        if mode == .normal {
            let appDirectory = context!.directory
            let diskStore: SnapshotStoring = FileSnapshotStore(fileURL: appDirectory.appendingPathComponent("snapshot.json"))
            snapshotStore = diskStore
            let loaded = diskStore.load() ?? .empty
            snapshot = loaded
            let metadata = FileLocalMetadataStore(fileURL: appDirectory.appendingPathComponent("local-task-metadata.json"))
            let eventMetadata = FileLocalEventReminderStore(fileURL: appDirectory.appendingPathComponent("local-event-reminders.json"))
            metadataStore = metadata
            let baseScheduler = suppliedScheduler ?? UserNotificationScheduler()
            let scheduler: ReminderScheduling = context?.identity.map { NamespacedReminderScheduler(base: baseScheduler, namespace: $0) } ?? baseScheduler
            reminderCoordinator = ReminderCoordinator(store: metadata, scheduler: scheduler, defaults: defaults, enabledKey: context!.reminderEnabledKey)
            eventReminderCoordinator = EventReminderCoordinator(store: eventMetadata, scheduler: scheduler)
            notificationStatusProvider = baseScheduler as? NotificationStatusProviding
            runner = context?.runner
            demoAdapter = nil
            syncState = loaded.fetchedAt == .distantPast ? .idle : .stale
            statusMessage = context?.setupProblem ?? (loaded.fetchedAt == .distantPast ? "Нажмите «Синхронизировать», чтобы загрузить данные." : "Показан последний сохранённый снимок.")
            if context?.setupProblem != nil { syncState = .setupRequired }
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
                selectedCalendarID = CalendarNavigation.selectedID(nil, calendars: initial.calendars)
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
        selectedCalendarID = CalendarNavigation.selectedID(selectedCalendarID, calendars: snapshot.calendars)
        transportSettingsObserver = googleTransportSettings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        googleTransportSettings.applyChanges = { [weak self] in self?.applyGoogleTransportChanges() }
    }

    private var transportRestartInFlight = false
    private func applyGoogleTransportChanges() {
        guard launchMode == .normal, !mutationInFlight, !mutationJournalBusy,
              !transportRestartInFlight, googleTransportSettings.requiresRestart else { return }
        transportRestartInFlight = true
        activeReadCancellation?.cancel()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let application, !application.isEqual(NSRunningApplication.current) else {
                    self.transportRestartInFlight = false
                    self.googleTransportSettings.applicationRestartFailed()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }

    var presentationDefaults: UserDefaults { defaults }
    var transportSettingsBlocked: Bool { mutationInFlight || mutationJournalBusy || mutationRecoveryProblem != nil || mutationJournal.isBlocked }
    var googleReauthenticationAllowed: Bool { launchMode == .normal && pendingMutation != nil && !mutationInFlight && !mutationJournalBusy && googleTransportSettings.canReauthenticate }
    private var mutationAccessBlocked: Bool { transportContext?.recoveryOnly == true || googleTransportSettings.requiresRestart || googleTransportSettings.signingIn || transportSettingsBlocked }
    var mutationsBlocked: Bool { mutationAccessBlocked || completedDeletionInProgress }

    func taskSortMode(for boardID: String) -> TaskSortMode { taskPreferences.sortMode(for: boardID) }
    var allTasksSortMode: TaskSortMode { taskPreferences.unifiedSortMode }
    var orderedTaskLists: [TaskList] { taskPreferences.orderedBoards(snapshot.taskLists) }

    func moveTaskBoard(_ boardID: String, toward targetID: String) {
        guard taskPreferences.moveBoard(boardID, toward: targetID, in: snapshot.taskLists) else { return }
        taskPreferences.save(to: defaults, key: "taskWorkspacePreferences." + (transportContext?.identity ?? "gws"))
    }

    func canShiftTaskBoard(_ boardID: String, direction: Int) -> Bool {
        let ids = orderedTaskLists.map(\.id)
        guard let index = ids.firstIndex(of: boardID) else { return false }
        return ids.indices.contains(index + direction)
    }

    func shiftTaskBoard(_ boardID: String, direction: Int) {
        let ids = orderedTaskLists.map(\.id)
        guard let index = ids.firstIndex(of: boardID), ids.indices.contains(index + direction) else { return }
        moveTaskBoard(boardID, toward: ids[index + direction])
    }

    func setTaskSortMode(_ mode: TaskSortMode, for boardID: String?) {
        if boardID == nil { taskPreferences.allTasksSortMode = mode }
        let ids = boardID.map { [$0] } ?? snapshot.taskLists.map(\.id)
        for id in ids { taskPreferences.setSortMode(mode, for: id) }
        taskPreferences.save(to: defaults, key: "taskWorkspacePreferences." + (transportContext?.identity ?? "gws"))
    }

    func reorderTask(_ task: GoogleTask, before target: GoogleTask) {
        guard !mutationsBlocked, taskSortMode(for: task.taskListID) == .manual,
              task.id != target.id, task.taskListID == target.taskListID, task.parent == target.parent,
              !task.completed, !target.completed,
              let current = snapshot.tasks.first(where: { $0.selectionIdentity == task.selectionIdentity }),
              let destination = snapshot.tasks.first(where: { $0.selectionIdentity == target.selectionIdentity }),
              current.parent == destination.parent, !current.completed, !destination.completed else { return }
        do {
            let previous = TaskOrdering.previousForMove(current, before: destination, in: snapshot.tasks)
            let invocation = try commandFactory().taskReorder(task: current, previous: previous, authorization: .userSave)
            performMutation(invocation)
        } catch { statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить порядок задач." }
    }

    func canShiftTask(_ task: GoogleTask, direction: Int) -> Bool {
        guard !mutationsBlocked, taskSortMode(for: task.taskListID) == .manual, !task.completed else { return false }
        let siblings = TaskOrdering.siblings(task, in: snapshot.tasks)
        guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return false }
        return siblings.indices.contains(index + direction)
    }

    func shiftTask(_ task: GoogleTask, direction: Int) {
        guard canShiftTask(task, direction: direction) else { return }
        let siblings = TaskOrdering.siblings(task, in: snapshot.tasks)
        guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return }
        if direction < 0 { reorderTask(task, before: siblings[index - 1]); return }
        do {
            let invocation = try commandFactory().taskReorder(task: task, previous: siblings[index + 1], authorization: .userSave)
            performMutation(invocation)
        } catch { statusMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось изменить порядок задач." }
    }

    func deleteCompletedTasks(_ confirmedTasks: [GoogleTask]) {
        guard !mutationsBlocked, !confirmedTasks.isEmpty, confirmedTasks.allSatisfy({ $0.completed && !$0.deleted }) else { return }
        completedDeletionInProgress = true
        deleteNextCompleted(confirmedTasks, index: 0, deleted: 0, skipped: 0)
    }

    private func deleteNextCompleted(_ confirmed: [GoogleTask], index: Int, deleted: Int, skipped: Int) {
        guard confirmed.indices.contains(index) else {
            completedDeletionInProgress = false
            statusMessage = "Удалено выполненных задач: \(deleted)." + (skipped > 0 ? " Пропущено: \(skipped)." : "")
            requestTargetedRefresh(taskListIDs: Set(confirmed.map(\.taskListID)))
            return
        }
        let task = confirmed[index]
        guard let current = snapshot.tasks.first(where: { $0.selectionIdentity == task.selectionIdentity }), current.completed, !current.deleted else {
            DispatchQueue.main.async { [weak self] in self?.deleteNextCompleted(confirmed, index: index + 1, deleted: deleted, skipped: skipped + 1) }
            return
        }
        do {
            let invocation = try commandFactory().completedTaskDelete(task: current, authorization: .confirmedDelete)
            performMutation(invocation, thenRefresh: false, asCompletedDeletion: true, onSuccess: { [weak self] in
                DispatchQueue.main.async { [weak self] in self?.deleteNextCompleted(confirmed, index: index + 1, deleted: deleted + 1, skipped: skipped) }
            }, onFailure: { [weak self] message in
                self?.completedDeletionInProgress = false
                self?.statusMessage = "Удалено: \(deleted). Удаление остановлено: \(message)"
            })
        } catch {
            completedDeletionInProgress = false
            statusMessage = "Удалено: \(deleted). " + ((error as? LocalizedError)?.errorDescription ?? "Удаление остановлено.")
        }
    }

    var sortedCalendars: [CalendarInfo] { CalendarNavigation.sorted(snapshot.calendars) }
    var selectedCalendar: CalendarInfo? { snapshot.calendars.first(where: { $0.id == selectedCalendarID }) }
    var selectedTaskList: TaskList? { snapshot.taskLists.first(where: { $0.id == selectedTaskListID }) }
    var calendarRangeIsCovered: Bool { snapshot.calendarCoverage?.covers(currentRange()) ?? false }
    var eventsInVisibleRange: [CalendarEvent] {
        CalendarDatePolicy.days(in: currentRange()).flatMap(events(on:))
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
        guard let transportContext else { throw GWSFailure.forbiddenOperation }
        return try transportContext.factory(configuredGWSPath: gwsPath)
    }

    func saveSettings() {
        defaults.set(gwsPath, forKey: "gwsExecutablePath")
        defaults.set(appearance.rawValue, forKey: "appAppearance")
        objectWillChange.send()
    }

    func refresh() {
        refreshMutationRecoveryState()
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
            case .empty: snapshot = .empty; snapshot.fetchedAt = Date(); selectedTaskListID = nil; selectedCalendarID = nil; statusMessage = "ДЕМО · синхронизация завершена, данных нет."
            case .busy:
                mutationJournalBusy = true
                mutationRecoveryProblem = "Другая копия приложения проверяет изменение. Дождитесь завершения и проверьте журнал."
            case .recovery:
                if !mutationJournal.isBlocked, let invocation = try? GWSCommandFactory(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
                    .taskInsert(taskListID: "demo-task-list", title: "Демо: сохранённый черновик", notes: "Длинные синтетические заметки для проверки отступов и восстановления. \(String(repeating: "Содержимое черновика. ", count: 60))", due: nil, authorization: .userSave) {
                    _ = try? mutationJournal.begin(invocation)
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
        if let activated = CalendarRangeCache.activate(range: currentRange(), in: snapshot) { installRefreshedSnapshot(activated) }
        requestNormalRefresh(scope: .full)
    }

    func refreshCalendarRangeIfNeeded(force: Bool = false) {
        guard launchMode == .normal else { refresh(); return }
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let range = currentRange()
        if !force, let activated = CalendarRangeCache.activate(range: range, in: snapshot) {
            installRefreshedSnapshot(activated)
            if let fetched = activated.calendarFetchedAt, Date().timeIntervalSince(fetched) >= CalendarRangeCache.rangeTTL {
                let coveredRange = activated.calendarCoverage?.dateRange ?? range
                enqueueBackground(WorkspaceRefreshQuery(range: coveredRange, scope: .calendarRange, purpose: .revalidation), runner: runner)
            }
            offerNeighbourPrefetch(runner: runner)
            return
        }
        guard snapshot.fetchedAt != .distantPast else { refresh(); return }
        let query = makeRefreshQuery(range: range, scope: .calendarRange, force: force)
        requestRefresh(query, runner: runner)
    }

    private func requestRefresh(_ query: WorkspaceRefreshQuery, runner: GWSProcessRunning) {
        if query.purpose == .foreground {
            backgroundRefreshQueue.removeAll()
            if let active = refreshCoordinator.active {
                let obsoleteRange = active.key.scope == .calendarRange && active.key.range != query.range
                    && active.key.taskListIDs.isEmpty && active.key.calendarIDs.isEmpty && !active.key.refreshTaskLists
                if active.key.purpose != .foreground || obsoleteRange { activeReadCancellation?.cancel() }
            }
        }
        guard let request = refreshCoordinator.request(query) else { return }
        startNormalRefresh(request, runner: runner)
    }

    private func enqueueBackground(_ query: WorkspaceRefreshQuery, runner: GWSProcessRunning) {
        guard !backgroundRefreshQueue.contains(query), refreshCoordinator.active?.key != query else { return }
        if query.purpose == .revalidation {
            backgroundRefreshQueue.removeAll { $0.purpose == .revalidation }
            backgroundRefreshQueue.insert(query, at: 0)
            if let active = refreshCoordinator.active, active.key.purpose != .foreground, active.key.range != query.range {
                activeReadCancellation?.cancel()
            }
        } else { backgroundRefreshQueue.append(query) }
        startNextBackground(runner: runner)
    }

    private func startNextBackground(runner: GWSProcessRunning) {
        guard refreshCoordinator.active == nil else { return }
        while !backgroundRefreshQueue.isEmpty {
            let query = backgroundRefreshQueue.removeFirst()
            let cached = CalendarRangeCache.activate(range: query.range, in: snapshot)
            if query.purpose == .prefetch, cached != nil { continue }
            if query.purpose == .revalidation, let fetched = cached?.calendarFetchedAt,
               Date().timeIntervalSince(fetched) < CalendarRangeCache.rangeTTL { continue }
            requestRefresh(query, runner: runner)
            return
        }
    }

    private func offerNeighbourPrefetch(runner: GWSProcessRunning) {
        let range = currentRange()
        guard snapshot.calendarCoverage?.covers(range) == true else { return }
        for neighbour in neighbourPrefetch.neighbours(after: range, calendars: snapshot.calendars, snapshot: snapshot) {
            enqueueBackground(WorkspaceRefreshQuery(range: neighbour, scope: .calendarRange, purpose: .prefetch), runner: runner)
        }
    }

    private func requestNormalRefresh(scope: WorkspaceRefreshScope, force: Bool = false) {
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let query = makeRefreshQuery(range: currentRange(), scope: scope, force: force)
        requestRefresh(query, runner: runner)
    }

    private func makeRefreshQuery(range: DateRange, scope: WorkspaceRefreshScope, force: Bool) -> WorkspaceRefreshQuery {
        if force { refreshRequestSequence += 1 }
        return WorkspaceRefreshQuery(range: range, scope: scope, requestID: force ? refreshRequestSequence : nil)
    }

    private func startNormalRefresh(_ request: RefreshTicket<WorkspaceRefreshQuery>, runner: GWSProcessRunning) {
        let foreground = request.key.purpose == .foreground
        if foreground { syncState = .syncing; statusMessage = "Обновление данных…" }
        let path = gwsPath
        let context = transportContext
        let cache = snapshotStore
        let baseline = snapshot
        let startedRevision = snapshotAcceptance.revision
        let cancellation = GWSReadCancellation()
        activeReadCancellation = cancellation
        DispatchQueue.global(qos: foreground ? .userInitiated : .utility).async { [weak self] in
            let outcome: Result<GWSWorkspaceReadResult, Error>
            do {
                guard let context else { throw GWSFailure.forbiddenOperation }
                let reader = GWSReadClient(factory: try context.factory(configuredGWSPath: path), runner: runner, cancellation: cancellation)
                outcome = .success(try GWSWorkspaceService(reader: reader, cache: cache).read(query: request.key, baseline: baseline))
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self, self.refreshCoordinator.active == request else { return }
                self.activeReadCancellation = nil
                var acceptedRead: GWSWorkspaceReadResult?
                var stale = false
                var cancelled = false
                do {
                    let read = try outcome.get()
                    if let refreshed = try self.snapshotAcceptance.accept(read, startedAt: startedRevision, current: self.snapshot,
                                                                          cache: cache, displayRange: self.currentRange()) {
                        acceptedRead = read
                        if read.completeTasks { self.requiredVerifiedTaskListIDs.removeAll() }
                        else { self.requiredVerifiedTaskListIDs.subtract(read.taskListIDs) }
                        self.installRefreshedSnapshot(refreshed)
                        let stillCurrent = self.snapshotAcceptance.currentGuard()
                        if let proof = read.fullProof(accepted: refreshed) {
                            Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulFullSync: proof, preservingTaskIDs: self.pendingMoveMetadataProtection, stillCurrent: stillCurrent) }
                        } else if let proof = read.tasksProof(accepted: refreshed) {
                            Task { try? await self.reminderCoordinator.reconcile(afterSuccessfulTasksSync: proof, preservingTaskIDs: self.pendingMoveMetadataProtection, stillCurrent: stillCurrent) }
                        } else if !read.taskListIDs.isEmpty {
                            Task { await self.reminderCoordinator.reconcile(tasks: read.tasks, stillCurrent: stillCurrent) }
                        }
                        if foreground && (read.completeCalendar || !read.calendarIDs.isEmpty) { self.reconcileEventReminders() }
                    } else { stale = true }
                } catch {
                    cancelled = (error as? GWSFailure) == .readCancelled
                    if foreground && !cancelled {
                        self.syncState = .afterFailure(error as? GWSFailure)
                        self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Синхронизация не выполнена. Сохранённые данные не изменены."
                    }
                }
                switch self.refreshCoordinator.finish(request, completed: acceptedRead, discardActive: cancelled) {
                case .ignored: return
                case .superseded(let next):
                    self.startNormalRefresh(next, runner: runner)
                    return
                case .accepted: break
                }
                if stale, foreground { self.requestRefresh(request.key, runner: runner); return }
                if acceptedRead != nil, foreground {
                    self.syncState = .updated
                    self.statusMessage = "Обновлено · \(self.snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
                    self.offerNeighbourPrefetch(runner: runner)
                }
                if acceptedRead != nil, self.snapshot.calendarCoverage?.covers(self.currentRange()) != true {
                    self.refreshCalendarRangeIfNeeded()
                    return
                }
                self.startNextBackground(runner: runner)
            }
        }
    }

    private func installVerifiedMutation(_ invocation: ProcessInvocation, result: GWSMutationResult) throws {
        let deletedTaskIDs: [String]
        if invocation.operation == .taskListDelete, let list = Self.argument("tasklist", in: invocation) {
            deletedTaskIDs = snapshot.tasks.filter { $0.taskListID == list }.map(\.id)
        } else { deletedTaskIDs = [] }
        let updated = try WorkspaceSnapshotReducer.applying(invocation: invocation, result: result, to: snapshot)
        requiredVerifiedTaskListIDs.formUnion(WorkspaceSnapshotReducer.affectedTaskListIDs(invocation: invocation, result: result))
        if invocation.operation == .taskListDelete, let list = Self.argument("tasklist", in: invocation) { requiredVerifiedTaskListIDs.remove(list) }
        snapshotAcceptance.verifiedMutation()
        backgroundRefreshQueue.removeAll()
        if refreshCoordinator.active?.key.purpose != .foreground { activeReadCancellation?.cancel() }
        installRefreshedSnapshot(updated)
        // A disk failure must not conceal a successful exact GET from the form.
        do { try snapshotStore.commit(updated) }
        catch { statusMessage = "Изменение подтверждено; локальный кэш пока не сохранён." }
        if !deletedTaskIDs.isEmpty {
            Task { for id in deletedTaskIDs { try? await reminderCoordinator.delete(taskID: id) } }
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
            selectedCalendarID = CalendarNavigation.selectedID(nil, calendars: refreshed.calendars)
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
                        self.selectedCalendarID = CalendarNavigation.selectedID(nil, calendars: refreshed.calendars)
                    }
                    self.selectedTaskListID = TaskWorkspaceLayout.validSelectedListID(self.selectedTaskListID, lists: refreshed.taskLists)
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

    func performMutation(_ invocation: ProcessInvocation, thenRefresh: Bool = true, asCompletedDeletion: Bool = false,
                         onSuccess: (() -> Void)? = nil, onFailure: ((String) -> Void)? = nil,
                         onVerified: ((GWSMutationResult) -> Void)? = nil) {
        guard !completedDeletionInProgress || asCompletedDeletion else { onFailure?("Дождитесь удаления выполненных задач."); return }
        if launchMode == .demo {
            guard !mutationAccessBlocked else { onFailure?(mutationRecoveryProblem ?? MutationRecoveryFailure.pendingVerification.errorDescription ?? "Требуется проверка."); return }
            do {
                let existingTaskIDs = Set(snapshot.tasks.map(\.id))
                try demoAdapter?.perform(invocation)
                if let demoAdapter {
                    snapshot = demoAdapter.snapshot()
                    if !snapshot.calendars.contains(where: { $0.id == selectedCalendarID }) {
                        selectedCalendarID = CalendarNavigation.selectedID(nil, calendars: snapshot.calendars)
                    }
                    selectedTaskListID = TaskWorkspaceLayout.validSelectedListID(selectedTaskListID, lists: snapshot.taskLists)
                    visibleCalendarIDs = Set(snapshot.calendars.map(\.id))
                }
                statusMessage = "ДЕМО · действие обработано локальным fixture-адаптером; Google не вызывался."
                if let onVerified {
                    let verifiedTask: GoogleTask?
                    if invocation.operation == .taskInsert {
                        verifiedTask = snapshot.tasks.first { !existingTaskIDs.contains($0.id) }
                    } else if invocation.operation == .taskPatch || invocation.operation == .taskMove {
                        let taskID = Self.argument("task", in: invocation)
                        let listID = Self.argument(invocation.operation == .taskMove ? "destinationTasklist" : "tasklist", in: invocation)
                        verifiedTask = snapshot.tasks.first { $0.id == taskID && $0.taskListID == listID }
                    } else { verifiedTask = nil }
                    guard let verifiedTask else { throw GWSFailure.mutationNotVerified }
                    onVerified(.taskVerified(verifiedTask))
                }
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
        guard !googleTransportSettings.requiresRestart, !googleTransportSettings.signingIn, transportContext?.recoveryOnly != true else {
            onFailure?("Перезапустите приложение для применения настроек Google.")
            return
        }
        guard !mutationJournal.isBlocked else {
            refreshMutationRecoveryState()
            onFailure?(mutationJournal.blockingFailure?.errorDescription ?? "Требуется проверка изменения.")
            return
        }
        mutationInFlight = true
        statusMessage = "Сохранение…"
        let path = gwsPath
        let context = transportContext
        let metadataMigration = reminderCoordinator.metadataMigrationPreparation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<GWSMutationResult, Error>
            do {
                guard let self, let runner = self.runner else { throw GWSFailure.forbiddenOperation }
                guard let context else { throw GWSFailure.forbiddenOperation }
                let reader = GWSReadClient(factory: try context.factory(configuredGWSPath: path), runner: runner)
                outcome = .success(try RecoverableMutationService(runner: runner, journal: self.mutationJournal, beforeCompletion: { result, pending in
                    if pending.operation == .taskMove, let sourceID = pending.sourceTaskID, case .taskVerified(let task) = result {
                        try metadataMigration.prepare(from: sourceID, to: task.id)
                    }
                }).perform(invocation, reader: reader))
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationInFlight = false
                self.refreshMutationRecoveryState()
                switch outcome {
                case .success(let result) where result.isReadBackVerified:
                    self.statusMessage = "Изменение подтверждено точным чтением Google."
                    do { try self.installVerifiedMutation(invocation, result: result) }
                    catch { onFailure?("Не удалось применить подтверждённое изменение."); return }
                    let mutationStillCurrent = self.snapshotAcceptance.currentGuard()
                    if onVerified == nil, case .taskVerified(let task) = result {
                        if invocation.operation == .taskMove, let sourceID = Self.argument("task", in: invocation) {
                            do { try await self.reminderCoordinator.migrateTaskMetadata(from: sourceID, to: task.id) }
                            catch {
                                self.statusMessage = "Перенос задачи подтверждён. Локальные данные сохранены на целевой доске, но обновление уведомлений ещё не завершено."
                                onFailure?(self.statusMessage)
                                return
                            }
                        }
                        await self.reminderCoordinator.reconcile(tasks: [task], stillCurrent: mutationStillCurrent)
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
                    onVerified?(result)
                    onSuccess?()
                    if thenRefresh { self.refreshAfterMutation(invocation, result: result) }
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

    func recheckPendingMutation(onSuccess: (() -> Void)? = nil, thenRefresh: Bool = true,
                                onVerified: ((GWSMutationResult) -> Void)? = nil) {
        guard !mutationInFlight, pendingMutation?.resourceID != nil, let runner else { return }
        mutationInFlight = true
        statusMessage = "Проверяем сохранение…"
        let path = gwsPath
        let context = transportContext
        let journal = mutationJournal
        let pendingInvocation = pendingMutation?.invocation(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        let pendingOperation = pendingMutation?.operation
        let pendingSourceTaskID = pendingMutation?.sourceTaskID
        let expectedPendingID = pendingMutation?.id
        let metadataMigration = reminderCoordinator.metadataMigrationPreparation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<GWSMutationResult, Error>
            do {
                guard let context else { throw GWSFailure.forbiddenOperation }
                let reader = GWSReadClient(factory: try context.factory(configuredGWSPath: path), runner: runner)
                result = .success(try RecoverableMutationService(runner: runner, journal: journal, beforeCompletion: { result, pending in
                    if pending.operation == .taskMove, let sourceID = pending.sourceTaskID, case .taskVerified(let task) = result {
                        try metadataMigration.prepare(from: sourceID, to: task.id)
                    }
                }).recheck(reader: reader, expectedID: expectedPendingID))
            } catch { result = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationInFlight = false
                self.refreshMutationRecoveryState()
                switch result {
                case .success(let verified):
                    self.statusMessage = "Изменение подтверждено точным чтением Google."
                    guard let pendingInvocation else { return }
                    do { try self.installVerifiedMutation(pendingInvocation, result: verified) }
                    catch { self.statusMessage = "Не удалось применить подтверждённое изменение."; return }
                    let mutationStillCurrent = self.snapshotAcceptance.currentGuard()
                    if onVerified == nil, case .taskVerified(let task) = verified {
                        if pendingOperation == .taskMove, let sourceID = pendingSourceTaskID {
                            do { try await self.reminderCoordinator.migrateTaskMetadata(from: sourceID, to: task.id) }
                            catch {
                                self.statusMessage = "Перенос задачи подтверждён. Локальные данные сохранены на целевой доске, но обновление уведомлений ещё не завершено."
                                return
                            }
                        }
                        await self.reminderCoordinator.reconcile(tasks: [task], stillCurrent: mutationStillCurrent)
                    }
                    onVerified?(verified)
                    onSuccess?()
                    // A domain refresh reconciles deletion reminders using complete, confirmed data.
                    if thenRefresh { self.refreshAfterMutation(pendingInvocation, result: verified) }
                case .failure(let error):
                    self.statusMessage = (error as? LocalizedError)?.errorDescription ?? "Проверка пока не завершена."
                }
            }
        }
    }

    func refreshMutationRecoveryState() {
        guard !mutationInFlight else { return }
        let state = mutationJournal.review()
        pendingMutation = state.pending
        mutationRecoveryProblem = state.pending == nil ? state.failure?.errorDescription : nil
        mutationJournalBusy = state.failure == .journalBusy
    }

    func acknowledgeManuallyReconciledMutation() {
        guard !mutationInFlight, !mutationJournalBusy else { return }
        do {
            try mutationJournal.releaseAfterManualReview(expectedID: pendingMutation?.id)
            pendingMutation = nil
            mutationRecoveryProblem = nil
            mutationJournalBusy = false
            statusMessage = "Проверка вручную отмечена пользователем. Автоматическое подтверждение Google не заявляется."
            refresh()
        } catch { mutationRecoveryProblem = "Не удалось обновить журнал проверки. Запись остаётся заблокированной." }
    }

    private var pendingMoveMetadataProtection: () -> Set<String> {
        let journal = mutationJournal
        let store = metadataStore
        return {
            let review = journal.review()
            if review.failure == .journalBusy || review.failure == .corruptJournal {
                // Until the lease/journal can be read, no reminder ID is safe to prune.
                return store.reminderTaskIDs()
            }
            guard let pending = review.pending, pending.operation == .taskMove, let sourceID = pending.sourceTaskID else { return [] }
            return [sourceID]
        }
    }

    func refreshTasksAfterSave(task: GoogleTask? = nil, taskListID: String? = nil, sourceTaskListID: String? = nil) {
        guard launchMode == .normal else { refresh(); return }
        guard let listID = task?.taskListID ?? taskListID else { requestNormalRefresh(scope: .tasks, force: true); return }
        var lists = requiredVerifiedTaskListIDs.union([listID])
        if let sourceTaskListID { lists.insert(sourceTaskListID) }
        requestTargetedRefresh(taskListIDs: lists)
    }

    private func refreshAfterMutation(_ invocation: ProcessInvocation, result: GWSMutationResult) {
        guard launchMode == .normal else { refresh(); return }
        let params = WorkspaceSnapshotReducer.parameters(invocation)
        switch result {
        case .eventVerified(let event): requestTargetedRefresh(calendarIDs: [event.calendarID])
        case .taskVerified:
            let lists = requiredVerifiedTaskListIDs.union(WorkspaceSnapshotReducer.affectedTaskListIDs(invocation: invocation, result: result))
            requestTargetedRefresh(taskListIDs: lists)
        case .taskListVerified: requestTaskListStructureRefresh()
        case .resourceDeleted:
            switch invocation.operation {
            case .taskDelete:
                if let list = params["tasklist"] { requestTargetedRefresh(taskListIDs: [list]) }
            case .eventDelete:
                if let calendar = params["calendarId"] { requestTargetedRefresh(calendarIDs: [calendar]) }
            case .taskListDelete: requestTaskListStructureRefresh()
            default: break
            }
        case .requestAccepted: break
        }
    }

    private func requestTaskListStructureRefresh() {
        guard let runner else { return }
        refreshRequestSequence += 1
        let query = WorkspaceRefreshQuery(range: currentRange(), scope: .targeted, requestID: refreshRequestSequence, refreshTaskLists: true)
        requestRefresh(query, runner: runner)
    }

    private func requestTargetedRefresh(taskListIDs: Set<String> = [], calendarIDs: Set<String> = []) {
        guard let runner else { return }
        refreshRequestSequence += 1
        let range = currentRange()
        let query = WorkspaceRefreshQuery.targeted(range: range, coverage: snapshot.calendarCoverage,
                                                   taskListIDs: taskListIDs, calendarIDs: calendarIDs,
                                                   requestID: refreshRequestSequence)
        requestRefresh(query, runner: runner)
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
        let context = transportContext
        let tasks = snapshot.tasks
        let taskCoordinator = reminderCoordinator
        let eventCoordinator = eventReminderCoordinator
        Task {
            await ReminderLifecycleReconciliation.perform(for: trigger) {
                await taskCoordinator.reconcile(tasks: tasks)
                guard let factory = try? context?.factory(configuredGWSPath: path) else { return }
                let reader = GWSReadClient(factory: factory, runner: runner)
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
        let context = transportContext
        Task {
            guard let factory = try? context?.factory(configuredGWSPath: path) else { return }
            let reader = GWSReadClient(factory: factory, runner: runner)
            await eventReminderCoordinator.reconcile(using: reader)
        }
    }

    func updatePath(_ value: String) {
        gwsPath = value
        saveSettings()
    }

    func setAppearance(_ value: Appearance) {
        DemoPerformanceProbe.shared.begin(.appearance)
        appearance = value
        saveSettings()
    }

    func setSection(_ value: Section) {
        DemoPerformanceProbe.shared.begin(.section)
        section = value
        searchText = ""
    }

    func requestSidebarToggle() { sidebarToggleRequestID += 1 }

    func updateShortcut(_ binding: WorkspaceShortcutBinding, for action: WorkspaceShortcutAction) -> String? {
        var settings = shortcutSettings
        if let problem = settings.update(binding, for: action) { return problem }
        shortcutSettings = settings
        settings.save(to: defaults)
        return nil
    }

    func resetShortcuts() {
        shortcutSettings = WorkspaceShortcutSettings()
        shortcutSettings.save(to: defaults)
    }

    func keyboardShortcut(_ action: WorkspaceShortcutAction) -> KeyboardShortcut {
        let binding = shortcutSettings[action]
        var modifiers: EventModifiers = []
        if binding.command { modifiers.insert(.command) }
        if binding.option { modifiers.insert(.option) }
        if binding.control { modifiers.insert(.control) }
        if binding.shift { modifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(binding.key.first!), modifiers: modifiers)
    }

    func requestSearchFocus() { searchFocusRequestID += 1 }
    func requestNewItem() { guard !mutationsBlocked else { return }; newItemRequestID += 1 }

    func moveDate(_ amount: Int) {
        DemoPerformanceProbe.shared.begin(.range)
        if let date = CalendarDatePolicy.moving(activeDate, by: amount, mode: calendarMode, timeZone: selectedTimeZone) {
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
        CalendarDatePolicy.range(containing: activeDate, mode: calendarMode, timeZone: selectedTimeZone)
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
    private let smoothScrolling = SmoothScrollController()

    func applicationDidFinishLaunching(_ notification: Notification) { smoothScrolling.start() }
    func applicationWillTerminate(_ notification: Notification) { smoothScrolling.stop() }
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
        DemoPerformanceProbe.shared.startIfRequested(arguments: ProcessInfo.processInfo.arguments, mode: mode)
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
            CommandGroup(replacing: .newItem) {
                Button("Поиск") { model.requestSearchFocus() }.keyboardShortcut(model.keyboardShortcut(.search))
                Button("Сегодня") { model.goToToday() }.keyboardShortcut(model.keyboardShortcut(.today))
                Button("Новое событие или задача") { model.requestNewItem() }.keyboardShortcut(model.keyboardShortcut(.newItem))
                Button("Синхронизировать") { model.refresh() }.keyboardShortcut(model.keyboardShortcut(.refresh))
                    .disabled(model.syncState == .syncing || model.mutationInFlight)
            }
            CommandMenu("Навигация") {
                Button("Свернуть / развернуть боковое меню") { model.requestSidebarToggle() }
                    .keyboardShortcut(model.keyboardShortcut(.toggleSidebar))
                Divider()
                Button("Календарь") { model.setSection(.calendar) }.keyboardShortcut(model.keyboardShortcut(.calendar))
                Button("Задачи") { model.setSection(.tasks) }.keyboardShortcut(model.keyboardShortcut(.tasks))
                Divider()
                Button("Предыдущий период") { model.moveDate(-1) }.keyboardShortcut(model.keyboardShortcut(.previousPeriod))
                Button("Следующий период") { model.moveDate(1) }.keyboardShortcut(model.keyboardShortcut(.nextPeriod))
            }
        }
    }
}
#endif
