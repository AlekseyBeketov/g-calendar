# Завершение g-calendar с утверждённым Pixel Paper

> **Исторический ExecPlan.** Основной продуктовый объём и локальная приёмка завершены 2026-10-07; этот файл сохранён как журнал решений и доказательств и не является текущим рабочим планом. Его исторические checkpoints не описывают текущие Git/remote state. Актуальные follow-up задачи перечислены в [roadmap](../roadmap.md); pointer-cursor follow-up описан в [отдельном плане](2026-10-08-pointer-cursor.md).

**Goal:** Последовательно завершить открытые задачи приложения, надёжность Google-записей и Pixel Paper UI с task metadata из Color Atlas, подтвердив результат тестами и computer use.

**Architecture:** Сохранить SwiftUI/AppKit, allowlisted gws process, exact read-back, date-only Tasks, независимые Calendar/Tasks refresh, локальные reminders и синтетический demo. Обновлять существующие границы; не вводить backend, UI packages или offline write queue.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, UserNotifications; direct swiftc build/test scripts; repo-local OpenSpec g-calendar-mvp.

Этот живой ExecPlan составлен по `/Users/alexbeketov/.codex/Plans.md`. Обновлять Progress, Surprises & Discoveries, Decision Log и Outcomes по свежим данным. Владелец 2026-10-05 разрешил агенту коммит и пуш текущего checkpoint, после чего продолжить цель. GitHub release, лицензия и notarization этим не подтверждаются. Этот план заменяет прежние quality/screenshot планы, а OpenSpec checklist остаётся формальным перечнем задач.

## Purpose / Big Picture


После завершения пользователь сможет нажимать любую часть строки sidebar, быстро просматривать компактный список задач со сроками и тегами, пользоваться выровненной неделей, создавать объекты в соразмерных формах и безопасно восстановиться после неподтверждённого сохранения. Приёмка демонстрируется тестами и actual built app в изолированном synthetic demo. Внешность сверяется с `design/DESIGN.md` и двумя сохранёнными референсами; PNG не задаёт семантику дат и не доказывает рабочий клик.

## Progress


- [x] (2026-10-05) Утверждены Pixel Paper + metadata Color Atlas; сохранены два референса, удалены отвергнутые варианты, объединён план. Tests/computer use и собственные disposable fixtures разрешены.
- [x] (2026-10-05–06) Исправлены semantic read-back, durable journal и interprocess lease/attempt ownership. Два narrow actual-app Google lifecycle завершили по 11 шагов и удалили собственные объекты.
- [x] (2026-10-06–07) Реализованы и внешне проверены full-row targets, independent calendar selection/visibility, compact metadata/due order, native keyboard/search, pinned calendar/header/overflow, themes/states и все modal/system insets.
- [x] (2026-10-07) Финальная optimized сборка run-54154: exit 0. Model suites ordinary/optimized по 440 assertions; native UI suite 20; installer fixtures 26. Последний optimized model run повторён после UI fix.
- [x] (2026-10-07) Финальный busy viewport и Cmd+N regression исправлены и подтверждены в коротком окне. Ready Cmd+N открывает editor; busy не создаёт editor/вкладку. Длинный recovery body прокручен до инструкции при доступном footer.
- [x] (2026-10-07) GUI baseline собран, метод ограничен AppKit update, предварительные бюджеты заданы после измерений. Scroll schema 1 invalidated; schema 2 handler p95 0,220 ms на 242 callbacks. CPU/RSS baseline записан; FPS/GPU/peak resource attribution не измерены.
- [x] (2026-10-07) Реализованы source/pinned-release installers, DMG/ZIP, signing/notary scripts, upgrade/rollback/uninstall. Actual mounted DMG install и запуск отдельной копии прошли; два разных binary hashes, rollback/data/backup preservation и own detach подтверждены.
- [x] (2026-10-07) Обновлены docs/OpenSpec/status/roadmap. Текущее продолжение без commit/push/publication; личные файлы и ignored caches сохранены.

Публичный подписанный выпуск не входит в локальную приёмку: нужны credentials/license/release approval и чистый Mac. Реальный public pin создаётся только после выпуска. Голосовой VoiceOver и человеческое наблюдение notification banner остаются внешней приёмкой, явно не выданы за выполненные.

## Surprises & Discoveries


Следующие наблюдения 5–6 октября описывают историю диагностики; их текущий итог приведён в Progress и Outcomes.

