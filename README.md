# g-calendar

Нативное macOS-приложение для Google Calendar и Google Tasks: интерфейс Pixel Paper с компактными метаданными Color Atlas, локальный кэш и системные напоминания. Поддерживается macOS 13+ на Apple Silicon (arm64). Текущий результат — локальная сборка; публичный релиз ещё не опубликован.

## Установка

Из уже скачанного репозитория, с установленными Git и Apple Command Line Tools:

```sh
./scripts/install-source.sh
open "$HOME/Applications/g-calendar.app"
```

По умолчанию приложение устанавливается в `~/Applications`. Обновление сохраняет предыдущий bundle для `--rollback`; удаление приложения сохраняет настройки, кэш, локальные напоминания и Google credentials. Локальный DMG имеет ad-hoc подпись. Установка из закреплённого публичного release станет доступна после его отдельной публикации. Подробности — [docs/INSTALLATION.md](docs/INSTALLATION.md), выпуск — [docs/RELEASING.md](docs/RELEASING.md).

## Сборка и запуск

Для Google-синхронизации нужен установленный `gws` с настроенным доступом к Google Workspace. Установщик не выполняет OAuth и не устанавливает `gws` автоматически.

```sh
./scripts/build-app.sh
open dist/g-calendar.app
./scripts/test.sh
./scripts/test-native-ui.sh
./scripts/test-installers.sh
```

Скрипты используют прямой `swiftc`: собранный bundle расположен в `dist/g-calendar.app`. На проверенной среде SwiftPM/XCTest не запускаются из-за linker failure в доступном CLT; подробности — [docs/BUILD_PREFLIGHT.md](docs/BUILD_PREFLIGHT.md). Итоговые команды и реальные результаты — [docs/verification.md](docs/verification.md).

Если `gws` установлен не по стандартному пути, укажите его абсолютный путь в настройках приложения. Приложение запускает `gws` с отдельными аргументами; OAuth credentials не показывает и не экспортирует. Первый sync — read-only. Изменения Google вызываются только явными действиями в UI. Автоматические fixture tests не выполняют live writes; отдельный owner-authorized acceptance run ограничен synthetic objects и GET/read-back, production/personal objects не затрагиваются.

## Что есть

- Недельный/дневной календарь с закреплённой шкалой времени и раздел задач с фильтрами, поиском, сроками и тегами списков.
- Light/Dark/System, полные зоны клика sidebar, нативная клавиатурная навигация и соразмерные формы с общими отступами.
- Создание и изменение событий/задач и списков через явные UI-команды; destructive actions требуют подтверждения. Проверки мутаций выполняются на synthetic fixtures, не через запись в пользовательский аккаунт.
- Кэш последнего успешного снимка, pagination, обработка ошибок и статусы синхронизации.
- Локальные напоминания задач через UserNotifications. Разрешение macOS запрашивается только при явном действии пользователя; закрытие окна не завершает приложение.

## Ограничения

- Google Tasks `due` — дата без времени. Локальное время напоминания — отдельное расширение g-calendar, обратно в Tasks/Calendar оно не синхронизируется.
- Durable offline write queue нет: при ошибке данные из кэша остаются доступны, но это не обещание отложенной записи.
- Повторяющиеся события не редактируются без выбора scope.
- Доставка тестового уведомления в Notification Center подтверждена; видимый баннер и полный голосовой проход VoiceOver требуют отдельного человеческого наблюдения. Synthetic Google lifecycle выполняется на собственных тестовых объектах; текущая приёмка и результаты — [docs/verification.md](docs/verification.md).
- GUI baseline измеряет реакцию до update AppKit, не FPS или показ pixels; метод и ограничения — [docs/GUI_PERFORMANCE.md](docs/GUI_PERFORMANCE.md).
- В репозитории пока нет `LICENSE`; open-source лицензия и условия публичного распространения не выбраны. Не считать локальную сборку опубликованным релизом.

## Разработка

Продуктовая спецификация, архитектурные решения и roadmap находятся в `docs/` и локальном OpenSpec change `openspec/changes/g-calendar-mvp/`. Текущие gates и результаты — [docs/STATUS.md](docs/STATUS.md).
