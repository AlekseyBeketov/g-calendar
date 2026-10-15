# Проверки g-calendar

Обновлено: **2026-10-15**. Подробные suite-таблицы и Computer Use матрица ниже описывают датированную локальную приёмку 2026-10-07/08, а не новый полный прогон текущего `main`. Проверки более поздних функций записаны рядом с изменениями в [OpenSpec tasks](../openspec/changes/g-calendar-mvp/tasks.md) и [согласованных дизайнах](plans/). Старые числа assertions не следует трактовать как результат тестирования всего текущего исходника. Этот документ также не подтверждает подписанный релиз, полный VoiceOver-проход или видимый notification banner.

## Сборка и автоматические проверки

### Поддержка автора — 2026-10-14

Реализованы постоянная кнопка в footer настроек и отдельное окно поддержки: CloudTips по умолчанию, Boosty вторым, реальные QR/марки, открытие и копирование ссылки. Подписей о регистрации нет.

`scripts/test-author-support.sh` прошёл 35 assertions: точные URL и отдельные QR payload (Boosty сохраняет `?qr=true` из исходника), выбор провайдера, success/failure браузера и clipboard через подставные handlers, ресурсный fallback и декодирование offscreen render в Light/Dark. Повтор того же теста на PNG из окончательного bundle также прошёл 35 assertions. Изолированный Vision/CoreVideo тест потребовал разрешённого системного доступа вне sandbox; использовано CPU-only распознавание. Браузер, буфер обмена пользователя и платёж не использовались этими tests.

Основной invariant suite прошёл 975 assertions. Strict OpenSpec: `valid=true`, `issues=[]`. `git diff --check` и shell syntax check успешны. Итоговый optimized bundle — `/Users/alexbeketov/g-calendar/dist/g-calendar.app`, arm64/macOS 13+, локальная ad-hoc подпись проверена `codesign --verify --strict`. Ресурсы AuthorSupport включены до подписи bundle.

Computer use не применялся. Offscreen проверка не подтверждает реальный ручной UI, spoken VoiceOver или банковскую оплату. Утверждённый дизайн — [author-support-design](plans/2026-10-14-author-support-design.md); результаты проверки записаны в этом разделе. Рабочий план реализации хранится локально.

Product commit `05d4d85` отправлен в origin/main; согласованный дизайн сохранён коммитом `f041b18`. Переносимый custom skill опубликован в main Dev Kit (`4945279`) и read-back проверен в `.agents`, всех объявленных Hermes endpoints и Cursor rule. Его создание не меняло чужую параллельную рабочую копию Dev Kit.

### Историческая приёмка — 2026-10-07/08

Все команды выполнялись в `/Users/alexbeketov/g-calendar` через `rtk proxy`.

| Команда | Результат |
|---|---|
| `./scripts/build-app.sh` | exit 0, optimized arm64/macOS 13+, финальная сборка run-54154 |
| `./scripts/test.sh` | exit 0, 440 assertions |
| `env G_CALENDAR_TEST_OPTIMIZE=1 ./scripts/test.sh` | exit 0, 440 assertions, повторён после финального UI fix |
| `./scripts/test-native-ui.sh` | exit 0, 20 assertions |
| `./scripts/test-installers.sh` | exit 0, 26 сценариев |

Модельные fixtures проверяют Google argument vectors и exact-resource GET, настоящие field/identity mismatches, empty/omitted notes, date-only due, timestamp precision, tombstones, cache/pagination failure, refresh supersession, DST/overlap, reminders и runtime isolation. Журнал удерживает stable flock на весь write + exact GET; stale instances, attempt identity, delayed GET, corruption и отдельный процесс покрыты регрессиями. Повторный INSERT при неизвестном результате не выполняется.

Native UI suite проверяет clip synchronization, сохранение scroll origin при layout update, removal observers и scoped keyboard responder. Поиск использует owned NSTextField: Escape очищает binding, field editor и control; остальные команды сохраняют native responder chain. Cmd+N заменяет стандартную `.newItem` команду macOS и не создаёт лишнюю вкладку.

