# Уведомления g-calendar: исследование официальных источников

Проверено: 2026-10-01 (Europe/Moscow). Использованы официальные документы Google и Apple; в репозитории прочитаны только нужные исходники и спецификации. Приложение не запускалось, разрешение на уведомления не запрашивалось, настройки macOS и Google-объекты не менялись.

## 1. Что уже делает проект

`Sources/GCalendar/Reminders.swift:5-10, 57-68, 83-105` описывает напоминание с `taskID`, сохраняет `LocalTaskMetadata.reminderAt` и пересобирает расписание только для `GoogleTask`; это локальное расширение задачи, а не Google Calendar event reminder. `Sources/GCalendar/Models.swift:119-146` не моделирует поле `reminders` у `CalendarEvent`. Следовательно, текущая реализация — только task-local.

Планировщик использует одноразовый `UNCalendarNotificationTrigger` с компонентами текущего `Calendar` — год, месяц, день, час и минута (`Reminders.swift:177-185`); разрешение запрашивается только на явном пути действия пользователя (`:48-55, 57-60`). Foreground delegate выбирает `.banner`, `.list`, `.sound` (`:141-147`). При отмене удаляются pending и delivered запросы по идентификатору (`:188-191`), но текущий код не читает списки pending/delivered. Поиск в `Sources/GCalendar` не обнаружил `didReceive`/notification action handler: клик или action сейчас не маршрутизируется к событию/задаче.

## 2. Google Calendar: reminder preference не равна локальной доставке

- Event resource содержит `reminders.useDefault` и `reminders.overrides`. `useDefault` определяет, применяются ли напоминания календаря по умолчанию; если событие использует собственные напоминания, `overrides` содержит их, а отсутствие списка означает, что для такого события напоминания не заданы. Список ограничен пятью override-записями.[1]
- Параметры override: `method` — только `email` или `popup`; `minutes` — целое число от 0 до 40320 включительно (до четырёх недель до начала события). Оба поля обязательны при добавлении override. Документация описывает `email` как отправку письма, а `popup` — как UI popup, не как уведомление стороннего macOS-приложения.[1]
- `CalendarList` предоставляет `defaultReminders` для календаря пользователя; Event resource описывает настройки напоминаний для аутентифицированного пользователя.[1][2]
- `events.list` возвращает `items[]` как Event resources, а `events.get` возвращает событие.[1][3][4]
- `reminders` помечены writable для создания/обновления через `events.insert` и `events.update`.[1][5][6]
- `events.update` заменяет весь ресурс; для частичного изменения есть `events.patch`.[6][7]
- Эти поля дают приложению данные для чтения/записи предпочтений Google Calendar, но не передают Google Calendar-уведомление в локальный `UNUserNotificationCenter`. Отдельный Google Calendar push-механизм сообщает об изменениях ресурсов через HTTPS webhook; это канал изменений, а не таймер напоминания о начале события.[1][10]
- Честное локальное отображение возможно только как отдельное, явно включённое приложением расписание. Можно интерпретировать выбранный `popup`-override или полученные `defaultReminders` и создать собственный local notification.[1][2]
- Такое расписание не подтверждает доставку Google и не воспроизводит Google Calendar: `email` не является локальным баннером, а macOS применяет собственные authorization, alert-style и Focus-настройки.[11][22][23]

### Даты, all-day и recurring

Для timed events используются `start.dateTime` / `end.dateTime`; API допускает RFC3339 offset и/или IANA `timeZone`, а ответы `get`/`list` интерпретируются в параметре `timeZone` либо timezone календаря. All-day events используют `start.date` / `end.date`; timezone для них значения не имеет.[8] Поэтому all-day событие само по себе не определяет час локального уведомления: продукту пришлось бы отдельно задать локальное время или не поддерживать такие уведомления.

Recurring event задаёт правило повторения, а его occurrences могут иметь отдельные исключения; timezone события обязательна для раскрытия повторений.[8][9]