На предыдущем demo обнаружены горизонтальное исчезновение hour axis, низкая читаемость disabled read-only event fields, чрезмерная высота list manager и работа только вложенной кнопки «Изменить». Эти дефекты исправлены в исходниках и ожидают повторной внешней проверки. Субагент keyboard navigation остановился по workspace credits, оставив неполную интеграцию; основной агент завершил обработчики и fixture coverage на текущей модели.

Существующие future-only Upcoming, Without due, list default, collapsible undated region и независимые refresh сохранены. Empty notes и отсутствующие notes семантически эквивалентны; непустые отличия по-прежнему отклоняются. Regression fixture первоначально завершился mutationNotVerified, после исправления проходит.

Google Calendar округлил отправленный timestamp до секунд: live difference -332 ms при правильном ID/названии. Теперь payload нормализуется до секунд до journaling; fixture с настоящим +1 second mismatch остаётся отрицательным. Deleted Calendar event может вернуть только id/status=cancelled; Tasks возвращает deleted=true. Проверка tombstone сначала сравнивает ID, затем принимает отсутствие active object. Ошибка с «404» внутри ID не считается HTTP not found.

Calendar DELETE в live run иногда оставлял pendingVerification при уже удалённом объекте. Корень nonzero CLI ответа не объявлен доказанным. После nonzero DELETE допускается только один exact GET; timeout и неизвестный INSERT остаются blocked, повторной записи нет. Два lifecycle завершились после явного restart cleanup (11 шагов, deleted=3); последний fresh run остановился до первой записи по timeout.

После закрытия старой обычной копии с разрешения владельца и запуска одного собственного demo восстановлены native clicks. Task-list icon/text/blank/edge activation, task create/edit-cancel/complete/reopen и task/reminder screenshots подтверждены. Открытие Settings по-прежнему завершает SkyComputerUseService: EXC_BREAKPOINT/SIGTRAP, Array.remove(at:), а g-calendar остаётся живым. Primary issue reports 43573/34432 описывают такой же stack; точная внутренняя причина не доказана. Calendar screenshot обнаружил обрезание 08:00 сверху.

Actual UserNotifications разрешены (alerts/sound enabled, delegate ready); один test request появился в Notification Center. Видимый баннер требует отдельного человеческого наблюдения. Full app build после последнего explicit-ledger изменения отклонил automatic approval review, сославшись на общее правило AGENTS.md, хотя ранее сборки выполнялись. Запрошено точное разрешение, обход отказа не применяется.

Дополнительный code audit обнаружил stale selectedTaskListID после normal refresh, если список удалён с другого клиента. installRefreshedSnapshot теперь использует validSelectedListID: сохраняет существующий выбор, выбирает первый оставшийся или nil при пустой коллекции. Четыре fixtures проверяют эти случаи. Overdue predicate исключает completed/deleted/today; четыре fixtures проверяют статус. Строка показывает отдельный overdue icon и объявляет статус; local metadata передаётся accessibilityValue, поскольку родительский Button имеет явный label. Это code + fixture evidence; UI и VoiceOver pass пока открыты.

## Decision Log


2026-10-07: локальную installer implementation/acceptance отделили от public release acceptance, потому что владелец поручил разработать установщики, а публикацию и signing credentials не предоставил. Реальный публичный pin не подменяется placeholder; source one-command из checkout и local DMG доступны сейчас. Внешние gate сохранены в PENDING_DECISIONS/RELEASING.

2026-10-07: для переполнения detail изучены 4 варианта: fixedSize/layout priority для шапки, конечный GeometryReader viewport, native bounded NSScrollView и clipping. Первые локальные fixedSize/workspace-only варианты не дали pass; выбран конечный размер detail/workspace и ограниченный recovery text, clipping только на внешней границе. Документация SwiftUI получена через официальный Context7; Apple Beyond scroll views — https://developer.apple.com/videos/play/wwdc2023/10159/. Native clip используется отдельно для закреплённого календаря. После изменения маленькое окно проходит внешнюю проверку.

2026-10-07: Cmd+N заменяет .newItem, чтобы единственная команда создания не конкурировала с native New Window. Busy guard действует на модель и UI; ready/busy проверены отдельно.

