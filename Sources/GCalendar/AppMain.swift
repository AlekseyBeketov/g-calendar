import AppKit
import Foundation
import SwiftUI

private enum NormalRefreshPayload {
    case full(GWSCompletedFullSync)
    case calendarRange(WorkspaceSnapshot)
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    enum Section: String, CaseIterable { case calendar = "Календарь", tasks = "Задачи" }
    enum CalendarMode: String, CaseIterable { case week = "Неделя", day = "День" }
    enum TaskFilter: String, CaseIterable { case all = "Все", today = "Сегодня", upcoming = "Предстоящие", overdue = "Просроченные" }
    enum SyncState { case idle, syncing, updated, stale, setupRequired }
    enum Appearance: String, CaseIterable, Identifiable { case system = "Система", light = "Светлая", dark = "Тёмная"; var id: String { rawValue } }

    @Published var snapshot: WorkspaceSnapshot
    @Published var section: Section = .calendar
    @Published var calendarMode: CalendarMode = .week
    @Published var taskFilter: TaskFilter = .all
    @Published var selectedCalendarID: String?
    @Published var visibleCalendarIDs: Set<String>?
    @Published var selectedTaskListID: String?
    @Published var activeDate = Date()
    @Published var searchText = ""
    @Published var syncState: SyncState = .idle
    @Published var statusMessage = ""
    @Published var gwsPath: String
    @Published var appearance: Appearance
    @Published var mutationInFlight = false
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
    private let defaults: UserDefaults
    private let demoAdapter: DemoWorkspaceAdapter?
    private var ledgerAcceptanceSession: SyntheticLedgerAcceptanceSession? = nil
    private let notificationStatusProvider: NotificationStatusProviding?
    private var refreshCoordinator = LatestWinsRefreshCoordinator<WorkspaceRefreshQuery>()

    init(mode: AppLaunchMode = .normal, defaults suppliedDefaults: UserDefaults? = nil, scheduler suppliedScheduler: ReminderScheduling? = nil) {
        launchMode = mode
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
            let scheduler: ReminderScheduling = suppliedScheduler ?? (mode == .demo ? NoopReminderScheduler() : UserNotificationScheduler())
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
            return
        }
        if launchMode == .ledgerAcceptance {
            refreshSyntheticAcceptance()
            return
        }
        guard launchMode == .normal else { return }
        requestNormalRefresh(scope: .full)
    }

    func refreshCalendarRangeIfNeeded() {
        guard launchMode == .normal else { refresh(); return }
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let range = currentRange()
        if let active = refreshCoordinator.active,
           active.key.scope == .full, active.key.range == range {
            _ = refreshCoordinator.request(active.key)
            return
        }
        if refreshCoordinator.active == nil, snapshot.calendarCoverage?.covers(range) == true { return }
        guard snapshot.fetchedAt != .distantPast else { refresh(); return }
        let query = WorkspaceRefreshQuery(range: range, scope: .calendarRange)
        guard let request = refreshCoordinator.request(query) else { return }
        startNormalRefresh(request, runner: runner)
    }

    private func requestNormalRefresh(scope: WorkspaceRefreshScope) {
        guard let runner else { syncState = .setupRequired; statusMessage = "Google transport недоступен."; return }
        let query = WorkspaceRefreshQuery(range: currentRange(), scope: scope)
        guard let request = refreshCoordinator.request(query) else { return }
        startNormalRefresh(request, runner: runner)
    }

    private func startNormalRefresh(_ request: RefreshTicket<WorkspaceRefreshQuery>, runner: GWSProcessRunning) {
        syncState = .syncing
        statusMessage = request.key.scope == .full ? "Полная синхронизация…" : "Обновление календарного диапазона…"
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
                case .failure(let error):
                    self.syncState = self.snapshot.fetchedAt == .distantPast ? .setupRequired : .stale
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
        selectedTaskListID = selectedTaskListID ?? refreshed.taskLists.first?.id
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
        mutationInFlight = true
        statusMessage = "Сохранение…"
        let path = gwsPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<GWSMutationResult, Error>
            do {
                guard let self, let runner = self.runner else { throw GWSFailure.forbiddenOperation }
                let executable = try GWSExecutableResolver().resolve(configuredPath: path.isEmpty ? nil : path)
                let reader = GWSReadClient(factory: GWSCommandFactory(executableURL: executable), runner: runner)
                outcome = .success(try GWSMutationService(runner: runner).perform(invocation, reader: reader))
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationInFlight = false
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
                    if thenRefresh { self.refresh() }
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

    func goToToday() { activeDate = Date(); refreshCalendarRangeIfNeeded() }

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
        let today = DateOnly(date: Date())
        return snapshot.tasks.filter { task in
            guard !task.deleted, selectedTaskListID == nil || task.taskListID == selectedTaskListID else { return false }
            guard searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText) else { return false }
            switch taskFilter {
            case .all: return true
            case .today: return task.due == today && !task.completed
            case .upcoming: return (task.due == nil || task.due! >= today) && !task.completed
            case .overdue: return task.due.map { $0 < today } == true && !task.completed
            }
        }
    }

    func taskGroups() -> [(String, [GoogleTask])] {
        let today = DateOnly(date: Date())
        let active = visibleTasks.filter { !$0.completed }
        return [("Просрочено", active.filter { $0.due.map { $0 < today } == true }),
                ("Сегодня", active.filter { $0.due == today }),
                ("Предстоящие", active.filter { $0.due.map { $0 > today } == true || $0.due == nil }),
                ("Готово", visibleTasks.filter(\.completed))]
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
                .frame(minWidth: 760, minHeight: 560)
                .preferredColorScheme(model.preferredColorScheme)
                .task {
                    if launchMode == .notificationStatus { await model.queryNotificationStatusAndExit() }
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
            }
        }
    }
}
#endif