Будущее локальное расписание должно быть определено на уровне конкретных экземпляров с учётом timezone и изменений/исключений, а не считаться одной датой master-события.[8][9]

## 3. Apple UserNotifications на macOS: pending, delivered и показ

- Приложение запрашивает типы authorization через `UNUserNotificationCenter.requestAuthorization`; Apple рекомендует делать это в контексте пользовательского действия. Authorization и разрешённые виды взаимодействия могут меняться; нужно перечитывать `notificationSettings`. Разрешение на уведомления не гарантирует alert: настройки могут оставить уведомление только в Notification Center.[11][12]
- `UNUserNotificationCenter.add` регистрирует `UNNotificationRequest` с контентом и trigger. `UNCalendarNotificationTrigger` сопоставляет календарные компоненты с конкретным временем; `UNTimeIntervalNotificationTrigger` отсчитывает интервал от текущего момента, а для повторения интервал должен быть не меньше 60 секунд.[13][14][15] Принятый в приложении `add` означает, что запрос поставлен системному планировщику, но не означает, что пользователь увидел баннер.
- `getPendingNotificationRequests` возвращает ожидающие срабатывания запросы; `getDeliveredNotifications` — уже доставленные уведомления, которые ещё присутствуют в Notification Center. Это разные состояния, и ни одно из них само по себе не доказывает показ баннера на экране.[12]
- Идентификатор запроса можно использовать для отмены; новый запрос с тем же идентификатором заменяет ранее ожидающий запрос. Это пригодно для дедупликации pending-запросов, но не следует трактовать как подтверждение доставки или замены уже delivered-записи.[16] Текущая реализация использует стабильный идентификатор задачи и отдельно удаляет pending и delivered при пересоздании (`Reminders.swift:25-29, 62-67, 188-191`).
- Если уведомление приходит при активном приложении, `UNUserNotificationCenterDelegate.willPresent` выбирает способ foreground-показа. Текущий delegate просит banner/list/sound; системные настройки всё равно влияют на фактический вид.[11][17] Для обработки нажатия/action Apple предусматривает delegate `didReceive`, категории и payload; их нужно реализовать для открытия правильной цели. В текущем `Sources/GCalendar` такой обработчик не найден.[18]
- Apple описывает системную обработку локальных уведомлений, когда приложение не запущено или находится в фоне, но это не доказывает отдельную гарантию после явного Quit. Focus может заглушать все уведомления или разрешать только выбранные приложения; настройки macOS позволяют отключить уведомления и выбирать, приостанавливать ли показ, когда дисплей спит. Документация не даёт оснований гарантировать видимый показ через Focus, отключённые alerts, сон компьютера либо явный Quit.[13][22][23]

## 4. Минимальная macOS и распространение

В `resources/Info.plist` задан `LSMinimumSystemVersion=13.0`, а `scripts/build-app.sh` компилирует для `arm64-apple-macosx13.0`; это текущий минимум проекта, а не универсальное требование Apple для UserNotifications. Apple определяет `LSMinimumSystemVersion` как минимальную macOS, необходимую приложению.[21] Скрипт не выполняет signing или notarization, а `docs/verification.md:35` характеризует текущий артефакт как локальную неподписанную/не нотарифицированную сборку, не релиз.

Локальная неподписанная `.app` не становится автоматически публично распространяемым продуктом: если macOS распознаёт её как приложение от неизвестного разработчика, может появиться предупреждение; Apple описывает это как приложение без подтверждённой регистрации/проверки и отдельно документирует ручное разрешение запуска. Здесь никакие настройки безопасности не менялись.[24]

Для прямого публичного распространения вне Mac App Store Apple требует подписать исполняемый код Developer ID; описанный notarization flow также требует Hardened Runtime и secure timestamp и предусматривает notarization перед распространением клиентам. Для распространения через Mac App Store применяется отдельный workflow, включая App Sandbox.[19][20] Эти release-шаги не нужны для факта локальной сборки и в рамках этой задачи не выполнялись.

