# Проверки g-calendar

Обновлено: **2026-10-07**. Локальная разработка и приёмка утверждённого UI завершены. Внешние условия публичного выпуска перечислены отдельно; этот документ не подтверждает подписанный релиз или голосовой проход VoiceOver.

## Сборка и автоматические проверки

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

## Scope и сохранность данных

[OpenSpec](../openspec/changes/g-calendar-mvp/tasks.md) фиксирует завершённую локальную реализацию/приёмку; [ExecPlan](plans/2026-10-05-final-product-completion.md) содержит итог и причины решений. Внешние release/VoiceOver/banner условия сохранены в [PENDING_DECISIONS](PENDING_DECISIONS.md). checkpoint 62f153f исторический; текущее продолжение без коммитов, push или публикации.

Design содержит два утверждённых PNG и DESIGN/README. Личный пустой download.html не изменён. Private ledgers/profile/raw captures остаются вне repo; baseline содержит только разрешённые синтетические агрегаты. `.hermes`, `.codegraph`, dist, credentials и `.DS_Store` не добавляются в Git. Regex privacy scan и diff check выполняются отдельно; scan не гарантирует отсутствие любого возможного секрета.

Финальный контроль 2026-10-07: strict OpenSpec `valid=true`, `issues=[]`, exit 0; `git diff --check` exit 0. SHA256SUMS для финальных ZIP/DMG/manifest: все OK. Ни один Swift source не новее финального executable. Privacy scan 92 текстовых файлов: credential-pattern flagged paths=[], личный download.html остаётся 0 bytes. Existing ignored design/.DS_Store сохранён.