## Computer Use — актуальный исходный код

Прогоны 6–7 октября использовали только built `.app` и синтетический `--demo`, отдельные настройки, отключённые gws, пользовательский кэш и UserNotifications. Доступы работают; TCC/helper binaries не менялись. Финальный busy/ready/recovery/loading/setup и installed-app проход использовал run-54154. Предшествующие current-source проходы state/theme/modal/pinned calendar выполнены на run-43884–53128; финальная сборка содержит эти исправления.

| Область | Внешний результат |
|---|---|
| Sidebar | icon/text/blank/interior edges переключают section/list; выбранный calendar и visibility checkbox независимы; отдельные local controls не перекрыты decoration |
| Tasks | компактные rows, aligned date/list metadata, просроченные с текстом/иконкой, отсутствие пустых групп, отдельные Upcoming/Undated, доступная прокрутка, default list и explicit columns fallback |
| Keyboard/search | Cmd+1/2, Cmd+F с native caret, текст/clear/no-match/Escape, Tab/стрелки/Return, scoped Space, возврат после editor; text fields/menu/sheets сохраняют ввод |
| Calendar | initial 08:00 без clipping; horizontal scroll до воскресенья, шкала часов остаётся слева; вертикальная прокрутка до 23:00, headers закреплены; manual origin сохраняется при collapse undated |
| Date-only overflow | восемь all-day событий и длинный список dated tasks достижимы в bounded scroll; Today region прокручен до последней fixture task 45 |
| Appearance/resize | Light/Dark/System через Settings, широкое и узкое/короткое окно; content 761×561–1434×897 pt, scale 2; full-row hit area и читаемые native состояния |
| States | loading и setup с доступом к Settings; empty Calendar/Tasks, no-match с clear; stale/offline/failed сохраняют данные, читаемые status/cache/badge/Retry |
| Busy/recovery | disabled Create/complete и Cmd+N; предупреждение/шапка/фильтры внутри короткого окна; retained draft, неизвестный ID не допускает recheck/write; длинный draft прокручен до инструкции/ручной сверки, footer доступен |

В финальной приёмке обнаружено два дополнительных дефекта. Стандартная команда New Window конкурировала с Cmd+N; `CommandGroup(replacing: .newItem)` устранил создание вкладки, ready теперь открывает task editor, busy сохраняет одно окно без editor. При busy list мог вытеснить шапку за viewport. Конечный GeometryReader размер detail/workspace и bounded recovery text удерживают status/warning/header/list в окне. Повторный screenshot в коротком окне подтвердил исправление. Простое fixedSize и ограничение только TaskWorkspace ранее не устранили overflow; эти попытки не считались успешной приёмкой.

Settings больше не вызывает прежний Sky helper SIGTRAP: native sections с пассивным decoration заменили проблемную структуру; current screenshots/AX и многократное переключение темы проходят. Разовый native pipe error устранялся переподключением; доступы не объявляются оставшейся блокировкой.

## Кодовый и внешний аудит отступов

Общий контракт: **24 pt** внешний inset, **16 pt** между разделами, **8 pt** между label/field. Footer находится вне прокручиваемого EditorBody, который ограничивает высоту по viewport. Удалён лишний trailing 8 pt overflow inset. Decoration overlays не участвуют в hit testing/AX.

