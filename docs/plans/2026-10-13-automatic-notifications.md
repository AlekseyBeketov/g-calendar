# Автоматические уведомления g-calendar

Этот ExecPlan поддерживается по /Users/alexbeketov/.codex/Plans.md. Используется Swift/Foundation/UserNotifications; зависимости не добавляются.

## Purpose / Big Picture


Приложение самостоятельно получает настройки Google и планирует фирменные уведомления о будущих событиях. Пользователь один раз разрешает системные уведомления; ручной выбор времени каждого локального напоминания убирается. Полноценная синхронизация времени Google Tasks остаётся частью цели: date-only due нельзя выдавать за точное время. Пользователь 13 октября потребовал реализовать остальные уведомления независимо от этого исследования.

## Progress


- [x] (2026-10-13) Проверены текущий код, Google Tasks/Calendar и Apple UserNotifications через Context7. Найдены отсутствующие reminders в моделях и только ручные scheduler paths.
- [x] (2026-10-13) Дополнены модели, unknown/disabled и чистый Google popup planner.
- [x] (2026-10-13) Реализованы полные страницы, четыре workers, actor/coalescing/stale guard, diff pending, archive и безопасные cancel/shutdown.
- [x] (2026-10-13) Подключены process-lifetime timer, startup/refresh/mutation/activation/wake/timezone, единая настройка; ручные формы и действия удалены.
- [x] (2026-10-13) Synthetic suite 967 assertions, strict OpenSpec и оптимизированный bundle прошли. Визуальный banner не проверялся.
- [ ] Review/stage собственных hunks, отдельный коммит и обновление локальных индексов.
- [ ] Исследовать и доказать независимые read/write Google task time; при отказе сохранить требование незавершённым.

## Surprises & Discoveries


CalendarInfo и CalendarEvent не содержат defaultReminders/reminders, хотя адаптеры читают полные ресурсы. Event updated не меняется от изменения напоминаний. Старый scheduler cancel удаляет также delivered history; новый путь отменяет только pending. В дереве есть сторонние незакоммиченные изменения TaskWorkspaceView и task-management specs; их нельзя включать в коммит этой работы.

## Decision Log


Решение: не задерживать автоматические event notifications до решения Google task time. Причина: прямое новое указание пользователя; расписание событий доступно официально. Дата/автор: 2026-10-13, Леха/Codex.

Решение: события наследуют Google popup offsets, без fallback при отключённых напоминаниях. Date-only задачи и all-day события не уведомляются. Неизвестные данные не считаются выключением или удалением. Причина: отказ от 09:00 и запрос соответствия Google. Дата/автор: 2026-10-13, Codex.

Решение: системное разрешение запрашивается кнопкой глобального включения; дальше расписание автоматическое. Уже авторизованное приложение работает сразу. При denied нет повторных системных запросов. Дата/автор: 2026-10-13, Codex.

## Outcomes & Retrospective


Автоматическое расписание событий реализовано и проверено 967 synthetic assertions; bundle обновлён. Google Tasks precise-time transport остаётся незавершённым. Browser calendar.google.com ранее отклонён сохранённой настройкой сайта; запрет не обходится. OAuth-проект сопоставлен по Client ID пользователя, private Tasks API не виден в каталоге, публичное due отбрасывает время. Это не является глобальным доказательством невозможности отдельного разрешённого транспорта.

## Context and Orientation


Sources/GCalendar/Models.swift задаёт CalendarInfo/CalendarEvent и date-only GoogleTask. GWSClient.swift декодирует полные страницы, GoogleRESTTransport.swift исполняет те же команды через OAuth. AppMain.swift содержит WorkspaceViewModel, AppViews.swift — lifecycle subscriptions. Reminders.swift содержит UserNotificationScheduler и legacy coordinators, Cache.swift — metadata. Новая Sources/GCalendar/AutomaticNotifications.swift отделит планирование от scheduler, чтения Google и UI. Tests/AutomaticNotificationTests.swift подключается к scripts/test.sh и InvariantTests.main.

