## Context

См. proposal и `docs/requirements.md`. Исходный репозиторий практически пуст; продуктовые и security ограничения зафиксированы в `docs/ACCEPTANCE_CONTRACT.md`. Локальный `gws` авторизован и прошёл CalendarList/TaskLists read-only smoke по предоставленной проверке, но приложение не должно читать его credential store. SwiftUI executable вручную собран, упакован в минимальный `.app`, запущен и закрыт из CLT. Текущий SwiftPM manifest compiler падает с undefined `PackageDescription.Package.__allocating_init(... swiftLanguageVersions ...)` даже на стандартном шаблоне; полноценный Xcode не выбран/не подтверждён. Это реальное build risk для coder, а не повод молча заявить SPM success.

## Goals / Non-Goals

**Goals:**
- Native application UI/lifecycle, local read-only Google integration and cache; week/day + task workflows; safe user-triggered writes validated with fixtures plus an owner-approved create/read-back smoke limited to synthetic objects; opt-in task and local-only timed Calendar event reminders.
- A reproducible app bundle build from the checked-in source and scripts, even if the active SwiftPM installation requires a documented direct-compiler fallback.
- A clear security boundary between UI operations, allowlisted gws calls and forbidden auth/credential operations.

**Non-Goals:**
- Google parity, a web wrapper, paid/hosted services, background push receiver, new OAuth consent flow or credential migration.
- Production/personal-object mutations, invitations/email, notification permission prompts during automated tests, login helpers or public release signing. The separately authorized live acceptance may operate only on this run's own synthetic event/task, with exact GET before and after each mutation and private IDs; no unrelated resource or broad cleanup is in scope.
- Pending offline-write queue or claims that local task/event reminder times are Google-synced.

## Decisions

Current owner decision 2026-10-05: Pixel Paper is the approved visual foundation; only the Color Atlas compact task-list metadata layout is adopted. See `design/DESIGN.md` and the unified `docs/plans/2026-10-05-final-product-completion.md`. Rejected variants were removed. Implementation and fixture/computer-use testing have resumed, including final code plus visual spacing acceptance for modal and primary surfaces. Historical environment notes below are checkpoints, not current build/test verdicts.

1. **Native UI: SwiftUI first, small AppKit bridges.** This is a single-platform macOS product. Use `NavigationSplitView`, native toolbar/list/search and semantic/system appearance. AppKit is limited to gaps such as NSApplication activation or window behavior; no embedded browser. Tauri is deferred: Cargo/Rust is absent, and its WebView/JS-to-Rust stack adds no MVP benefit. Keep `docs/ui.md` as a visual contract, not an instruction to build a web app.

2. **Google adapter: existing gws as a child process, never shell.** A `GWSExecutableResolver` uses a user-configured path and safe standard candidates (including `$HOME/.local/bin/gws`); it must not assume the GUI inherits interactive PATH. `ProcessRunner` receives URL and separate arguments, sets a controlled working directory and HOME, captures status/stdout/stderr, and enforces a timeout/output limit. It does not read, export, log, or copy tokens; it never runs login/auth/status-debug commands. Command factory allowlists calendar/list/events-list, tasklists-list/tasks-list for sync and explicitly-supported writes only from user-triggered UI handlers. No arbitrary service/method input.

3. **Typed domain layer, pagination and last-good cache.** Convert gws JSON to app-owned event/task/calendar models. List pages must be fully traversed; repeated event expansion and timeZone are explicit query choices. API errors, process errors, malformed JSON, and partial pagination produce an error state, not an empty collection. Commit a new cached snapshot atomically only after all required pages succeed. On failure preserve prior cache and mark stale/error. No offline mutation queue. Logs contain operation category and safe error metadata only, never titles, email, raw requests or auth material.

5. **User-triggered writes with explicit boundaries.** UI edits remain drafts until Save. Real create/update/delete operations are only started from the corresponding user action; deletion requires confirmation. Read-only calendars expose no writes. Automated fixture tests inject a clearly-named fake `ProcessRunner` and assert exact command/argument construction. Separately, the owner has authorized a current-run-only synthetic event/task lifecycle through the actual app UI/adapter. Keep exact IDs in a private local ledger; GET that exact ID and validate its unique marker before each mutation, then GET it again and verify the result. Delete only exact objects created by this run. Personal objects are never touched. Event attendee/invite fields are not part of MVP. Recurring event instances are displayable but not editable until exact scope UI is implemented.

5. **Separate Google fields from local reminder extensions.** Google Tasks `due` maps to calendar date only. Store task reminder time, favorites, and a user's exact local time for one supported timed non-recurring Calendar event separately in app support data keyed by stable resource identity (`calendarID + eventID/occurrence`); never send local fields in Google JSON and never mirror Google reminder preferences as local defaults. Do not prune an event reminder merely because its event is outside the latest range query; require exact removal evidence or explicit user action. Cache and sidecars contain no credentials.

6. **Notification scheduler behind a protocol.** A `ReminderScheduling` boundary wraps `UNUserNotificationCenter`; the UI asks permission only after the user explicitly enables a reminder. Stable identifiers deduplicate. Task completion/deletion cancels its reminder; event reminder clear/cancel uses composite identity and exact removal evidence. Use full date components including seconds; reconcile after activation/wake without claiming delivery. Expose read-only authorization/pending/delivered counts. Unit tests use fake scheduler; OS banner visibility and Focus/sleep behavior are not automated-pass claims. Closing a window hides it; explicit Quit exits the process.