Решение 2026-10-06, агент: W3C contrast thresholds сравнивать без округления; использовать явный sRGB в native adapter. Сохранить единый источник color roles в ThemePalette и проверять обе темы, selected alpha backgrounds и значимые boundaries. Дополнительно проверить caption/ink над произвольным calendar color и actual native primary button text. Кодовый spacing audit не закрывает visual acceptance; runtime font/control appearance проверяется на current bundle.

Решение 2026-10-06, агент: task arrows/Return/Space обрабатывает собственный AppKit first responder в task workspace, без глобального event monitor. Выбор использует taskListID + taskID, исключает свёрнутые/отфильтрованные строки и восстанавливается после редактора; native controls/sheets сохраняют responder chain. Занятый journal имеет read-only retry, без предложения ручного снятия блокировки. Hour axis компенсирует горизонтальный origin в именованном viewport; offset не меняет layout frames. Apple SwiftUI GeometryProxy/offset docs проверены через официальный Context7.

Решение 2026-10-05, владелец: сохранить текущее состояние коммитом и пушем в согласованную основную ветку, затем закончить текущую цель и реализовать удобную установку. Субагенты разрешены для чётких задач, код/планирование остаются на текущей модели. Default remote branch main; master отсутствует, назначение пуша уточняется. future.md не найден даже среди скрытых локальных файлов; его путь уточняется. Установщик будет отдельным следующим этапом этого плана, а не заменой незавершённой UI-приёмки.

Решение 2026-10-05, агент: checkpoint сохраняет текущий незавершённый результат с честными gates. После review вновь открыть 7.2: два процесса могут заменить общий journal; исправление должно сериализовать доступ к файлу и проверять актуальную identity перед clear. Не возобновлять live writes до этой регрессии.


Решение 2026-10-05, владелец: принять Pixel Paper, добавить только task-list визуализацию Color Atlas и светлую тему как главный сценарий; отвергнутые варианты удалить. Не вводить rail/agenda/glass или дополнительную task pane в Calendar.

Решение 2026-10-05, владелец: возобновить весь scope и проводить tests через computer use, включая внешнюю проверку отступов после UI. Это разрешает снимки синтетического demo через доступный интерфейс; выбор в macOS permission prompt остаётся за человеком. Не захватывать personal normal-mode окно.

Решение 2026-10-05, агент: сначала сохранение, потом presentation и приёмка; новая palette не отменяет Google safety. Сохранить существующие незакоммиченные изменения, не удалять личные данные/старые Google test objects по названию.

Решение 2026-10-05, агент: при nonzero DELETE проверять только exact ID одним GET, без повторной записи. Исторический ledger не открывать неявно; UI acceptance требует явного --acceptance-ledger /absolute/path. Это ограничивает приёмку выбранным тестовым набором и исключает случайный доступ к прошлым запускам.

## Outcomes & Retrospective


Актуально 2026-10-07: локальная разработка и приёмка утверждённого интерфейса завершены, установщики реализованы и проверены на реальных bundles в отдельной временной папке. Пользователь получает full-row навигацию, компактные задачи со сроками/списками, закреплённую ось и headers календаря, рабочие native shortcuts/search, сохранённый черновик без повторного INSERT и симметричные bounded формы. Финальная сборка run-54154 успешна; 440 model assertions, 20 native UI assertions и 26 installer scenarios прошли.

Прежние доступы/Settings helper crash/build отказ больше не являются блокировками. Current screenshots и AX были обязательны: они выявили исчезновение оси, footer/height defects и конфликт Cmd+N, которые не обнаруживали чистые fixtures. Определение performance metric столь же важно: idle wait после scroll нельзя назвать UI stall, поэтому handler timing вынесен в schema 2. Actual p95 baseline и ограниченные resource snapshots записаны отдельно от модельных и сетевых цифр.

Подписанная публичная дистрибуция, license, public installer pin и clean-Mac acceptance требуют отдельного release этапа. Голосовой VoiceOver и видимый notification banner не подтверждены человеком. Эти условия сохранены, не заменены фиктивными отметками. Source checkpoint 62f153f исторический, текущее продолжение не выполняло commit/push/publication.

## Context and Orientation


