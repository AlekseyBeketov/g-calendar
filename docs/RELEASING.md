# Упаковка и выпуск macOS

Текущая сборка — **0.2.0 (build 2), arm64, macOS 13+**. Apple Developer Program не используется. Поддерживаются локальные ad-hoc пакеты и явный режим **unsigned-preview** с подписанной EdDSA лентой и ZIP для Sparkle. EdDSA подтверждает подлинность обновления, но не заменяет Apple notarization или первую проверку Gatekeeper. Публичный Release автоматически не создаётся.

## Выпустить обновление через GitHub Releases

1. Запишите пользовательские изменения в `CHANGELOG.md` и подготовьте короткий Markdown-файл примечаний для конкретного выпуска. Каждый логический продуктовый change проходит проверки и получает отдельный коммит; push исходников не публикует приложение.
2. Поднимите SemVer и build number: `./scripts/set-version.sh --version 0.3.0`. Числовой `CFBundleVersion` должен строго увеличиваться; именно по нему Sparkle сравнивает версии. Для воспроизводимого номера можно передать `--build N`, но он также должен быть больше текущего. Просмотрите и закоммитьте diff plist и changelog.
3. Выполните релевантные проверки и `./scripts/build-app.sh`. Перед первой упаковкой выполните `./scripts/setup-installer-tools.sh`: pinned Python-инструменты Finder layout устанавливаются только в ignored `.build/installer-layout-venv`, без изменения системного Python. Все исходники, версия в bundle и будущий tag должны относиться к одному проверенному коммиту.
4. Подготовьте файлы в новом каталоге:

```sh
./scripts/prepare-update.sh --output dist/packages/0.3.0-preview --notes /absolute/path/to/release-notes.md
./scripts/test-updates.sh dist/packages/0.3.0-preview
```

Пример предполагает уже выбранную версию 0.3.0; не выполняйте bump только ради чтения инструкции. Helper создаёт `g-calendar-<version>-arm64-preview.dmg`, ZIP, `release-manifest.json`, `SHA256SUMS` и **`appcast.xml`**. Он проверяет соответствие публичного ключа в bundle ключу Keychain, подписывает ленту и архив, проверяет подписи и финальные checksum. Подписанный XML нельзя редактировать после генерации.

