# g-calendar

Нативное macOS-приложение для Google Calendar и Google Tasks: интерфейс Pixel Paper с компактными метаданными Color Atlas, локальный кэш и системные напоминания. Целевая платформа — macOS 13+ на Apple Silicon (arm64); Intel и universal bundle не поддерживаются. Локальная приёмка выполнена на macOS 27.0.1, не на всех целевых версиях macOS. Публичного подписанного/notarized релиза пока нет.

## Установка

Из корня уже скачанного репозитория, с установленными Git и Apple Command Line Tools (`xcode-select --install`, если tools отсутствуют):

```sh
./scripts/install-source.sh
open "$HOME/Applications/g-calendar.app"
```

По умолчанию приложение устанавливается в `~/Applications`. Обновление сохраняет предыдущий bundle для `--rollback`; удаление приложения сохраняет настройки, кэш, локальные напоминания и Google credentials. Локальный DMG имеет ad-hoc подпись. Source installer доступен в основной ветке; установка закреплённой версии из GitHub Release требует отдельной публикации подписанного релиза. Подробности — [docs/INSTALLATION.md](docs/INSTALLATION.md), выпуск — [docs/RELEASING.md](docs/RELEASING.md).

## Сборка и запуск

Для локальной сборки и fixture tests `gws` и Google-аккаунт не нужны. Для синхронизации нужен отдельно установленный и авторизованный `gws` с доступом к Calendar и Tasks. Установщик не выполняет OAuth и не устанавливает `gws` автоматически.

```sh
./scripts/build-app.sh
open dist/g-calendar.app
./scripts/test.sh
env G_CALENDAR_TEST_OPTIMIZE=1 ./scripts/test.sh
./scripts/test-native-ui.sh
./scripts/test-installers.sh
```

Скрипты используют прямой `swiftc`: собранный bundle расположен в `dist/g-calendar.app`, временные продукты — в `.build/`. `Package.swift` и Xcode project в репозитории отсутствуют, поэтому `swift build`/`swift test` не являются командами сборки этого проекта. Исторический SwiftPM preflight и его linker failure в CLT описаны в [docs/BUILD_PREFLIGHT.md](docs/BUILD_PREFLIGHT.md). Датированные результаты приёмки — [docs/verification.md](docs/verification.md).

После завершения работы над одной или несколькими доработками агент пересобирает приложение через `./scripts/build-app.sh`. Для ручной проверки открывайте обновлённый `dist/g-calendar.app`; если приложение уже запущено, завершите его и откройте заново.

### Первый запуск

1. Установите и настройте `gws` по [документации Google Workspace CLI](https://github.com/googleworkspace/cli), отдельно разрешив доступ к Calendar и Tasks. OAuth выполняется вне g-calendar под тем же пользователем macOS.
2. Откройте настройки g-calendar и при необходимости укажите абсолютный путь к доверенному executable `gws`. Автопоиск проверяет `~/.local/bin/gws`, `/opt/homebrew/bin/gws` и `/usr/local/bin/gws`; GUI не полагается на PATH интерактивной оболочки.
3. Нажмите «Синхронизировать». Первый sync — read-only. Изменения Google вызываются только явными действиями в UI; удаление требует подтверждения, результат записи проверяется точным read-back.

Без Google можно посмотреть синтетический интерфейс после сборки (предварительно завершите обычный экземпляр приложения):

```sh
open dist/g-calendar.app --args --demo
```

Demo не вызывает `gws`, не читает пользовательский кэш и не запрашивает разрешения уведомлений.

## Что есть

- Недельный/дневной календарь с закреплённой шкалой времени и раздел задач с фильтрами, поиском, сроками и тегами списков.
- Light/Dark/System, полные зоны клика sidebar, нативная клавиатурная навигация и соразмерные формы с общими отступами.
- Создание и изменение событий/задач и списков через явные UI-команды; destructive actions требуют подтверждения. Проверки мутаций выполняются на synthetic fixtures, не через запись в пользовательский аккаунт.
- Кэш последнего успешного снимка, pagination, обработка ошибок и статусы синхронизации.
- Локальные напоминания задач и отдельных timed non-recurring событий через UserNotifications. Разрешение macOS запрашивается только при явном действии пользователя; закрытие окна не завершает приложение.

## Данные и безопасность

- Google-запросы выполняет выбранный `gws` как subprocess с отдельными аргументами. Указывайте только доверенный executable: g-calendar не изолирует произвольную программу от прав вашего пользователя. Приложение не читает и не экспортирует OAuth credentials; их настройкой и хранением управляет `gws`.
- Кэш, локальные reminders и журнал неподтверждённых записей хранятся в `~/Library/Application Support/g-calendar/`, настройки — в UserDefaults. Кэш содержит данные Calendar/Tasks, журнал может содержать сохранённый draft. Это локальные JSON-файлы без прикладного шифрования; не публикуйте их, raw API responses или личные screenshots.
- Обновление, rollback и uninstall сохраняют эти данные и credentials. Не удаляйте журнал неподтверждённой записи для повторной отправки: он не является offline queue.
- Для отчётов об ошибках используйте demo/fixtures и обезличенные сообщения. Private security contact и политика поддержки пока не определены; открытые решения — [docs/PENDING_DECISIONS.md](docs/PENDING_DECISIONS.md).

## Ограничения

- Google Tasks `due` — дата без времени. Локальное время напоминания — отдельное расширение g-calendar, обратно в Tasks/Calendar оно не синхронизируется.
- Durable offline write queue нет: при ошибке данные из кэша остаются доступны, но это не обещание отложенной записи.
- Повторяющиеся события доступны только для чтения: выбор scope и их редактирование пока не реализованы. Участники/приглашения не поддерживаются; локальные reminders для all-day/recurring событий не предусмотрены.
- Показ уведомлений зависит от разрешений macOS, Focus, настроек и состояния Mac; доставка во сне или после явного Quit не гарантируется.
- Доставка тестового уведомления в Notification Center подтверждена; видимый баннер и полный голосовой проход VoiceOver требуют отдельного человеческого наблюдения. Synthetic Google lifecycle выполняется на собственных тестовых объектах; текущая приёмка и результаты — [docs/verification.md](docs/verification.md).
- GUI baseline измеряет реакцию до update AppKit, не FPS или показ pixels; метод и ограничения — [docs/GUI_PERFORMANCE.md](docs/GUI_PERFORMANCE.md).
- В репозитории пока нет `LICENSE`; open-source лицензия и условия публичного распространения не выбраны. Не считать локальную сборку опубликованным релизом.

## Разработка

Рабочие правила и проверки — [CONTRIBUTING.md](CONTRIBUTING.md). Продуктовая спецификация, архитектурные решения и roadmap находятся в [docs/](docs/) и repo-local [OpenSpec change](openspec/changes/g-calendar-mvp/). Текущие gates и результаты — [docs/STATUS.md](docs/STATUS.md).