Рабочий корень `/Users/alexbeketov/g-calendar`. `openspec/changes/g-calendar-mvp/tasks.md` содержит formal checklist. `AppMain.swift` управляет ObservableObject состоянием, refresh/mutations; `AppViews.swift` — sidebar/status/search; `SettingsAndForms.swift` — task/list/event/settings forms; `TaskWorkspaceView.swift` — task rows; `CalendarWorkspaceView.swift`/`CalendarTimeGrid.swift`/`CalendarLayout.swift` — календарь и чистые правила размещения. `GWSClient.swift` строит allowlisted argument vectors и запускает subprocess; `MutationService.swift` точно читает изменённый ресурс. `RuntimeModes.swift` изолирует demo, `Cache.swift` хранит atomic app-local state, `Reminders.swift` — локальные notifications. `Tests/InvariantTests.swift` использует fake runners/schedulers.

Exact read-back — отдельный GET конкретного calendarID/eventID или taskListID/taskID после записи, с проверкой identity и semantic fields. Unresolved write — запрос мог быть принят, но результат ещё не подтверждён; нельзя повторять create. Pending verification journal — local state ожидания проверки, который сам не отправляет writes. Sidebar selection не равна calendar visibility checkbox. Task tags означают список и существующие локальные свойства, а не новый Google priority/tag API.

Demo использует отдельную storage и fixtures, никогда не запускает gws/не читает personal cache. Live acceptance разрешена только для собственных synthetic objects этого запуска с приватным exact-ID ledger; edit/complete/delete имеют GET до и после. Нельзя удалять старые тестовые списки по имени. Подтверждение notification permission остаётся человеку. License selection, Developer ID signing/notarization и выпуск GitHub Release требуют отдельных исходных данных. Текущий checkpoint разрешено закоммитить и отправить в согласованную основную ветку.

## Plan of Work


### Этап 1 — единый контракт и очистка


Скопировать Pixel Paper overview в `design/reference-overview.png`, выбранный пользователем crop Color Atlas в `design/task-list-reference.png`; создать `design/DESIGN.md` и короткий index. После сохранения удалить только известный `design/variants` и старые superseded quality plans. Обновить их ссылки в docs/OpenSpec. Фиксировать blue #0B57D0, canvas #F7F9FC, white surface, ink #202124, secondary #505866; SF system, classic sidebar, 24 pt editor inset/16 section gap/8 field gap. Добавить OpenSpec selected-identity/metadata/modal-spacing acceptance и current computer-use authorization. Strict OpenSpec validate должен вернуть valid=true без issues.

### Этап 2 — надёжность записи


Добавить failing fixture в `InvariantTests.swift`: task insert с notes="" и exact GET без notes должен быть принят, а nonempty mismatch — нет. Запустить тест до fix и записать safe failure. В `MutationService.swift` определить семантическое равенство отсутствующей/пустой строки для пустых notes; date-only due остаётся date-only. Добавить recheck-only path и результат unresolved attempt с operation/known identity/expected fields. Persist попытку до отправки в app-local journal; при process/network failure после возможной отправки не возвращать UI в blindly retryable create. На старте journal загружается без автоматической записи. Дубликат той же попытки блокируется глобально; известный ID читается повторно точно. Неизвестный ID показывается как требующий reconciliation, без title-only proof или auto resend. Тестировать всех типов объектов, GET failure, wrong identity, missing ID, double Save, reopen и persisted recovery. Forms предлагают «Проверить сохранение», сохраняют draft и footer; обычная pre-write validation допускает corrected Save. Patch/delete retries также не отправляются автоматически.

### Этап 3 — общая оболочка и выбранная UI система


В `AppTheme.swift` добавить semantic primary-container, divider, row-selected/focus roles и spacing/radius constants с парными Light/Dark values. В `AppViews.swift` обеспечить actual full-row target для sections/list/filter и separate calendar checkbox. Проверить blank/interior edge/label activation в native List, убрать ambiguity selection/completion symbols. Sidebar footer не повторяет техническую справку. В calendar/task headers убрать letter-wrap labels и дублирование sidebar фильтров, сохраняя фильтры при hidden sidebar. Toolbar отвечает текущему разделу; периодные controls не загружают Calendar в Tasks без необходимости. Selected/read-only/loading states явно доступны. Header может перенести целые группы на новую строку, не сжимая буквы.

### Этап 4 — задачи, календарь, формы


В `CalendarLayout.swift` добавить stable due ordering локального view без remote mutations, компактную обработку empty groups и чистое вычисление общей content-aware date-only height. В `TaskWorkspaceView.swift` убрать card-per-row, добавить title/completion/menu, due status и list badge в выровненных колонках, существующие favorite/reminder badges, selected-row fill/leading marker и collapse counts. Narrow version переносит metadata как группу. Completed отдельны; no-due сохраняет исходный порядок. Columns остаётся явным альтернативным mode.