5. По отдельному запросу владельца создайте draft GitHub Release с тегом `v<version>` на проверенный source commit и приложите **все пять файлов**. Просмотрите release notes, архитектуру, manifest (`signing=ad-hoc`, `distribution=unsigned-preview`, `notarized=false`) и проверьте установку скачанного DMG на Mac с сохранённым quarantine. Затем публикуйте только после явного разрешения. Не выдавайте SHA-256 или EdDSA за Developer ID. Официальные варианты пользовательского первого открытия описывает [Apple](https://support.apple.com/en-us/102445); не отключайте Gatekeeper и не удаляйте quarantine.
6. Release должен быть обычным стабильным **Latest**, поскольку приложение читает `https://github.com/AlekseyBeketov/g-calendar/releases/latest/download/appcast.xml`. Draft/prerelease не является этим каналом. Внутри ленты ZIP указывает на конкретный tag, поэтому старые архивы и теги не перезаписывают.

Обычная публикация исходников или создание тега без `appcast.xml` не включает обновление пользователей. До первого опубликованного appcast ручная проверка может показать ошибку недоступной ленты. Последующие подписанные версии появятся у пользователей с включённым автообновлением примерно в течение суток работы приложения; ручная проверка доступна сразу.

## Подпись и хранение ключа

В macOS Keychain создан отдельный Sparkle signing account **`g-calendar`**. Приватный ключ не находится в репозитории, app bundle, переменных команд или release assets. В `resources/Info.plist` лежит только `SUPublicEDKey`. Официальные инструменты pinned Sparkle 2.10.0 находятся в ignored `.build/dependencies/sparkle-2.10.0/bin/` после `scripts/fetch-sparkle.sh`.

До первого распространения владелец должен сделать приватную зашифрованную резервную копию ключа по [инструкции Sparkle](https://sparkle-project.org/documentation/). Не экспортируйте его в checkout и не печатайте в отчётах. Без Developer ID потеря EdDSA-ключа не позволяет безопасно выпустить обновление для уже установленных приложений: потребуется ручная переустановка. Не генерируйте новый ключ при каждом релизе.

В приложении включены `SURequireSignedFeed` и `SUVerifyUpdateBeforeExtraction`: проверяются и лента, и ZIP до распаковки. Auto-update использует Sparkle с собственной установкой и перезапуском; он не вызывает строгий Developer-ID-only `install-release.sh`. Этот старый сценарий остаётся отдельным, доступным только для будущих notarized-пакетов. Телеметрия Sparkle отключена. Проверки/скачивание начинаются после завершения начальной настройки; demo и synthetic режимы Sparkle не запускают.

## Локальный DMG

Для следующего осознанного изменения версии используйте helper до сборки:

```sh
./scripts/set-version.sh --version 0.3.0
```

Скрипт проверяет SemVer, обновляет `CFBundleShortVersionString` и увеличивает числовой `CFBundleVersion`. Если нужен заданный номер сборки, передайте `--build N`. После этого просмотрите diff `resources/Info.plist` и только затем собирайте пакет. Сам helper не создаёт Git tag, Release или фоновые обновления.

После разрешённой актуальной сборки (инструменты оформления подготавливаются один раз):

```sh
./scripts/setup-installer-tools.sh
./scripts/package-dmg.sh --app dist/g-calendar.app --output dist/packages/local-preview
./scripts/verify-release.sh --app dist/g-calendar.app --mode local --artifacts dist/packages/local-preview
```

Скрипт работает с копией приложения, не меняет запущенный `dist/g-calendar.app`. Выходной каталог должен быть свежим: существующие assets/checksums не перезаписываются. Получаются `g-calendar-<version>-arm64-local.dmg`, ZIP, `SHA256SUMS`, `release-manifest.json`. В образе приложение, ярлык `/Applications`, утверждённый голубой фон с волнами и стрелкой, переносимый Finder layout и автономная инструкция. Фон хранится внутри `.installer/background.tiff`; alias создаётся на собственном writable image и повторно разрешается системным API на финальном readonly mount, без путей checkout автора. Подробности и исходник оформления — `resources/installer/README.md`. Выполняются `hdiutil verify` и проверка содержимого собственного readonly mount; размонтируется только этот mount.

**Local** означает целостную ad-hoc подпись и локальную проверку. Это не Developer ID, не notarization и не подтверждённый скачанный Gatekeeper запуск. Не удалять quarantine и не отключать Gatekeeper.

## Developer ID + Apple notarization (не текущий путь владельца)

Этот сценарий неприменим, пока владелец не пересмотрит отказ от Apple Developer Program. Текущий `sign-release.sh` дополнительно останавливается при наличии nested framework; перед будущим Developer ID выпуском потребуется реализовать явный порядок переподписи helpers Sparkle изнутри наружу. Только после такого решения владелец заранее предоставляет существующую **Developer ID Application** identity, её ожидаемый 10-значный Team ID и существующий Keychain profile для `notarytool`. Секреты не помещаются в репозиторий, команды не принимают Apple ID/password параметрами и не выводят содержимое service responses. Не создавать credentials автоматически.

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

Скрипты не создают GitHub Release и не загружают assets. Auto-update уже встроен в приложение; для него нужно публиковать подписанную ленту вместе с архивом по процедуре выше. После отдельного разрешения владельца: закреплённый tag, draft Release, все assets и SHA256SUMS; проверить GitHub integrity/immutable release, затем опубликовать. Digest соседнего файла защищает от порчи; Developer ID requirement подтверждает издателя. Homebrew cask уместен после проверенного подписанного релиза; не добавлять `zap` пользовательских данных.

## Первичные источники

- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — ZIP submission, ticket к app/DMG, повторная упаковка ZIP.
- [Apple: Creating distribution-signed code for the Mac](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) — Developer ID, timestamp, hardened runtime, inside-out signing.
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — проверка Gatekeeper до распространения.

Документация Apple проверена через официальный Context7. Фактическая signed acceptance остаётся внешней до credentials и чистого Mac.

- [Sparkle: programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/) — native updater и SwiftUI.
- [Sparkle: publishing](https://sparkle-project.org/documentation/publishing/) — подпись архивов и appcast.