| Поверхность | Размер/источник | Внешняя приёмка |
|---|---|---|
| Task create/edit | 500 pt, shared 24/16/8 | Симметричные края, title focus, date/list context, reachable Cancel/Save; финальный Cmd+N screenshot |
| Event create/edit | 540 pt, shared 24/16/8 | Timed/all-day, часовой пояс и footer; короткое окно без clipping |
| Read-only/recurring event | 540 pt, selectable значения | Читаемые значения, Save/Delete отсутствуют, Close доступен |
| List create/rename | 460 pt, shared 24/16/8 | Title focus, Cancel/Save, создание/rename/delete собственных demo objects |
| List manager | 500 pt, content-fit max шесть rows | Полная строка открывает editor, нет прежней избыточной высоты, footer доступен |
| Task reminder | 500 pt, off/on content height | Date control и footer доступны, локальный scope |
| Recovery draft | 460 pt, bounded body | Финальный длинный draft в коротком окне: scroll reaches manual-review action, Close виден, 24 pt inset |
| Settings | outer 24/sections 16/fields 8, section inset 12 | Light/Dark/System и небольшой viewport; footer доступен, AX helper не падает |
| Confirmations | Native confirmationDialog | Раздельные cancel/destructive действия для собственных demo task/event/list |
| Primary surfaces | Sidebar 36 pt targets; task/header insets 24; bounded calendar | Шапка не переносится побуквенно; status/warning остаются сверху, list scroll bounded |

Source palette и fixtures используют общий sRGB ThemePalette. Предыдущий отрицательный fixture воспроизвёл contrast 4.43156:1; исправлены роли и проверены Light/Dark, alpha selections, control boundaries и event tint extremes. Это проверка заданных ролей, не заявление полного WCAG соответствия native приложения. AX labels и keyboard проверены; голосовой VoiceOver walkthrough отдельно не выполнен.

## Производительность

Метод, sample sizes, измерения и предварительные бюджеты — [GUI_PERFORMANCE](GUI_PERFORMANCE.md), агрегаты — [JSON](gui-performance-baseline.json). macOS 27.0.1, M4 Pro, 24 GiB, 51 synthetic tasks/10 events. GUI action → AppKit update отделён от pixel latency/FPS/GPU. `.scroll` schema 2 измеряет handler duration: 242 callbacks, p95 0,220 ms, max 0,255 ms. Старый schema 1 idle wait исключён из baseline. Idle CPU 0,4/0,6/0,5%, RSS 199,2 MiB.

Финальный optimized model run: 4096 tasks/search, девять samples, p50 1,635 ms/p95 1,917 ms; grouping p50 4,967/p95 6,271 ms; overlap 1024 events 1,48 ms за один проход. Вариативность между прогонами учитывается; это не GUI или network latency. Instruments/xctrace отсутствует; peak resource/FPS и attribution RunLoop stalls не подтверждаются.

## Установщики — fixtures и настоящие bundles

`package-dmg.sh --output dist/packages/2026-10-07-release-preview` завершился exit 0. Созданы versioned DMG/ZIP, manifest и SHA256SUMS; codesign integrity, ZIP round trip, `hdiutil verify`, readonly mount, Applications shortcut и resources проверены. Finder Computer Use показал приложение, Applications и инструкцию. Hidden files могут отображаться согласно личной настройке Finder; она не менялась.

Реальный bundle из mounted DMG установлен в собственный private `/private/tmp/g-calendar-native-install-20261007-*` destination. Из установленного пути запущен `--demo`; Calendar/Tasks видны. После закрытия проверены две разные бинарные версии, установка/upgrade, backup hash, rollback hash и uninstall. Synthetic data sentinel побайтно неизменен, backup сохранён, только собственный mount размонтирован. Основные Applications, пользовательский cache/journal/reminders/settings и credentials не изменялись.

26 installer fixtures покрывают atomic install/upgrade/rollback, interrupted replacement/recovery, lock/concurrency, foreign/running bundle, archive traversal/symlink/special files, bad checksum/signature, spaces/permissions, platform/architecture/minOS, actual Mach-O и host без CLT. macOS 13 compatible fallback использует flock через доступный Perl; проверки внешних attributes и ad-hoc signatures выполнялись на реальных маленьких Mach-O fixtures.

Локальные artifacts **ad-hoc, not notarized**. Developer ID/notarization/stapling/Gatekeeper scripts реализованы и документированы, но credentials не предоставлены, signed downloaded release/clean Mac не тестировались. Public pinned one-command installer contract существует; реальный публичный pin появится после отдельно разрешённого release. Fake SHA/version/Team ID и обход Gatekeeper не предлагаются. Из текущего checkout работает `./scripts/install-source.sh`.

## Live Google и уведомления — ранее выполненный scope