## Plan of Work


Добавить optional reminders с совместимостью старого JSON cache. Nil означает неизвестные настройки, пустой массив — подтверждённое отсутствие. Ошибочная live форма не очищает старые уведомления.

Planner создаёт стабильные IDs по namespace аккаунта, calendar/event occurrence и offset. Popup minutes от 0 до 40320 дают start минус offset; email не превращается в banner. Горизонт уведомлений 30 дней требует чтения до горизонта плюс 28 дней, с запасом исключительной верхней границы. Recurring instances читаются singleEvents=true. Cancelled/declined/all-day не планируются; неизвестные reminders защищают pending от удаления.

Reader читает CalendarList целиком, затем каждый календарь со всеми страницами до четырёх workers. Успех подтверждает покрытие только этого календаря. Ошибка сохраняет его requests; отсутствие календаря в полном каталоге подтверждает удаление. Чтение не меняет видимый snapshot/выбранную неделю.

Actor coordinator объединяет overlapping requests и не применяет устаревшие чтения. Scheduler сравнивает содержимое/момент pending, заменяет изменённые и отменяет ненужные pending. Ошибка добавления запрещает destructive cleanup и показывается в настройках. Legacy metadata архивируется до отмены legacy pending; delivered history сохраняется. Manual scheduling больше не вызывается.

UI показывает глобальный статус/включение/обновление и источник Google reminders. Task/Event reminder toggles/date pickers/actions удаляются. Due остаётся date-only; точное время нельзя записывать в due, notes или скрытый event. Исследование должно предложить проверенный отдельный транспорт без копирования cookies.

## Concrete Steps


Из /Users/alexbeketov/g-calendar выполнять rtk proxy ./scripts/test.sh, rtk proxy openspec validate g-calendar-mvp --strict, rtk proxy git diff --check, после реализации rtk proxy ./scripts/build-app.sh. Коммитить только собственные файлы после staged review; в общих dirty файлах stage только собственные hunks. Не push.

## Validation and Acceptance


Synthetic tests: offsets/defaults/overrides/empty/email, recurring identities, all-day/date-only, unknown metadata, partial failure, replace/no-op/cancel, namespace, denied, stale read, scheduler failure и сохранение delivered history. Существующая suite остаётся зелёной. Bundle: /Users/alexbeketov/g-calendar/dist/g-calendar.app. Ручная проверка: разрешить уведомления, задать Google popup через несколько минут, синхронизировать и получить banner g-calendar без локальной настройки; сменить время/offset или удалить событие и проверить отмену. Сборка не доказывает banner. Task time реализовано только после собственного read/write и read-back той же identity.

## Idempotence and Recovery


Стабильные IDs исключают дубли. Отказ сети не очищает расписание. Разрешение не вызывается из тестов. Account-scoped архив создаётся без удаления исходных данных. Coordinator не пишет Google и не повторяет неопределённые mutations.

## Artifacts and Notes


Первичные источники: Tasks resource due, CalendarList.defaultReminders/Event.reminders, Apple pendingNotificationRequests/add/removePendingNotificationRequests. HAR остаются ignored .hermes/research/task-time.

## Interfaces and Dependencies


AutomaticNotificationRequest: Codable/Equatable со stable identifier, namespace, calendar/resource identity, title/body/fireDate. AutomaticNotificationReading возвращает полный каталог и per-calendar успех/ошибки. AutomaticNotificationScheduling предоставляет permission/pending/add/cancelPending без delivered deletion. AutomaticNotificationCoordinator — actor, единственный writer. Real scheduler использует UserNotificationScheduler center/foreground delegate; тесты — fake.

Revision note (2026-10-13): прежняя зависимость всей системы от task-time исследования снята по новому указанию владельца.

Revision note (2026-10-13): реализовано автоматическое event scheduling; ревью выявило и regression tests закрыли удаление во время add, shutdown/logout и очистку owned malformed payload при выключении. Проверены строгие scalar types reminders. Bundle собран, task-time read/write и видимый banner остаются неподтверждёнными.