## 5. Рекомендация и delta спецификации

**Оставить MVP в текущем узком scope: только локальные напоминания Google Tasks.** Не планировать и не обещать уведомления Google Calendar events и не называть поведение эквивалентом Apple Calendar: текущая модель/планировщик/UX не поддерживают event reminder fields, а Google API описывает предпочтения `email`/`popup`, не гарантированную локальную доставку.[1][11][13]

Для spec delta уточнить в `docs/requirements.md` §5 и OpenSpec `specs/local-reminders/spec.md`, что «local reminders» MVP относятся только к задачам; приложение не читает, не изменяет и не зеркалит `event.reminders`, не создаёт уведомления для событий и не обещает parity с Apple Calendar. Отдельно сохранить различие «настроено локально / pending / доставлено в Notification Center / видимый баннер» и отсутствие гарантии последнего.

Если добавлять event notifications позднее, до изменения scope нужен конкретный выбор владельца продукта: зеркалировать ли только Google `popup` (учитывая `useDefault`/overrides), либо дать независимое локальное время события; что делать с `email`, all-day временем и отдельными recurring occurrences; как предотвращать двойные уведомления с Google Calendar. Точное соответствие Apple Calendar из одних полей API и UserNotifications обосновать нельзя.[1][8][9]

## Sources

[1] https://developers.google.com/workspace/calendar/api/v3/reference/events — Events | Google Calendar API
[2] https://developers.google.com/workspace/calendar/api/v3/reference/calendarList — CalendarList | Google Calendar API
[3] https://developers.google.com/workspace/calendar/api/v3/reference/events/list — Events: list | Google Calendar API
[4] https://developers.google.com/workspace/calendar/api/v3/reference/events/get — Events: get | Google Calendar API
[5] https://developers.google.com/workspace/calendar/api/v3/reference/events/insert — Events: insert | Google Calendar API
[6] https://developers.google.com/workspace/calendar/api/v3/reference/events/update — Events: update | Google Calendar API
[7] https://developers.google.com/workspace/calendar/api/v3/reference/events/patch — Events: patch | Google Calendar API
[8] https://developers.google.com/workspace/calendar/api/concepts/events-calendars — Calendars and events | Google Calendar API
[9] https://developers.google.com/workspace/calendar/api/guides/recurringevents — Recurring events | Google Calendar API
[10] https://developers.google.com/workspace/calendar/api/guides/push — Get push notifications | Google Calendar API
[11] https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications — Asking permission to use notifications | Apple Developer Documentation
[12] https://developer.apple.com/documentation/usernotifications/unusernotificationcenter — UNUserNotificationCenter | Apple Developer Documentation
[13] https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app — Scheduling a notification locally from your app | Apple Developer Documentation
[14] https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger — UNCalendarNotificationTrigger | Apple Developer Documentation
[15] https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger/init%28timeinterval%3Arepeats%3A%29 — UNTimeIntervalNotificationTrigger initializer | Apple Developer Documentation
[16] https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier — UNNotificationRequest identifier | Apple Developer Documentation
[17] https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate — UNUserNotificationCenterDelegate | Apple Developer Documentation
[18] https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions — Handling notifications and notification-related actions | Apple Developer Documentation
[19] https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution — Notarizing macOS software before distribution | Apple Developer Documentation
[20] https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution — Preparing your app for distribution | Apple Developer Documentation
[21] https://developer.apple.com/documentation/bundleresources/information-property-list/lsminimumsystemversion — LSMinimumSystemVersion | Apple Developer Documentation
[22] https://support.apple.com/guide/mac-help/mchl613dc43f/mac — Set up a Focus on Mac | Apple Support
[23] https://support.apple.com/guide/mac-help/notifications-settings-mh40583/mac — Notifications settings on Mac | Apple Support
[24] https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac — Open a Mac app from an unknown developer | Apple Support