5 октября два actual-app synthetic Google lifecycle завершили по 11 read-back verified шагов; в каждом удалены все три собственных объекта и подтверждён read-only restart cleanup. Fresh timeout до первой записи оставил created=0. IDs и личные данные не публикуются. После межпроцессного fix live не повторялся; его regression fixtures и current demo recovery прошли. Чужие объекты не использовались.

Actual bundle notification authorization, alert/sound settings и доставка одного собственного уведомления в Notification Center подтверждены ранее. Человеческое наблюдение видимого баннера отдельно не получено; доставка не выдаётся за подтверждение баннера.

## Repository hygiene — изолированный проход 2026-10-07

Следующие результаты относятся к отдельному documentation-only проходу в worktree от checkpoint **a406d3b**. Они сохранены как датированная история; при переносе в main полезное содержание сверено с текущими исходниками и устаревшие утверждения о Git заменены. Проверки ниже не выдаются за повторный прогон 2026-10-08.

Scope того прохода: `.gitignore`, README и документация; Swift, runtime, build/release scripts, resources, подпись и публикация не менялись. Тогдашняя verification секция фиксировала именно тот worktree, не текущий main checkout.

Первоначальные `.build/`, `.swiftpm/`, `DerivedData/`, `.codegraph/`, `.hermes/`, `dist/` и `.DS_Store` исключают local artifacts; их назначение сохранено. Строка `:-` — обычный literal ignore pattern, не comment/negative rule. Документационный worktree 2026-10-07 не содержал такой path и тогда удалил правило; при интеграции в основной checkout обнаружен существующий ignored текстовый файл `:-` с локальной signing/designated-requirement заметкой (mtime 2026-10-02). Файл не удалялся и не добавляется в Git; pattern восстановлен, чтобы не раскрыть локальное значение. Проверки `./:-` из исторического прохода трактовали путь как pathspec magic, а `GIT_LITERAL_PATHSPECS=1` не поддерживался тогдашним `check-ignore`; эти попытки не считались успешными ignore-проверками.

Добавленные тогда правила были ограничены build/debug/Xcode artifacts, user IDE state, macOS metadata, agent caches/worktrees и типичными private auth/app-data exports. Root-only JSON rules не скрывали `Tests/Fixtures`; `.env.example`/`.env.template`, shared Xcode/IDE configuration и обычный JSON оставались видимыми. Ignore не защищает уже tracked файлы и не заменяет privacy review.

Из необходимой repository guidance был добавлен только [CONTRIBUTING](../CONTRIBUTING.md). `.editorconfig` не требовался для точечной docs-задачи; `LICENSE`, security contact/SLA, CI и release metadata не создавались без утверждённой политики. Выбор лицензии, signing/notarization, signed downloaded release/clean Mac, VoiceOver/banner и compatibility/support decisions остаются открыты в [PENDING_DECISIONS](PENDING_DECISIONS.md).

### Проверки, выполненные в worktree 2026-10-07

| Проверка/команда | Фактический результат того прохода |
|---|---|
| `git ls-files -z` + `git check-ignore --no-index --stdin` для tracked paths | 100 tracked paths, ни один не игнорировался; exit 1 у `check-ignore` ожидался для полного отсутствия matches |
| `git ls-files -ci --exclude-standard` | exit 0, пустой вывод |
| `git check-ignore -v --no-index --stdin`, representative matrix | 41 artifact path игнорировался, 33 source/docs/fixture/config/template path оставались видимыми; retained original rules проверялись отдельно |
| Relative Markdown links/anchors в README, CONTRIBUTING и пяти связанных docs | 44 ссылки/anchors разрешались в существующие paths/headings |
| Script references и shell examples в тех же docs | 12 существующих script paths, 10 напрямую вызываемых executable scripts, 13 shell blocks проходили `bash -n`; sourced helper не обязан быть executable |
| `bash -n` отдельно для каждого `scripts/*.sh` | все 14 shell scripts проходили, exit 0 |
| `OPENSPEC_TELEMETRY=0 openspec validate g-calendar-mvp --strict --json` | exit 0, `valid=true`, `issues=[]`; tasks/specs не менялись и внешние gates не закрывались |
| `git diff --check` и diff scope review | exit 0; изменялись только `.gitignore`/Markdown; Swift, tests, scripts, resources, OpenSpec, AGENTS и download.html были неизменны; tracked deletions отсутствовали |
| Credential-pattern scan tracked text + CONTRIBUTING | 98 текстовых файлов, flagged paths=[]; новые строки проверялись на личные home paths/email; это не гарантия отсутствия любых секретов |
| Public GitHub REST read-only: repository, releases, source installer/helper на `main` | HTTP 200; repo public/default branch `main`, releases=[]; blobs installer/helper совпадали с локальными tracked версиями |

