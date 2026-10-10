# Доработки рабочего пространства Implementation Plan

**Goal:** Последовательно выполнить восемь пользовательских доработок macOS приложения.

**Architecture:** SwiftUI представления используют WorkspaceViewModel; Google операции создаёт GWSCommandFactory, подтверждает GWSMutationService, неопределённые результаты сохраняет MutationJournal. Локальные настройки и напоминания не отправляются в Google.

**Tech Stack:** Swift 5, SwiftUI, AppKit, UserNotifications, ServiceManagement, Google Workspace CLI, macOS 13+.

Этот ExecPlan ведётся по /Users/alexbeketov/.codex/Plans.md. Обновлять Progress, Surprises & Discoveries, Decision Log и Outcomes & Retrospective после каждого этапа.

## Purpose / Big Picture


Пользователь сможет менять сочетания клавиш, управлять боковой панелью через ⌘B, задавать время локального напоминания при создании задачи, включать запуск при входе, видеть все доски и переносить задачи между ними. Кликабельные области показывают указатель руки. UI проверяет Леха вручную; computer use не использовать.

## Progress


- [x] 2026-10-10: Изучены исходники, существующая OpenSpec и официальная документация Google/Apple.
- [x] 2026-10-10: Зафиксированы архитектура, спецификации и последовательный план.
- [x] 1: Настраиваемые hotkeys и ⌘B.
- [x] 2: Напоминание в редакторе, актуальная иконка, постоянный стиль уведомлений.
- [x] 3: Запуск при входе.
- [x] 4: Сортировка календарей и доступный для записи контекст по умолчанию.
- [x] 5: Стрелки вниз/вверх для списка задач над календарём.
- [ ] 6: Pointer на всей области действия и правило в AGENTS.md.
- [ ] 7: Все доски по умолчанию, колонки по доскам и исправление геометрии.
- [ ] 8: Перенос задачи в другую доску с проверкой результата.

## Surprises & Discoveries


Google Task.due отбрасывает время. Источник: developers.google.com/workspace/tasks/reference/rest/v1/tasks. tasks.move теперь принимает destinationTasklist. Источник: developers.google.com/workspace/tasks/reference/rest/v1/tasks/move. macOS управляет стилем уведомлений; NSUserNotificationAlertStyle=alert задаёт исходное предпочтение, пользовательский выбор остаётся приоритетным. Значок уведомления берётся из установленного bundle, а не из UNNotificationContent.

## Decision Log


Решение: сохранить дату Google отдельно от времени локального напоминания. Причина: API не поддерживает время срока. Автор/дата: Codex, 2026-10-10.

Решение: использовать существующий OpenSpec change g-calendar-mvp и добавить новые проверяемые сценарии. Причина: repository instructions задают этот change.

Решение: работать последовательно, отдельный коммит и push main после каждого проверенного пункта. Причина: последнее явное поручение пользователя заменяет старый запрет push и самостоятельные коммиты владельца. Полные сборки запускает Леха; агент выполняет invariant suite и focused typecheck.

Решение: реализовать нативный перенос, не копировать и удалять. Сначала подтвердить сохранение полей, затем перенос и точное чтение целевой и исходной доски; ошибка сохраняет форму и journal, повторная проверка не делает повторной записи.

## Outcomes & Retrospective


Анализ и план завершены. Реализация и ручная UI приёмка ещё не выполнены.

## Context and Orientation


Sources/GCalendar/AppMain.swift содержит модель и команды приложения. AppViews.swift содержит корень и sidebar. SettingsAndForms.swift содержит настройки и редактор задачи. TaskWorkspaceView.swift рисует список/колонки. CalendarLayout.swift содержит чистые правила фильтрации и раскладки. CalendarTimeGrid.swift рисует сворачиваемый список задач. GWSClient.swift создаёт безопасные команды CLI; MutationService.swift проверяет результат точным чтением, MutationRecovery.swift сохраняет неизвестные результаты. Reminders.swift планирует локальные системные уведомления. Tests/InvariantTests.swift проверяет синтетические данные без Google и UI.

## Plan of Work


Этап 1: добавить модель сочетаний, сохранение в UserDefaults, проверку конфликтов и сброс. Настройки редактируют все команды рабочего пространства; ⌘B меняет NavigationSplitViewVisibility через запрос модели. Фиксированные ⌘Q, Return/Escape и навигацию стрелками не переназначать. Проверить сохранение, конфликты и defaults.

Этап 2: редактор задачи получает отдельный переключатель и DatePicker локального напоминания. После read-back успешной записи сохранить напоминание для полученного task ID; сбой напоминания не повторяет Google запись. Задать Info.plist alert style и уникальное актуальное имя icon resource. Показать системный стиль и путь к настройкам. Не изменять глобальные настройки macOS.