В `CalendarTimeGrid.swift`/`CalendarWorkspaceView.swift` передать общую height всем date-only columns, zero/compact height если данных нет, bounded overflow если много; убрать повторный empty-text. Обеспечить initial 08:00 без перезаписи manual scroll несвязанными updates, доступные семь дней, не обрезанные axis labels и alignment. Добавить fixture coverage геометрии и local date boundaries.

В `SettingsAndForms.swift` заменить растягивающий Form на content-sized field layout, использовать единый inset/spacing/footer и scroll только при ограничении высоты. Создание выбирает supported context; edit не меняет remote identity. Провести read-only/recurring view mode и local reminder controls. Проверить пустые/длинные поля, длинную ошибку, Enter/Escape/Tab, cancellation without write. Вылечить одинаковый класс spacing-defects в settings/list/reminder surfaces, а не только New task.

### Этап 5 — тесты, внешняя приёмка, профиль


Выполнить `scripts/test.sh`, затем собрать актуальную app для computer-use приёмки. Использовать именно isolated demo process/window; если app resolver выбирает открытое normal window, не взаимодействовать с ним. Запустить synthetic demo и пройти мышью blank-row clicks, keyboard shortcuts, search/clear/no match, views/filters, all modal create/edit/cancel, confirmations, Light/Dark/System, resize и width collapse. Screenshot evidence synthetic-only. Отдельно проверить код padding/frame modifiers во всех modal surfaces и внешнюю симметрию/выравнивание/footer reachability. Записать pass/fail для каждого surface; корректировать UI и повторять.

Добавить release profile с -O и измерить fixed tasks/events dataset, warm/cold сценарии, p50/p95 local projections и GUI visible latency, resize/scroll/hitches, CPU/memory. Разделять gws startup, API pagination и exact verification latency. Если Instruments недоступен, использовать доступные измерения и явно оставить unmeasured frame/trace metrics; не выдавать микроbenchmark за GUI. Согласованные бюджеты основываются на фактической машине/наборе; оптимизировать только повторяемые hotspots.

### Этап 6 — live acceptance и финальный отчёт


Через разрешённый actual-app adapter workflow выполнить narrow synthetic lifecycle с private ledger и exact GET before/after; never repeat unresolved create. Cleanup only current-run known IDs. UI tests не требуют personal mutations. Проверить available notification state; permission prompt человек выбирает сам. Refresh `docs/verification.md`, status, README/roadmap/OpenSpec из текущих результатов. Удалить stale contradictory summary information, сохранить реальные ограничения. Review source/scripts/tracked and untracked paths для личного содержимого/credentials/generated caches; не публиковать GitHub Release; текущий checkpoint разрешено закоммитить и отправить в согласованную основную ветку. Отправка completion notifications возможна только после фактического завершения и только по доступному авторизованному каналу.

### Этап 7 — реализованные установщики и отдельный публичный выпуск


Этот этап выполняется после закрытия текущих source/build/UI/spacing/performance acceptance задач, а не вместо них. Пользователь сможет установить g-calendar из исходников одной командой, перенести приложение из удобного DMG в «Программы» и установить конкретную версию из GitHub Releases без ручного распаковывания. Сейчас bundle строится только для arm64/macOS 13+ и имеет локальную ad-hoc подпись. Intel не обещать и не добавлять в installer manifest до отдельной сборки и приёмки. future.md не найден в tracked/untracked/hidden repository files; пункт перенесён по явному сообщению владельца, путь оригинала уточняется.

Создать `scripts/install-common.sh` для общей безопасной замены bundle, `scripts/install-source.sh` для сборки текущего checkout и установки в `~/Applications`, `scripts/uninstall.sh` для удаления только установленного bundle без app data. Перед заменой проверять macOS/architecture, ожидаемый bundle ID `com.alexbeketov.gcalendar`, существующую подпись и write permissions destination. Временный кандидат копируется рядом с destination, проверяется до замены; стабильный lock предотвращает параллельные upgrades. Запущенное приложение не закрывать принудительно: сообщить пользователю, что нужно закрыть его и повторить. Сохранить предыдущий bundle для явного rollback; при ошибке восстановить прежний. Не удалять cache, UserDefaults, pending verification journal, local reminders, gws или OAuth credentials. Не запускать Google operations и не менять Gatekeeper/quarantine.