Тогдашний local acceptance harness запускался как `python3 .hermes/verification/repository-hygiene.py`, exit 0. Это была ignored одноразовая проверка в task worktree, не штатный скрипт приложения; harness не переносился как проектный файл.

Source install из public `main` описан как уже доступный workflow, а не будущая публикация скриптов. Это mutable source checkout, **не** опубликованный signed release; release version/SHA/Team ID не подставлялись. GitHub проверялся без authenticated mutation, push или загрузки assets.

Внешние ссылки из проверенных тогда файлов открывались в upstream/Apple pages. Apple Developer pages отдавали JavaScript shell: проверялась доступность/названия, не содержательная валидация всего notarization workflow. README upstream `gws` подтверждал отдельные Google Cloud/OAuth prerequisites и предупреждение о breaking changes; Calendar/Tasks authorization не выполнялась.

Full build, invariant/native UI/installer suites, GUI, live Google и notification acceptance в том проходе не повторялись: runtime и scripts не менялись. Основной checkout, ignored artifacts и пользовательские данные не менялись; commit, push, Developer ID signing, notarization и публикация не выполнялись.

## Сборка после объединения утверждённой иконки — 2026-10-08

`./scripts/build-app.sh` завершился успешно на исходнике `7657db81f0cc3ca5bf670ddb854113452b0c5e4b` (`feat: use approved calendar app icon`). Bundle: `/Users/alexbeketov/g-calendar/dist/g-calendar.app`; executable arm64, размер 4,512,640 bytes, mtime 2026-10-08 21:21:09 MSK. Повторная `codesign --verify --deep --strict --verbose=2 dist/g-calendar.app` завершилась exit 0: `valid on disk`, `satisfies its Designated Requirement`. Это проверка bundle после текущей сборки, а не публичная подпись/notarization. В рамках последующих документационных изменений продуктовые suites и сборка повторно не запускались.

## Scope и сохранность данных

[OpenSpec](../openspec/changes/g-calendar-mvp/tasks.md) фиксирует завершённую локальную реализацию/приёмку; этот журнал и [утверждённый дизайн](../design/DESIGN.md) сохраняют результаты и продуктовые решения. Рабочие ExecPlan хранятся локально по [правилам планов](plans/README.md). Внешние release/VoiceOver/banner условия сохранены в [PENDING_DECISIONS](PENDING_DECISIONS.md). Checkpoint 62f153f — исторический; его Git-записи не являются текущей проверкой remote или публикации. Source commit/push требует явного owner approval и сам по себе не означает выпуск приложения.

Design содержит два утверждённых PNG и DESIGN/README. Личный пустой download.html не изменён. Private ledgers/profile/raw captures остаются вне repo; baseline содержит только разрешённые синтетические агрегаты. `.hermes`, `.codegraph`, dist, credentials и `.DS_Store` не добавляются в Git. Regex privacy scan и diff check выполняются отдельно; scan не гарантирует отсутствие любого возможного секрета.

Финальный контроль 2026-10-07: strict OpenSpec `valid=true`, `issues=[]`, exit 0; `git diff --check` exit 0. SHA256SUMS для финальных ZIP/DMG/manifest: все OK. Ни один Swift source не новее финального executable. Privacy scan 92 текстовых файлов: credential-pattern flagged paths=[], личный download.html остаётся 0 bytes. Existing ignored design/.DS_Store сохранён.