Этап 3: новый сервис LoginItemSettings на SMAppService.mainApp. Настройки читают реальный статус enabled/requiresApproval/notRegistered/notFound, показывают ошибку и ссылку на системные настройки; demo не регистрирует автозапуск.

Этап 4: чистая сортировка writable first, затем локализованное имя и ID; контекст по умолчанию выбирает writable. Существующий явный выбор сохраняется пока присутствует, видимость календарей независима. Проверить пустой список и только read-only.

Этап 5: заменить только иконку раскрытия календарных задач на down/up; сохранить действие, счётчик и accessibility.

Этап 6: общий AppKit cursor rect для SwiftUI и нативных интерактивных контролов. Область совпадает с hit region, disabled исключаются, текстовые поля сохраняют I-beam. Проверить cleanup курсора; добавить правило в AGENTS.md и docs/ui.md.

Этап 7: nil selectedTaskListID означает все доски и является default. Сохранить nil после refresh и удаления выбранной доски. В sidebar и selector добавить Все доски. Колонки показываются только в этом scope и группируются по TaskList с устойчивыми составными task identity; фильтры применяются ко всем доскам. Конкретная доска всегда список. Задать явную ширину колонок и один вертикальный scroll внутри каждой колонки без перекрытия. Проверить фильтры, scope, сортировку, keyboard identities и узкое окно.

Этап 8: редактор всегда показывает Picker доски. Новый taskMove invocation с source tasklist/task и destinationTasklist, пустым body, авторизацией userSave. Проверить точное чтение целевой и отсутствие в исходной доске, сохранить ID и локальные metadata. Добавить поддержку demo, refresh scope, journal recovery. Проверить успешный перенос, неподтверждённый результат и recheck без повторной записи.

## Concrete Steps


Рабочий каталог /Users/alexbeketov/g-calendar. Выполнять rtk proxy ./scripts/test.sh после изменений pure models/transport, ожидать exit 0 и число passed assertions. Для SwiftUI выполнить focused swiftc -typecheck с источниками проекта, target arm64-apple-macosx13.0, frameworks SwiftUI/AppKit/UserNotifications/ServiceManagement; не запускать полный build-app.sh. После проверки использовать rtk git diff --check, explicit git add, git diff --cached, git commit и git push origin HEAD:main. Перед первым push сверить origin/main через git fetch; при расхождении не перезаписывать историю.

## Validation and Acceptance


OpenSpec validate g-calendar-mvp --strict должен завершиться успешно. Все invariant tests работают с synthetic fixtures. Ручная проверка Лехи: hotkey changes/reset/conflicts; sidebar ⌘B; create/edit/reminder failure; alerts remain until dismiss and correct icon after install; launch at login and external status refresh; writable calendar default; down/up chevron; hand on blank button margins; all boards/filter/list/columns/narrow window; move with edited fields and reminders. Системные настройки и фактическую доставку агент не меняет и не объявляет проверенными.

## Idempotence and Recovery


Проверки не меняют реальные Google данные. Неопределённый результат записи оставляет journal и блокирует повторную запись до read-back. При частичном успехе patch/move форма обновляет подтверждённый task, чтобы повторное действие было направлено на правильную доску. Git push никогда не использует force; локальные cache, dist, .hermes и credentials не добавлять.

## Artifacts and Notes


Исходный HEAD f6474ed; рабочее дерево чистое. OpenSpec CLI установлен; schema spec-driven, artifacts proposal/specs/design/tasks доступны.

## Interfaces and Dependencies


Использовать UserDefaults для hotkeys, NavigationSplitViewVisibility для sidebar, ReminderCoordinator.saveReminder для времени, SMAppService.mainApp для автозапуска, CalendarInfo.isWritable для права записи, TaskWorkspaceLayout для scope/grouping, GWSCommandFactory.taskMove и GWSMutationService.verifyAccepted для переноса. Модель данных GoogleTask.due остаётся DateOnly.

Редакция 2026-10-10: план добавлен до реализации по явному требованию пользователя; подтверждения не требуются в рамках указанного scope.

Этап 1 завершён: 496 assertions, Swift typecheck exit 0; dynamic shortcuts и ⌘B реализованы. UI проверяет пользователь.

Этап 2 завершён: 512 assertions; typecheck, plist lint, shell syntax exit 0. Подтверждённая Google запись отделена от local retry; alert style и WorkspaceIcon заданы. Уже сохранённый banner пользователь меняет в macOS вручную.

Этап 3 завершён: 519 assertions и typecheck exit 0. Fake service подтверждает register/unregister, requiresApproval, внешние изменения, ошибки и demo isolation; настоящий автозапуск не изменялся.

Этап 4 завершён: 526 assertions, typecheck exit 0. Сортировка writable/name/ID, cache/refresh default и сохранение явного выбора проверены синтетически.

Этап 5 завершён: down/up disclosure, typecheck exit 0. Действие и accessibility сохранены; визуальную приёмку делает пользователь.
