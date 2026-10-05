# Требования продукта и MVP

Источник исходных ограничений — `docs/ACCEPTANCE_CONTRACT.md`. Этот документ превращает их в продуктовый scope; факты API и текущей среды см. в `docs/research.md`.

## Обязательные возможности MVP

### 1. Установка и запуск
- Собираемый native macOS `.app` с bundle identifier, иконкой/именем приложения, корректным Info.plist и предсказуемым foreground/background lifecycle.
- Сборка и локальный запуск только из документов/скриптов репозитория. Отсутствующий полный Xcode и текущая проблема SwiftPM manifest linker должны быть отражены; успешный `swift build` нельзя утверждать без реального exit code 0.
- Закрытие окна не завершает процесс; Quit завершает его явно.

### 2. Calendar
- Week-first view с навигацией по датам; day/detail view. Month view — после стабилизации недели.
- Отдельные календарные selectors с цветом, именем и режимом read-only; событие содержит начало/конец, timezone/all-day и календарь.
- Календарный диапазон и часовой пояс передаются явно; all-day end-date считается эксклюзивной. Повторяющиеся экземпляры не получают scope редактирования, если пользователь не может выбрать/увидеть точную область действия.
- События можно создавать/редактировать/удалять в доступном для записи календаре из явного UI workflow. Удаление подтверждается. Не включать участников/приглашения в MVP.

### 3. Google Tasks
- Selector task list, список по умолчанию и явное переключение в колонки, Today, Upcoming, Overdue, Without due, search; completion toggle доступен из списка и календарного контекста.
- Today содержит due date = локальному сегодня; Upcoming — due date строго позже; Overdue — незавершённые задачи до сегодня; Without due — задачи без Google due. Одинаковые date-only predicates используются в фильтрах, группах и календарном контексте.
- Создание/редактирование/удаление задач и task lists, complete/uncomplete — если API/текущий `gws` поддерживают соответствующий endpoint; каждый workflow проверяется только fixtures.
- Срок Google Task отображается как дата без скрытого времени. Для локального reminder time хранить отдельное app-local значение, отдельно от Google payload, и обозначать его «Локальное напоминание».

### 4. Данные и синхронизация
- Текущий адаптер запускает абсолютный путь к `gws` (локальная настройка и безопасный поиск распространённых путей); не зависит от shell profile/интерактивного PATH.
- Запуск через `Foundation.Process` с executable URL и отдельным массивом аргументов; shell interpolation запрещён. Только allowlist команд; никаких auth/login/debug-token вызовов.
- Пагинация сохраняет каждый объект; любой неуспешный exit code, malformed JSON, auth/network/quota error отражается как ошибка, а не как пустой календарь.
- Кэш last-known-good локальный и заменяется атомарно только после полного успешного sync. Сетевая ошибка его не очищает. Pending offline writes не реализуются и не изображаются.
- В логах — только error code, operation category и safe metadata; никаких пользовательских event/task titles, email, raw request bodies или OAuth material.

### 5. Уведомления
- UserNotifications с отдельной кнопкой действия пользователя для запроса permission; до этого никакого prompt.
- Локальные напоминания задач планируются/обновляются/отменяются с дедупликацией; изменение или завершение задачи отменяет/пересоздаёт относящееся уведомление. Для одного конкретного timed non-recurring Calendar event доступно opt-in local-only напоминание с точным временем от пользователя; не зеркалировать Google `event.reminders`, не задавать all-day time и не обещать Apple/Google Calendar parity.
- Не создаются скрытые Google events-копии. Настройка и доставка ясно указывают local-only; настройка macOS/sleep может изменить фактическое время показа.
- Автоматический запуск при login не включён. На уведомления и планирование тесты используют контролируемый fixture/scheduler; визуальная доставка требует human verification.

### 6. UI и доступность
- Material-inspired SwiftUI/AppKit визуальная система по `docs/ui.md`; macOS navigation patterns сохраняются.
- Light/Dark/System, клавиатурная навигация, visible focus, VoiceOver labels, Dynamic Type и понятные состояния loading/empty/error/offline/stale.
- Офлайн показывает cache и время его последнего обновления, если он есть; не обещает отложенную синхронизацию.

## Не входит / ограничения API

- Google Tasks due-time sync невозможен на Tasks API; точное время существует только как локальное расширение.
- Google Calendar push требует публично доступного HTTPS callback; hosted receiver для MVP не добавляется.
- Прямой OAuth реализация, credentials generation/export, приглашения/письма, полная recurring-event scope UX, Google parity, hosted services, платные keys, sync во время сна и login helper не входят.
- Production/личные Google writes запрещены. Текущая запись в `docs/HUMAN_APPROVALS.md` дополнительно разрешает в одном acceptance run создать и затем редактировать, завершать, возобновлять, GET/read-back и удалить только synthetic event/task ресурсы с уникальным `[g-calendar TEST <run-id>]`, созданные этим run через actual application UI/adapter. Перед каждой мутацией проверить точный ID и marker GET-запросом, после неё проверить результат ещё одним exact GET; IDs остаются только в private ledger. Без attendees/invites/email, без изменения существующих объектов и broad cleanup. Другие live writes остаются запрещены.

## Гейты приёмки

1. Gate A: feasible native stack, исследование API/CLI/распространения, UI specification.
2. Gate B: vision/requirements/ADR/roadmap и локальный OpenSpec change `g-calendar-mvp`; prompter выдаёт полный prompt implementation с тестируемыми критериями.
3. Gate C: app запускается; настоящие Calendar/Tasks read-only metadata доступны через текущий `gws`; ошибки не стирают cache; notification permission wiring реализован.
4. Gate D: основные week/day/task workflows и локальные reminders реализованы; UI edits проверены fixture runner, live writes не выполнялись.
5. Gate E/F: actual builds/tests, read-only smoke, ревью кода, финальный `docs/verification.md`; statuses выставлены отдельно как passed/failed/not-run/needs-human-verification.

## Неустранимые human checks

- Первый показ и фактическая доставка macOS notification после пользовательского разрешения.
- Поддержка all-day/recurring Calendar event reminders не входит в текущую реализацию и не может быть выведена из task-reminder tests.
- Live lifecycle of only this run's synthetic test objects is authorized as described above; any operation on another object remains prohibited.
- Screen Recording/screenshot and full manual VoiceOver traversal are human gates; do not bypass TCC.
- Подписание, notarization, App Store публикация, login item/helper.
