# Установка g-calendar

Целевая платформа — **macOS 13+ на Apple Silicon (arm64)**. Intel/universal-сборки нет. Текущая локальная приёмка выполнена на macOS 27.0.1; target 13.0 в bundle/Mach-O не означает тестирование на каждой версии macOS. Установка не требует `sudo`, системных служб или изменения Gatekeeper. Основной каталог — `~/Applications`.

## Из текущих исходников

Нужны Git и Apple Command Line Tools (при отсутствии установите через `xcode-select --install`). `gws` и Google-аккаунт для сборки не нужны. Все команды ниже выполняются из корня уже скачанного checkout, если явно не указано иное:

```bash
./scripts/install-source.sh
```

Скрипт собирает текущие исходники через `scripts/build-app.sh`, проверяет локальную ad-hoc подпись и устанавливает bundle. Полная сборка выполняется именно этим вызовом. Если актуальный bundle уже собран:

```bash
./scripts/install-source.sh --app "$PWD/dist/g-calendar.app"
```

Source installer и его helper доступны в публичной основной ветке `main` (проверено 2026-10-07). Находясь вне существующего каталога `g-calendar`, для установки из Git выполните:

```bash
git clone https://github.com/AlekseyBeketov/g-calendar.git && ./g-calendar/scripts/install-source.sh
```

Команда использует изменяемую основную ветку: запускайте её только если доверяете текущим исходникам. Для review перед выполнением разделите clone и запуск installer. Для воспроизводимой установки выберите и проверьте конкретный commit, выполните `git checkout <проверенный commit>` внутри clone, затем installer. Это source workflow, не закреплённый подписанный release; лицензия и условия публичного распространения остаются открытым решением владельца.

Запуск установленной программы:

```bash
open "$HOME/Applications/g-calendar.app"
```

Локальная ad-hoc подпись подтверждает целостность bundle, но не идентичность издателя и не notarization. Для распространения через скачанный DMG требуется отдельная Developer ID сборка.

## Каталог установки, обновление и возврат

Закройте g-calendar перед установкой, обновлением, удалением и возвратом. Установщик обнаруживает запущенный executable, прекращает операцию и не закрывает приложение принудительно. Не запускайте приложение во время замены файлов.

```bash
./scripts/install-source.sh --destination "/absolute/path/Applications"
./scripts/install-source.sh --rollback
```

Проверка arm64, минимальной macOS, `com.alexbeketov.gcalendar`, executable и подписи проходит до замены. Кандидат копируется во временный каталог рядом с установленным bundle и проверяется ещё раз. Другой bundle, symlink destination и занятый installer lock отклоняются.

Предыдущая версия сохраняется как `.g-calendar-previous.app` рядом с приложением. Каждое следующее успешное обновление заменяет этот единственный резерв. `--rollback` меняет текущую и предыдущую версии местами. Если установка прервана между переименованиями, следующий запуск требует `--rollback` и восстанавливает предыдущий bundle. При обычной ошибке или обработанном сигнале восстановление выполняется автоматически. При `SIGKILL`/отключении питания временный `.g-calendar-stage.*` может остаться: он не считается установленным приложением.