7. **Build strategy is an engineering gate.** First investigate the known SwiftPM manifest-link failure on the actual environment without installing tools or mutating global configuration. If a safe, checked-in `swift build`/`swift test` route is established, use it. Otherwise use a documented script with pinned assumptions that invokes existing `swiftc` and Apple SDK frameworks, assembles `dist/g-calendar.app` with stable bundle identifier and Info.plist, and runs a local focused fixture test executable. Record the true SwiftPM failures in `docs/verification.md`; do not call a fallback `swift build` or `swift test`. No signing, notarization, installer or login item.

8. **Isolated synthetic demo mode.** An explicit app argument selects only synthetic fixtures and a separate data directory; it MUST not invoke `gws`, load personal app cache, or request UserNotifications permission. This permits native GUI smoke and visual QA without showing personal Calendar/Tasks content.

## Risks / Trade-offs

- [SwiftPM/CLT incompatibility] → coder reproduces on this machine, searches only safe local alternatives; if unresolved, direct compiler script and transparent failed-SwiftPM evidence.
- [gws CLI changes or schema discovery/network failure] → pin/document tested version where possible, strict JSON/error parsing, compatibility fixtures, user-configurable executable, and stale cache.
- [GUI PATH/config mismatch] → absolute executable resolution, preserve current user HOME/config lookup, explicit settings validation without displaying credentials.
- [unauthorized writes] → prohibit production/personal mutations; allow only current-run synthetic event/task operations explicitly recorded in `docs/HUMAN_APPROVALS.md`, with exact GET before and after each mutation. Fixture tests remain the default for all other writes; read-only calendar enforcement and unsupported recurrence/invitations remain explicit.
- [Quota and network failure] → user-triggered/controlled refresh, local cache, respectful retry/backoff for transient errors; never claim permanent free API usage.
- [Task due-time mismatch] → date-only Google model and separate labelled local reminder store.
- [Notification delivery differs by settings/sleep] → request permission in context, show permission status, document OS limitations, label end-to-end banner delivery needs-human-verification.
- [Private data leaks through cache/logs/screenshots] → local-only cache path, no titles in default logs, synthetic or empty screenshot fixture, review tracked files before acceptance.

## Migration Plan

No existing application data is migrated. On first run, show a setup state that locates the configured gws executable and performs only list/read operations. Successful reads atomically seed a cache; failures preserve any prior snapshot and provide retry. Local reminder metadata is versioned separately. Upgrade errors preserve the last valid data and report a safe diagnostic. Rollback means quit and remove/replace only the newly-built `dist/g-calendar.app`; do not delete user cache automatically.

## Open Questions

- Can the installed SwiftPM be repaired by a source-level manifest/build invocation, without changing system tool installation or configuration? Coder must test and decide based on exit status.
- Is direct `swiftc` adequate for both focused tests and repeatable app bundling while the SwiftPM defect persists? Must be demonstrated with actual commands.
- Exact minimum macOS deployment target and recurrence boundaries should follow successful SDK compile and fixture tests; no unsupported target should be hard-coded before validation.
- Synthetic Google write/read-back smoke is explicitly owner-authorized for this completion run but remains not-run until documented. Production writes, visible notification permission/banner, signing/notarization, and login behavior remain human approval/verification gates.


## Workspace improvements (2026-10-10)


Этап 1: добавить модель сочетаний, сохранение в UserDefaults, проверку конфликтов и сброс. Настройки редактируют все команды рабочего пространства; ⌘B меняет NavigationSplitViewVisibility через запрос модели. Фиксированные ⌘Q, Return/Escape и навигацию стрелками не переназначать. Проверить сохранение, конфликты и defaults.

Этап 2: редактор задачи получает отдельный переключатель и DatePicker локального напоминания. После read-back успешной записи сохранить напоминание для полученного task ID; сбой напоминания не повторяет Google запись. Задать Info.plist alert style и уникальное актуальное имя icon resource. Показать системный стиль и путь к настройкам. Не изменять глобальные настройки macOS.

Этап 3: новый сервис LoginItemSettings на SMAppService.mainApp. Настройки читают реальный статус enabled/requiresApproval/notRegistered/notFound, показывают ошибку и ссылку на системные настройки; demo не регистрирует автозапуск.

Этап 4: чистая сортировка writable first, затем локализованное имя и ID; контекст по умолчанию выбирает writable. Существующий явный выбор сохраняется пока присутствует, видимость календарей независима. Проверить пустой список и только read-only.

Этап 5: заменить только иконку раскрытия календарных задач на down/up; сохранить действие, счётчик и accessibility.

Этап 6: общий AppKit cursor rect для SwiftUI и нативных интерактивных контролов. Область совпадает с hit region, disabled исключаются, текстовые поля сохраняют I-beam. Проверить cleanup курсора; добавить правило в AGENTS.md и docs/ui.md.

Этап 7: nil selectedTaskListID означает все доски и является default. Сохранить nil после refresh и удаления выбранной доски. В sidebar и selector добавить Все доски. Колонки показываются только в этом scope и группируются по TaskList с устойчивыми составными task identity; фильтры применяются ко всем доскам. Конкретная доска всегда список. Задать явную ширину колонок и один вертикальный scroll внутри каждой колонки без перекрытия. Проверить фильтры, scope, сортировку, keyboard identities и узкое окно.

Этап 8: редактор всегда показывает Picker доски. Новый taskMove invocation с source tasklist/task и destinationTasklist, пустым body, авторизацией userSave. Проверить точное чтение целевой и отсутствие в исходной доске, сохранить ID и локальные metadata. Добавить поддержку demo, refresh scope, journal recovery. Проверить успешный перенос, неподтверждённый результат и recheck без повторной записи.