Создать `scripts/package-dmg.sh` и `resources/installer/` для светлого Pixel Paper DMG: `.app`, shortcut `/Applications`, короткая инструкция о переносе и первом запуске. Использовать системный `hdiutil`, не вводить PKG/root services, поскольку приложение не требует системных служб. Артефакты помещать в ignored `dist/`: versioned arm64 DMG, ZIP, `SHA256SUMS` и `release-manifest.json` с version/architecture/minOS/bundle identity. До Developer ID явно маркировать локальный ad-hoc package; не утверждать Gatekeeper acceptance.

Создать `scripts/sign-release.sh`, `scripts/notarize-release.sh`, `scripts/verify-release.sh` и `docs/RELEASING.md`. Developer ID certificate/private key, Team ID и notarization Keychain profile передаёт владелец; не создавать и не сохранять их в repo. Подписать bundle с hardened runtime и timestamp, отправить ZIP в Apple notarization, прикрепить ticket к `.app` через stapler и заново создать ZIP. Затем создать, notarize и staple DMG. ZIP не допускает прямой staple. Проверить подпись, ticket и Gatekeeper assessment, вычислить checksums только после окончательных изменений. Источники решений: Apple Notarizing macOS software и Customizing notarization workflow; официальные GitHub immutable releases и verify-release-integrity; Homebrew Cask Cookbook. Проверенные ссылки доступны ниже, но все обязательные шаги описаны здесь.

Создать `scripts/install-release.sh`: `--version` фиксирует release tag, destination по умолчанию `~/Applications`, `--rollback` явно возвращает сохранённый bundle. Скачивать точный versioned arm64 asset по HTTPS с bounded retries/timeouts; checksum mismatch, bundle/architecture/minOS/Developer ID Team ID mismatch прекращают установку до замены. Checksum из соседнего asset защищает от порчи, а ожидаемая Developer ID подпись подтверждает издателя. Инструкция одной командой скачивает installer по commit SHA в временный файл, сверяет заранее указанный digest и только затем исполняет. Не публиковать инструкцию с фиктивным SHA/version/Team ID. `latest` сначала разрешается в конкретный tag; updater не запускается в фоне. Для выпуска загрузить все assets в draft GitHub Release и проверять их целостность, по возможности immutable release/gh verify-asset. Публикация Release и выбор лицензии требуют отдельного решения; source push не равен release approval.

В `docs/INSTALLATION.md` описать source и DMG workflows, отдельный gws setup и точные ограничения текущего package. Установщик не встраивает gws и не запускает OAuth. Первый запуск ведёт через существующие настройки gws; использование Calendar/Tasks scopes описывается отдельно. Homebrew cask в собственном tap добавить как дополнительный канал после проверенного релиза, с fixed version/sha256/URL и arm64/macOS constraints; не включать автоматический zap app data.

Написать `scripts/test-installers.sh` с disposable fake bundles и destination вне пользовательских Applications. Проверить установку, повтор/upgrade/rollback, interrupted copy, concurrent lock, running app rejection, foreign bundle rejection, Intel/old macOS, malformed archive/path traversal/symlink escape, digest/signature mismatch, destination с пробелами и отсутствие write permission. До/после сравнить synthetic cache/journal/reminders/settings побайтно. Скрипты не должны вызывать gws/OAuth. Проверить DMG через `hdiutil verify` и readonly mount содержимого с Applications shortcut; размонтировать только собственный mount. На подписанном скачанном релизе нужны `codesign --verify --strict`, `stapler validate`, Gatekeeper assessment и первый запуск на чистом Mac. Computer Use проверяет DMG install/start/setup и upgrade без потери настроек. Credential gate оставляет release acceptance открытой, но локальные scripts/tests должны быть реализованы и проверены.

Рабочий каталог команд `/Users/alexbeketov/g-calendar`:

    rtk proxy bash -n scripts/install-common.sh scripts/install-source.sh scripts/install-release.sh scripts/package-dmg.sh scripts/uninstall.sh
    rtk proxy ./scripts/test-installers.sh
    rtk proxy ./scripts/install-source.sh --destination /private/tmp/g-calendar-install-acceptance/Applications
    rtk proxy ./scripts/package-dmg.sh --app dist/g-calendar.app --output dist

