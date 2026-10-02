# g-calendar

Нативное macOS-приложение для Google Calendar и Google Tasks: компактный Material-inspired интерфейс календаря и задач, локальный кэш и системные напоминания. Текущий результат — локальная MVP-сборка для проверки, не публичный релиз.

## Сборка и запуск

Требуется macOS 13+ и установленный `gws` с уже настроенным доступом к Google Workspace.

```sh
./scripts/build-app.sh
open dist/g-calendar.app
./scripts/test.sh
```

Скрипты используют прямой `swiftc`: собранный bundle расположен в `dist/g-calendar.app`. На проверенной среде SwiftPM/XCTest не запускаются из-за linker failure в доступном CLT; подробности — [docs/BUILD_PREFLIGHT.md](docs/BUILD_PREFLIGHT.md). Итоговые команды и реальные результаты — [docs/verification.md](docs/verification.md).

Если `gws` установлен не по стандартному пути, укажите его абсолютный путь в настройках приложения. Приложение запускает `gws` с отдельными аргументами; OAuth credentials не показывает и не экспортирует. Первый sync — read-only. Изменения Google вызываются только явными действиями в UI. Автоматические fixture tests не выполняют live writes; отдельный owner-authorized acceptance run ограничен synthetic objects и GET/read-back, production/personal objects не затрагиваются.

## Что есть

- Недельный/дневной календарь и раздел задач с фильтрами и поиском.
- Создание и изменение событий/задач и списков через явные UI-команды; destructive actions требуют подтверждения. Проверки мутаций выполняются на synthetic fixtures, не через запись в пользовательский аккаунт.
- Кэш последнего успешного снимка, pagination, обработка ошибок и статусы синхронизации.
- Локальные напоминания задач через UserNotifications. Разрешение macOS запрашивается только при явном действии пользователя; закрытие окна не завершает приложение.

## Ограничения

- Google Tasks `due` — дата без времени. Локальное время напоминания — отдельное расширение g-calendar, обратно в Tasks/Calendar оно не синхронизируется.
- Durable offline write queue нет: при ошибке данные из кэша остаются доступны, но это не обещание отложенной записи.
- Повторяющиеся события не редактируются без выбора scope.
- Реальная видимая доставка баннера и pixel/VoiceOver QA требуют human verification/разрешения. Synthetic Google write/read-back acceptance разрешён владельцем, но ещё не выполнен; см. [docs/verification.md](docs/verification.md) и [docs/PRODUCT_COMPLETION.md](docs/PRODUCT_COMPLETION.md).
- В репозитории пока нет `LICENSE`; open-source лицензия и условия публичного распространения не выбраны. Не считать локальную сборку опубликованным релизом.

## Разработка

Продуктовая спецификация, архитектурные решения и roadmap находятся в `docs/` и локальном OpenSpec change `openspec/changes/g-calendar-mvp/`. Текущие gates и результаты — [docs/STATUS.md](docs/STATUS.md).
