# Упаковка и выпуск macOS

Текущая сборка: **arm64, macOS 13+**. SwiftUI/AppKit стек сохраняется. Публичный GitHub Release, выбор лицензии и предоставление Developer ID credentials — отдельные решения владельца. Пуш исходников их не выполняет.

## Локальный DMG

После разрешённой актуальной сборки:

```sh
./scripts/package-dmg.sh --app dist/g-calendar.app --output dist/packages/local-preview
./scripts/verify-release.sh --app dist/g-calendar.app --mode local --artifacts dist/packages/local-preview
```

Скрипт работает с копией приложения, не меняет запущенный `dist/g-calendar.app`. Выходной каталог должен быть свежим: существующие assets/checksums не перезаписываются. Получаются `g-calendar-<version>-arm64-local.dmg`, ZIP, `SHA256SUMS`, `release-manifest.json`. В образе приложение, ярлык `/Applications`, светлый переносимый Finder layout и автономная инструкция. Выполняются `hdiutil verify` и проверка содержимого собственного readonly mount; размонтируется только этот mount.

**Local** означает целостную ad-hoc подпись и локальную проверку. Это не Developer ID, не notarization и не подтверждённый скачанный Gatekeeper запуск. Не удалять quarantine и не отключать Gatekeeper.

## Developer ID + Apple notarization

Владелец заранее предоставляет существующую **Developer ID Application** identity, её ожидаемый 10-значный Team ID и существующий Keychain profile для `notarytool`. Секреты не помещаются в репозиторий, команды не принимают Apple ID/password параметрами и не выводят содержимое service responses. Не создавать credentials автоматически.

В приватной оболочке задаются `G_CALENDAR_SIGN_IDENTITY`, `G_CALENDAR_TEAM_ID`, `G_CALENDAR_NOTARY_PROFILE`, затем:

```sh
./scripts/sign-release.sh --app dist/g-calendar.app --output dist/release-staging/g-calendar.app
./scripts/notarize-release.sh --app dist/release-staging/g-calendar.app --output dist/packages/signed-release
./scripts/verify-release.sh --app dist/release-staging/g-calendar.app --mode signed --signature-only
```

Последняя команда проверяет исходную подписанную staging copy: нотарификация выполняется на собственной временной копии. Финальные ZIP/DMG проверяются внутри `notarize-release.sh` **после** ticket stapling и расчёта окончательных digest. Не принимать `--signature-only` за готовность выпуска.

Последовательность:

1. Проверить bundle ID, executable, arm64 и minimum OS; скопировать в новый staging.
2. Подписать Developer ID с hardened runtime и secure timestamp. Проверить certificate requirement и ожидаемый Team ID. При появлении nested framework/helper pipeline останавливается до явного inside-out signing plan.
3. Отправить ZIP Apple через существующий Keychain profile; ждать до 30 минут, принять только статус `Accepted`.
4. Staple ticket к `.app`, проверить ticket и Gatekeeper execute assessment. Создать ZIP заново из stapled app: к ZIP напрямую ticket не прикрепляется.
5. Создать и Developer ID подписать DMG, отправить Apple, staple DMG; проверить ticket, publisher identity, Gatekeeper open assessment.
6. После окончательных изменений написать `notarized=true`, пересчитать SHA-256 для ZIP, DMG и manifest. Signed filenames: `g-calendar-<version>-arm64.zip` / `.dmg`.
7. До публикации скачать assets и проверить их на чистом Mac: digest, expected publisher, quarantine-preserving первый запуск, DMG install и upgrade с сохранением данных. Этот внешний шаг не заменяется локальными проверками.

Notary failure не меняет исходное приложение и не оставляет пакет, объявленный готовым. Для диагностики rejected submission владелец использует Apple notary history/log отдельно в приватной оболочке. Повторные команды требуют нового output directory.

## Публикация

Эти скрипты **не** создают GitHub Release, не загружают assets и не включают auto-update. После отдельного разрешения владельца: закреплённый tag, draft Release, все assets и SHA256SUMS; проверить GitHub integrity/immutable release, затем опубликовать. Digest соседнего файла защищает от порчи; Developer ID requirement подтверждает издателя. Homebrew cask уместен после проверенного подписанного релиза; не добавлять `zap` пользовательских данных.

## Первичные источники

- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — ZIP submission, ticket к app/DMG, повторная упаковка ZIP.
- [Apple: Creating distribution-signed code for the Mac](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) — Developer ID, timestamp, hardened runtime, inside-out signing.
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — проверка Gatekeeper до распространения.

Документация Apple проверена через официальный Context7. Фактическая signed acceptance остаётся внешней до credentials и чистого Mac.