Install-source запускает полную app build; выполнить её только после явного разрешения владельца на script build. Ожидаются exit 0 и точный installed bundle path, checksum verification, fixture pass count и verified DMG. Не считать скачанный подписанный релиз принятым по локальному ad-hoc package.


## Concrete Steps


Рабочий каталог для команд — `/Users/alexbeketov/g-calendar`.

    rtk node /Users/alexbeketov/.hermes/node/lib/node_modules/@fission-ai/openspec/bin/openspec.js validate g-calendar-mvp --type change --strict --no-interactive --json
    rtk ./scripts/test.sh
    rtk ./scripts/build-app.sh
    ./dist/g-calendar.app/Contents/MacOS/g-calendar --demo

Ожидается OpenSpec valid=true/issues=[], test exit0 с перечисленными passed groups/assertion count и build exit0 с APP_BUNDLE. Сборка не называется SwiftPM success; используются поддерживаемые scripts и существующий compiler. В текущей sandbox iconutil может потребовать auto-reviewed escalation: это отдельный environment issue, не повод менять system files. При повторении одинаковой ошибки дважды изучить первичные источники, записать 3–5 вариантов и выбрать эффективный, как требует AGENTS.md.

## Validation and Acceptance


Клик по icon/label/blank center/interior edge каждого sidebar row меняет ровно один selected context. Calendar visibility изменяет только visibility. Form Save при unresolved outcome не создаёт второй объект; exact recheck подтверждает правильные поля или оставляет честную ошибку. Fixture nil/empty equivalence не принимает nonempty mismatch. Journal сохраняется после restart без automatic writes.

Tasks List по умолчанию имеет compact grouped rows, metadata aligned, readable due/list badges, visible focus, separate menu/completion targets и stable due order. Empty groups не занимают большие gaps. Calendar Week сохраняет режим в narrow window, shared axis/header heights и reachable overflow; initial anchor и subsequent manual intent отличаются. Sheets имеют одинаковый outer inset, разумные field gaps, header/footer alignment и не показывают огромные пустые области. Это подтверждается code audit и computer-use screenshots, не только compile.

Light/Dark/System, loading/empty/no-match/offline/stale/setup/failure, writable/read-only/recurring, no-due/due/completed и длинные synthetic names проверяются отдельно. Полный human VoiceOver pass не заменяется AX labels inspection; доступное evidence и ограничения записываются точно. Performance reports фиксируют machine/build/dataset/method; численные budgets без данных не объявляются достигнутыми.

## Idempotence and Recovery


Delete scope ограничен отвергнутыми артефактами, созданными в design exploration, после сохранения двух утверждённых изображений. Existing working changes не сбрасываются. Tests/demo используют synthetic isolated storage. Journal содержит нужные local draft/identity, хранится приватно, не попадает в logs/repo. Нельзя retry INSERT при unresolved attempt, удалять ресурсы по названию или делать broad cleanup. При unavailable computer-use/OS permission сохранить прогресс, не обходить TCC и не утверждать visual pass.

## Artifacts and Notes

Последний checkpoint перед коммитом: optimized tests exit 0, ASSERTIONS=268. Предыдущий прогон имел один timeout в GUI-path launcher fixture; повтор без правок прошёл. Native task-list targets и task/reminder spacing подтверждены для предыдущего bundle. Calendar 08:00 clipping, Settings helper crash, актуальная сборка и 18 открытых задач OpenSpec остаются в работе. Исторические blocked записи ниже описывают прошлые наблюдения и не задают актуальный статус; цель возобновлена.


Финальные артефакты: `design/DESIGN.md`, два approved reference PNG, этот ExecPlan, OpenSpec checklist и sanitized verification report. До начала реализации 29/51 OpenSpec tasks закрыто; новые identity/spacing задачи добавляются отдельно. Все последующие timestamps/results заполняются по выполненным командам и GUI observations.

## Interfaces and Dependencies


Использовать текущие `GWSProcessRunning`, `GWSReadClient`, `GWSMutationService`, `WorkspaceViewModel`, `SnapshotStoring`, demo adapter и scheduler protocols. Добавить durable pending-verification record/store и чистые helper functions для local task order/date-only height. UI передаёт пользовательский intent, не произвольную CLI-команду. Точные поля и known identity в recovery не превращаются в публичные логи. SwiftUI/AppKit/ Foundation/UserNotifications остаются единственными runtime framework dependencies.