Постоянный приватный `.g-calendar-install.lock` остаётся на диске: это системный flock lock, а не признак занятого установщика. Современный `lockf` блокирует inherited descriptor; на macOS 13, чей `lockf` не поддерживает FD mode, используется встроенный Perl `flock` на том же descriptor. Lock освобождается при завершении процесса; файл не следует удалять во время работы installer. Различие подтверждено в [официальном Apple source 2022](https://github.com/apple-oss-distributions/shell_cmds/blob/shell_cmds-278/lockf/lockf.c).

Настройки, cache, local reminders, mutation journal, `gws` и Google credentials не удаляются и не перемещаются. Возврат старой версии сохраняет файлы данных, но совместимость будущих форматов данных потребует отдельной проверки при их изменении.

## DMG

Локальный package создаёт `scripts/package-dmg.sh --mode local`. Он явно помечен как ad-hoc и служит для локальной проверки. Откройте DMG и перенесите `g-calendar.app` в shortcut «Applications». Этот shortcut указывает на `/Applications`; установка туда зависит от прав текущего пользователя. В отличие от source installer, ручное перетаскивание Finder не сохраняет installer rollback-копию.

Перед заменой через Finder закройте приложение и убедитесь, что заменяете именно g-calendar. Не отключайте Gatekeeper и не удаляйте quarantine для обхода проверки. Скачанный signed package должен пройти подпись, notarization и Gatekeeper. Процедура выпуска описана в [RELEASING.md](RELEASING.md).

## Проверенный GitHub Release

**Реальный подписанный/notarized release и ожидаемый Developer ID Team ID пока не опубликованы.** Скрипт уже реализован; конкретная команда загрузки появится после выпуска и приёмки скачанной версии на чистом Mac.

`install-release.sh` принимает конкретный tag `--version vX.Y.Z`, доверенный SHA256 ZIP через `--sha256`, ожидаемый Team ID через `--team-id` и необязательный `--destination`. Значения берутся из проверенного сообщения о выпуске; совпадение checksum с asset рядом на сервере само по себе не подтверждает издателя. `latest` намеренно не используется: tag должен быть явным.

Скачивается только versioned `g-calendar-<version>-arm64.zip` из GitHub Releases этого репозитория, по HTTPS с ограниченными retries/timeouts и размером. До распаковки проверяются checksum, структура ZIP и запрет symlinks/special files/path traversal. Apple `ditto` распаковывает ZIP в пустой приватный каталог и восстанавливает AppleDouble metadata, включая extended attributes, вместо лишних `._*` файлов внутри подписанного bundle. После распаковки повторно проверяются root, отсутствие links и codesign. Затем проверяются version, bundle ID, architecture, minOS в Info.plist и Mach-O, Apple Developer ID chain, ожидаемый Team ID, hardened runtime, secure timestamp и Gatekeeper source `Notarized Developer ID`. Кандидат повторно проверяется после копирования рядом с destination. Ошибка оставляет установленную программу нетронутой.

Скачанный release installer не требует Command Line Tools: Mach-O проверяется системным `od` с bounded load-command parser по [официальному Apple loader.h](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h), без `lipo`/`vtool`; notarization подтверждает системный Gatekeeper assessment, без `xcrun stapler`. Проверка конкретного stapled ticket остаётся в developer release pipeline и clean-Mac приёмке. Source build и fixture suite требуют developer tools.

Будущая команда установки без `git clone` должна скачивать **installer и его общий helper по конкретному commit**, проверять заранее опубликованные digests, затем запускать. Текущий installer состоит из двух файлов; скачивать только `install-release.sh` и выполнять его без `install-common.sh` нельзя. Инструкция с фиктивными tag/SHA/Team ID не публикуется.

Homebrew tap/cask будет дополнительным каналом после подписанного релиза. Автоматического обновления в фоне сейчас нет.

## Google Workspace отдельно

Установщик не включает `gws`, не запускает OAuth и не отправляет Google-запросы. Установите и настройте `gws` по [документации проекта Google Workspace CLI](https://github.com/googleworkspace/cli) под тем же пользователем macOS; Calendar/Tasks доступ подтверждается отдельно. Затем укажите абсолютный путь к доверенному executable в настройках g-calendar. При пустом поле проверяются `~/.local/bin/gws`, `/opt/homebrew/bin/gws` и `/usr/local/bin/gws`, а не произвольный PATH оболочки. Нажмите «Синхронизировать»: первый sync — read-only; записи происходят только по явным действиям в интерфейсе. Поддерживаемый диапазон версий `gws` пока не закреплён; не считать любую будущую версию автоматически совместимой.

Для новой OAuth-настройки `gws` требуется Google Cloud project и доступ аккаунта по его инструкции. Уже рабочую авторизацию не нужно менять ради установки g-calendar. Upstream `gws` предупреждает, что это не официально поддерживаемый продукт Google и возможны breaking changes; его installation/auth prerequisites отдельны от prerequisites сборки g-calendar.

Без настройки Google можно предварительно посмотреть синтетический UI после сборки: завершите обычный экземпляр и выполните `open dist/g-calendar.app --args --demo`. Этот режим не вызывает `gws`, не читает пользовательский кэш и не запрашивает разрешения уведомлений.

## Локальные данные

`~/Library/Application Support/g-calendar/` содержит `snapshot.json`, `local-task-metadata.json`, `local-event-reminders.json`, журнал `pending-verification.json` с lock и возможные `reviewed-attempt-*.json`. Настройки хранятся в UserDefaults. Эти JSON-файлы не шифруются приложением и могут содержать личные Calendar/Tasks данные или draft; не переносите их в checkout и не прикладывайте к публичным отчётам. Credentials остаются под управлением `gws`. Installer/uninstaller сохраняют все эти данные; очистка данных или OAuth не входит в удаление bundle.

## Удаление

```bash
./scripts/uninstall.sh
./scripts/uninstall.sh --destination "/absolute/path/Applications"
```

Удаляется только проверенный установленный `g-calendar.app`. Настройки, reminders, cache, journal, OAuth и сохранённая rollback-версия остаются. Чужой или повреждённый bundle автоматически не удаляется.

## Проверки установщика

```bash
for script in scripts/install-common.sh scripts/install-source.sh scripts/install-release.sh scripts/uninstall.sh scripts/test-installers.sh; do
  bash -n "$script" || exit
done
./scripts/test-installers.sh
```

Fixture suite создаёт маленькие настоящие arm64 Mach-O bundles с ad-hoc подписью и изолированные destination в временном каталоге. Он не меняет пользовательский `~/Applications`, не открывает UI, не вызывает `gws`/OAuth. В транзакционных fixtures process probe подменяется для изоляции; отдельный настоящий fixture executable проверяет detection без подмены и завершается сам. Проверяются также Mach-O target и round-trip настоящего `ditto` ZIP с extended attribute и AppleDouble metadata. Это synthetic metadata, не настоящий notarization ticket. Подписанный release/download/чистый Mac остаются отдельной приёмкой и не доказываются локальными fixtures.