## Google onboarding и подписанные GitHub updates — 2026-10-15

Реализованы выбранные шапки календаря/задач, встроенный public Google Client ID и PKCE-вход, второй шаг с автообновлением/автозапуском, Sparkle 2.10.0 и подготовка unsigned-preview обновлений. Версия кандидата: 0.2.0 (build 2). Приватный EdDSA ключ создан в Keychain account g-calendar; в исходниках и bundle только public key.

`./scripts/test.sh` прошёл **989 assertions**; `./scripts/test-task-workspace-ui.sh` — **106 assertions** без computer use. `./scripts/test-installers.sh` — **26 scenarios**; первый restricted запуск остановился на запрете process inspection, повторный разрешённый запуск прошёл полностью. `scripts/prepare-update.sh` создал настоящий ZIP/DMG и подписанный appcast; hdiutil verify, проверка собственного readonly mount, подписи ленты/ZIP и checksum прошли. `scripts/test-updates.sh` подтвердил загрузку Sparkle в текущей ad-hoc конфигурации, проверку реального ZIP через CryptoKit public key, отказ при изменении байта, сохранение framework при распаковке и отказ для опасных symlinks/записей под alias. Дополнительно настоящий updater с обязательной подписанной лентой успешно запущен в изолированном ad-hoc fixture без сети и изменения пользовательских настроек.

Native image/геометрия и успешная сборка не доказывают видимый системный баннер, живой OAuth, Gatekeeper первого скачанного запуска или обновление уже опубликованного приложения. Эти действия требуют ручной приёмки; Google данные не изменялись, GitHub Release и tag не создавались. Старый notification icon из скриншота отличается от текущего approved icns; исходник и вложенный ресурс совпадают. Первый restricted вызов lsregister вернул -10822. Последующий разрешённый запуск удалил ровно 71 регистрацию старых build backups и зарегистрировал актуальный dist bundle. Backup теперь имеет суффикс .build-backup вместо .app. Корректный synthetic запуск через Launch Services подтвердил own_notification_delivered=true; видимый баннер и его иконку должен подтвердить владелец.

## Completion audit: retained local notification content — 2026-10-15

Аудит обнаружил пробел в прежней приёмке: тесты автоматического Google planner не проверяли native content отдельного UserNotificationScheduler. После выделения реальной сборки UNNotificationRequest в pure factory регрессионный тест воспроизвёл `FAIL local native notification must show its reminder date and time`. Scheduler теперь использует название ресурса и локализованную дату/время срабатывания; в body остаётся метка локального напоминания. Точное время, секунды и account namespace сохранены. Это не возвращает удалённые редакторы локальных напоминаний и не означает поддержку точного времени Google Tasks.

Финальный прогон `./scripts/test.sh` после исправления: **998 assertions, PASS**. Девять новых проверок читают настоящий UNNotificationRequest без Notification Center: русский и английский текст, переход через полночь, точный timestamp/timezone/seconds, разовый trigger и сохранение REST namespace. Strict OpenSpec validation проходит.

Приложение пересобрано через `./scripts/build-app.sh`. Новый preview создан из этой сборки в отдельном локальном output directory: ZIP round trip, readonly DMG mount, hdiutil verify, checksums, EdDSA-подписи XML/ZIP прошли. Повторный `scripts/test-updates.sh` подтвердил проверку подлинного/изменённого ZIP, безопасную распаковку и настоящий startup updater в изолированной ad-hoc копии. Регистрация актуального bundle обновлена, новых устаревших backup registrations нет.

Обновлённый bundle через Launch Services отправил ровно одно synthetic уведомление: `scheduled=1 own_notification_delivered=true visible_banner=needs_human_verification`. Google, reminder metadata и системные разрешения не менялись. Внешний вид иконки и баннера не объявлен подтверждённым.

## Owner onboarding acceptance and approved DMG artwork — 2026-10-15