Редакция 2026-10-05: объединены предыдущие планы, выбранный дизайн и новый scope тестирования; реализация возобновлена пользователем. План будет обновляться после каждого этапа.

Checkpoint: regression fixture notes="" + omitted notes failed before fix (exit1, mutationNotVerified). Implemented nil/empty semantic equivalence and exact read-only recovery with durable private journal; current tests and UI integration pending acceptance.

Checkpoint 2026-10-05: fixture suite passed 221 assertions after nil/empty notes, durable journal, chronological dated projections and shared content-aware height. Optimized direct-swiftc build passed (exit0). CLI launch requires environment escalation to connect to WindowServer. Initial demo AX/screenshot and Cmd2 worked. Screenshot revealed initial scroll remained at 00:00; replaced offset-only axis anchors with actual VStack hour frames, acceptance pending rebuild.

Toolchain decision: State macro errors repeated twice with CLT SDK. Considered full Xcode selection, matching older compiler/SDK, loading an available official plugin, and existing StateObject/ObservableObject view-local storage. Selected StateObject because it compiles with installed toolchain and preserves supported native semantics without system changes. Sources: Apple StateObject documentation (Context7); Apple TN3211; missing-plugin primary report https://github.com/drumih/turbo-fieldfare/issues/185. An explicit generic State wrapper did not resolve macro selection. Build then found UUID-vs-String callback state type, corrected to UUID.

Computer-use recovery: native click failed noWindowsAvailable then native pipe closed; two fresh observations also failed. Research found primary reports https://github.com/openai/codex/issues/32293 and /26887 and official https://learn.chatgpt.com/docs/computer-use. Considered fresh AX binding, documented REPL reset/reinitialization, alternate running-app targeting, proper LaunchServices demo relaunch, and human Codex/plugin restart if helper still crashes. First three did not restore stable actions. Restarting only the agent-owned demo through LaunchServices is the next safe step. No TCC changes, helper binaries or raw input bypass.

Редакция 2026-10-05: Progress и Outcomes обновлены по 254 assertions, двум завершённым 11-step lifecycle, фактической доставке notification и текущим внешним gates. Включены новые read-back находки, explicit-ledger scope и отказ automatic approval review сборки; GUI проверки не закрыты по коду.
Редакция 2026-10-05: code audit исправил remote-deleted list context и отсутствие явного overdue icon/AX статуса, latest optimized suite passed 266 assertions. UI specification уточнена по утверждённой одной группе фильтров в workspace; obsolete sidebar filter helper удалён. Нужна новая app build и внешняя приёмка этих правок.\n
Редакция 2026-10-05, blocked audit: после трёх последовательных goal turns с тем же external blocker getApp снова подтверждает native-helper failure. Фиксируются 266 passed optimized assertions, 37/54 закрытых OpenSpec задач и 17 оставшихся build/UI acceptance пунктов. Safe independent work исчерпана в текущем этапе; запрещённый full build не повторялся, UI automation обхода нет. Цель blocked до точного разрешения на сборку и восстановления native Computer Use; это не изменение scope или утверждение о завершении.

Повторная проверка 2026-10-05 после сообщения владельца «дал доступ»: REPL reset + getState прошли; getApp(System Settings), click «Конфиденциальность и безопасность» и click «Запись экрана и системного звука» прошли с подтверждённой AX сменой страницы. Codex Computer Use.app screen recording toggle=on. Native clicks работают для macOS Settings. getApp(dist/g-calendar.app) всё ещё падает; bundle-ID lookup сообщает множество зарегистрированных старых копий. Name lookup запустил старую обычную сборку, с ней Google mutations/снимки не выполнялись. Cmd-Q этой копии отклонил automatic approval review из-за риска несохранённого состояния и недоказанного ownership; запрос закрытия отправлен владельцу, обхода отказа нет. Нельзя считать общую блокировку native clicks актуальной, но current demo binding/внешняя приёмка ещё не подтверждены. Разрешение на current-source build остаётся отдельным pending запросом.

Обновление 2026-10-07: Progress/Outcomes приведены к фактическим current-build/CU/installer/performance доказательствам; исторические блокировки больше не отражают текущий статус. Отдельные public-release и человеческие проверки сохранены явно.

Финальный контроль: strict OpenSpec valid=true/issues=[], git diff --check clean, package checksums OK; 92 текстовых файла без срабатывания credential patterns, Sources не новее run-54154 executable.