Владелец подтвердил: «Вход и оба шага работают», включая календарь, и принял DMG-концепт. Это человеческая приёмка Google-входа и второго шага, отдельно от автоматических fixtures. Иконку нового уведомления владелец пока видит старой: прежняя регистрационная очистка не доказывает исправление.

Реальный DMG с утверждённым 2x-фоном успешно собран: запись layout на writable image, нативное разрешение background alias, сжатие, hdiutil verify и повторная проверка того же alias на readonly mount прошли. Ресурс непрозрачный, 1280×840 px / 144 DPI; layout не содержит пути checkout. Finder не автоматизировался и реальный UI не выдаётся за screenshot-проверку.

После перезапуска только пользовательского интерфейса NotificationCenter одно новое synthetic уведомление доставлено, но владелец снова подтвердил старую иконку. Перезапуск UI не решил дефект; он не считается исправлением. Workspace, canonical application lookup и running-app icon при этом возвращают новый рисунок для текущего dist bundle. Следующий узкий эксперимент — отдельное имя ресурса для каждого изменения artwork и новый build number, без смены bundle ID или очистки базы уведомлений.

## Build 3 icon-resource experiment — 2026-10-15

Приложение пересобрано как 0.2.0 (build 3) с `CFBundleIconFile=WorkspaceIcon-9970f3eaba3a`. ICNS побайтно совпадает с утверждённым source. `scripts/test.sh` прошёл **999 assertions**; `scripts/test-app-icon.sh` принял точные bytes/name и отклонил валидно переподписанный fixture со старым повторно используемым именем. Это проверка нового packaging-контракта, не доказательство видимой иконки.

Повторная регистрация затронула только g-calendar. Из build 3 доставлено одно уведомление с видимой пометкой сборки: `build=3 icon_resource=WorkspaceIcon-9970f3eaba3a scheduled=1 own_notification_delivered=true`. На тот момент основной пользовательский процесс всё ещё загружал executable из build-2 backup (проверен proc_pidpath), хотя bundleURL сообщал dist. Владелец получил просьбу сохранить изменения, завершить через ⌘Q и открыть новую сборку; до ответа нормальный процесс автоматически не завершается. После этого нужна одна свежая визуальная проверка.

## Native ICNS corruption reproduced — 2026-10-15

Дополнительное нативное декодирование выявило повреждённые малые representations исходного ICNS: проверка `scripts/test-icon-representations.sh` воспроизвела `FAIL Corrupt icon representation icon_16x16.png: mean channel error 110.787109375`. Проверка только большой PNG и совпадения source/bundle пропускала этот дефект. Утверждённый рисунок 1024×1024 сохранён как raster master, штатные sips/iconutil пересобрали все размеры. Та же проверка прошла для десяти representations; ошибка малых 16/32px стала 2.23/1.13, остальные 0.00. Это подтверждает исправление кодирования ресурса; видимый notification icon требует отдельной человеческой приёмки.

Build 4 использует `WorkspaceIcon-50255c65ec18`. Проверены native roundtrip всех десяти bundled representations, bytes/name и отказ переподписанному fixture со старым именем; OpenSpec strict и bash syntax проходят. Приложение открыто по точному dist-пути (один основной процесс); diagnostic delivery подтверждена из build 4. Владелец всё ещё видит старую иконку, поэтому исправление ICNS не объявлено решением видимого дефекта. Следующий единичный эксперимент — перезапуск только пользовательского usernoted с сохранением базы. Новый локальный DMG/ZIP build 4 прошёл native background alias на RW/readonly mounts, hdiutil checksum и EdDSA-подписи appcast/ZIP. Релиз не публиковался.

После перезапуска usernoted доставка второго synthetic запроса build 4 подтверждена; внешний вид отдельно ожидает ответа владельца. `scripts/test-updates.sh` на новых build-4 artifacts прошёл: подлинный архив принят, изменённый отклонён, Sparkle runtime и signed-feed updater стартуют в изолированном ad-hoc fixture, опасные symlinks/записи под aliases отклонены. Это не live обновление с GitHub.
