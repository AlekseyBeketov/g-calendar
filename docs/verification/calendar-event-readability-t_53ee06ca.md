# Calendar timed-title readability — t_53ee06ca

Дата: 2026-10-08. Worktree `t_53ee06ca`, ветка `g-calendar/t_53ee06ca-g-calendar-execplan`, baseline `c0a0f5212d5e1a81b00d139f0bea58f1d2a70b33`. Только синтетические данные, offscreen production views. Codex implementation lane не использовал commit/stage/Kanban/Hermes CLI; последующие stage/commit/integration и Kanban принадлежат Hermes. Live/demo bundle, Google и desktop input не использовались ни одним lane. Исходный ExecPlan, OpenSpec и общая verification history не менялись.

## Изменение

`CalendarTimedCardLayout` задаёт высоту, резерв полос, complete-line budgets и единый нижний запас. Минимум 24 pt, масштаб 0.8 pt/мин; реальные start/end/duration не изменяются. Native callout medium разрешается через NSFont, его реальные line metrics передаются общей политике. SwiftUI semantic sizeCategory увеличивает шрифт и бюджеты вместе; настройки пользователя тесты не меняют.

`CalendarTimedEventCard` сохраняет native Button/onEdit/composite identity. Заголовок сначала: одна строка по центру, затем до двух строк, затем время. Tail ellipsis, без уменьшения шрифта и clipShape текста. Один tint 0.16 поверх surface, одна полоса 3 pt; декорации не принимают hit testing. Lock скрывается в узких полосах; ограничения записи не зависят от иконки. Full title/time/calendar/read-only/recurring находятся в help и AX; AX value содержит фактическую видимую длительность и полосу.

Нижний запас `max(22, minimumHeight)` заменяет сумму прежних grid 8 pt + workspace 14 pt; grid, axis и document используют один бюджет. Начало последнего события не сдвигается, новые часовые метки не добавляются. All-day/date-only Tasks и Calendar search не изменены.

Дополнительные необходимые файлы: неизменённый `Color(hex:)` перенесён из `AppViews.swift` в `AppTheme.swift`, чтобы production grid компилировался существующим ограниченным native test target. В `scripts/test-native-ui.sh` добавлены production grid и focused test file; entry point подключён в `NativeUIInvariantTests.swift`. Пакеты/зависимости не добавлялись.

## Артефакты

Все пути ниже относительно worktree, игнорируемые Git:

- `.hermes/task-t_53ee06ca/baseline/`: сохранённые production sources из `git show`, frozen synthetic harness, `render.sh`, 27 исходных PNG, `metrics.json`, `run.log`. Baseline не перезаписывается after-прогонами.
- `.hermes/task-t_53ee06ca/after/`: duration/overlap/end-day production grids для 160/80/700 pt и Light/Dark/System; отдельные карточки для 24/39/40/55/56/96 pt и увеличенного шрифта; contact sheets, цветовая матрица, `metrics.json`.
- `.hermes/task-t_53ee06ca/comparison-light.png` и `comparison-dark.png`: подписанные baseline/after crops short/overlap/23:55, увеличение 2× без интерполяции. `MakeComparison.swift` и `make-comparison` сохраняют способ получения.
- `.hermes/task-t_53ee06ca/toolbar/`: текущие синтетические toolbar PNG и bounds существующей проверки.
- `.hermes/task-t_53ee06ca/{invariants,native,focused-native,typecheck,build}.log`: текущие прогоны. Отдельные compiler/tool outputs канонических скриптов остаются в их обычных ignored `.build/` и `dist/`.

Baseline vertical budget: NSFont caption title 13 pt line + subtitle 13 pt line + spacing 2 + padding 4 = **32 pt**, available **18 pt**, deficit **14 pt**. Production PNG/crops показывают верхнее/нижнее обрезание, проступающий subtitle и две полоски. Это доказательство содержимого и пикселей, не только `frame == 18`.

After measured budgets и финальные exits приведены ниже; исторические результаты не используются.

## Проверки и ограничения

- [x] 10.1 Сохранён baseline из production view; demo fixtures расширены без удаления прежних. 1/5/10/15/30/60/120 мин, 10:00/10:10, 23:55, длинные нейтральные русские заголовки, read-only/recurring.
- [x] 10.2 Общая политика geometry/lane reservation; custom minima, exact-boundary reuse, permutations, composite identities, near-boundary 25 мин, midnight, существующие DST и 1024 stress fixtures.
- [x] 10.3 Отдельная production timed card, title-first, actual line metrics, narrow lanes, одно оформление.
- [ ] 10.4 Native activation/focus evidence и ограничения — финальный результат ниже. Spoken VoiceOver, живое открытие полной формы человеком не проверены.
- [x] 10.5 Текущий native suite/contrast/pixel evidence — результаты ниже. System проверяется как текущий resolved appearance; переход системной темы и human acceptance не заявляются.
- [x] 10.6 `docs/ui.md` обновлён узко; создан этот отдельный документ. Canonical build попытка завершилась ошибкой iconutil. Независимые build/review/commits/integration принадлежат Hermes.

Compiler troubleshooting: явный test target первоначально не включал `Color(hex:)`. Рассмотрены четыре подхода: подключить весь AppViews и его зависимости; дублировать helper в fixture; вынести новый shared-файл; перенести неизменённый helper в уже подключённый AppTheme. Выбран последний, с минимальным расширением target. [Swift initialization](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/initialization/) и [access control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/) подтверждают доступность extension в модуле при включении его исходника. TinyFish здесь не запускался: его script читает credential env-file, что запрещено owner contract; использован read-only web fallback без секретов.

Offscreen AX troubleshooting: после двух неудач получение дерева остановлено для проверки [NSHostingView accessibilityChildren](https://developer.apple.com/documentation/swiftui/nshostingview/accessibilitychildren%28%29) и [unignored children](https://developer.apple.com/documentation/AppKit/NSAccessibility-c.protocol/accessibilityChildren). Рассмотрены native children, navigation-order/unignored traversal, принудительное offscreen display/cache, hit-test на isolated host. Показ key/front окна и включение accessibility preferences исключены owner contract. Полный spoken VoiceOver не заменяется тестом AX label или press.

## Измеренные результаты

NSFont на этой macOS разрешил callout medium в **12 pt**, `.AppleSystemUIFontMedium`: ascent 11.6015625, descent 2.53125, leading 0, округлённый полный line budget **15 pt**. CoreText glyph bounds для `Короткая встреча Йруф`: height **13.4296875 pt**. Time line budget **12 pt**. Минимум/пороги остаются **24/40/56 pt**. Это разрешённый semantic callout этой ОС, а не принудительное уменьшение до 12 pt.

Инъекция `.accessibilityExtraExtraExtraLarge` разрешает title **26.4 pt**, полный line budget **32 pt**, glyph height **28.449609375 pt**, time line **26 pt**. Общие minimum/two-line/time thresholds: **38/70/98 pt**. В production native day/axis document конец 23:55-карточки находится на **1172/1186 pt**, высота документа **1176/1190 pt** соответственно; ось и дни после scroll к нижней границе имеют одинаковые offsets **976/990 pt**. Часовые метки не расширяются.

**108** отдельных production-card pixel cases: 3 ширины × 3 темы × 6 высот × 2 font categories. Скан исключает полосу и обнаруживает реальный текстовый ink, с минимальными свободными границами **5 px сверху / 4 px снизу** (1× raster в этой среде). CoreText/NSFont, required complete-line budget и actual offscreen pixels проверяются вместе. Пиксельный scan подтверждает вертикальный запас; наличие корректного многоточия дополнительно оценено на contact sheets, не выводится из одного frame assertion.

**18** цветов, Light/Dark: минимальный точный contrast **8.98925723757177:1**, white tint в Dark; сравнение `>= 4.5` выполняется без округления. Один слой tint над surface. Native color contact sheets используют те же production cards. PNGs: **27 baseline**, **158 after**, плюс comparison sheets. Машинные данные: `.hermes/task-t_53ee06ca/summary.json`, `after/metrics.json`, сохранённые baseline hashes `baseline/SHA256SUMS`.

Focused native runner: **exit 0, 641 assertions**; явно сообщает `UNVERIFIED timed-card AX press: offscreen SwiftUI children unavailable`. Изолированный hosting responder принимает native focus (`true`), прямой Space в него **не открыл** кнопку (`spaceOpened=false`). Это не успешная проверка keyboard activation. Full native Button AX label/press, click, keyboard opening и фактическое появление detail form остаются непроверенными: ни AX children, ни key/front window в разрешённой offscreen конфигурации нет. Проверка help/detailText обеспечивает полное исходное название, реальные времена, календарь и статусы; wiring `onEdit` и restriction rules сохранены в production и проходят source typecheck/существующие mutation invariants. Accessibility prefs и permissions не изменялись.

### Команды

Shell bodies выполнялись через `rtk proxy`; redirects сохраняют указанные логи. `TMPDIR=/Users/alexbeketov/.hermes/profiles/coder/cache/scratch` задавался для compiler/test процессов.

```sh
bash .hermes/task-t_53ee06ca/baseline/render.sh
# exit 0; PASS calendar-timed-card-native: 28 assertions
./scripts/test.sh
# exit 0; ASSERTIONS=496
bash .hermes/task-t_53ee06ca/focused-native.sh
# exit 0; PASS calendar-timed-card-native: 641 assertions
mkdir -p dist
./scripts/build-app.sh
# exit 1; icon generation stopped at iconutil, before app source compilation
source scripts/swift-toolchain.sh
configure_swift_compiler .hermes/task-t_53ee06ca/typecheck
"${G_CALENDAR_SWIFT[@]}" -typecheck -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications Sources/GCalendar/*.swift
# exit 0; typecheck.log empty (all production sources, no bundle launch)
.hermes/task-t_53ee06ca/make-comparison .hermes/task-t_53ee06ca
# exit 0; comparison-light.png / comparison-dark.png
git diff --check
# exit 0
```

Точная ошибка canonical build (sandbox не обходился):

```text
/Users/alexbeketov/g-calendar/.worktrees/t_53ee06ca/.build/g-calendar/run-55311/AppIcon.iconset:Invalid Iconset.
/Users/alexbeketov/g-calendar/.worktrees/t_53ee06ca/.build/g-calendar/run-55311/AppIcon.iconset:Invalid Iconset.
```

Canonical native suite и окончательная проверка diff implementation lane записаны далее. Результаты независимой Hermes verification находятся в отдельном разделе ниже; human acceptance не заявляется.


## Финальный canonical native suite

```sh
TMPDIR=/Users/alexbeketov/.hermes/profiles/coder/cache/scratch \
G_CALENDAR_CARD_EVIDENCE_DIR="$PWD/.hermes/task-t_53ee06ca/after" \
G_CALENDAR_NATIVE_EVIDENCE_DIR="$PWD/.hermes/task-t_53ee06ca/toolbar" \
./scripts/test-native-ui.sh
# exit 0; NATIVE_UI_ASSERTIONS=898
# production-toolbar-offscreen=237, calendar-timed-card-native=641,
# existing native scroll/scoped-keyboard=20
```

Текущие существующие scroll/toolbar tests прошли; toolbar/search production code не менялся. Log содержит sandbox XPC `Connection invalid` diagnostics, но suite завершился exit 0. AX/Space ограничения выше остаются непроверенной частью 10.4, несмотря на успешный suite exit. Final `git diff --check`: exit 0. Stage/commit отсутствуют.

## Изменённые файлы

- `Sources/GCalendar/CalendarLayout.swift`: pure minimum/content/bottom policy и согласованный резерв полос.
- `Sources/GCalendar/CalendarTimeGrid.swift`: resolved semantic font metrics, отдельная timed card, runtime minimum и shared bottom padding.
- `Sources/GCalendar/CalendarWorkspaceView.swift`: тот же runtime minimum в axis/document, замена старого bottom padding.
- `Sources/GCalendar/RuntimeModes.swift`: дополнительные synthetic demo events; прежние fixtures сохранены.
- `Sources/GCalendar/AppTheme.swift`, `Sources/GCalendar/AppViews.swift`: только перенос существующего `Color(hex:)` для явного test compilation target.
- `Tests/InvariantTests.swift`: геометрия/minima/permutation/stress и фактический single-layer contrast.
- `Tests/CalendarTimedCardNativeTests.swift`: production offscreen renders, CoreText/NSFont/pixels/contrast/native documents, честно маркированные activation probes.
- `Tests/NativeUIInvariantTests.swift`, `scripts/test-native-ui.sh`: подключение focused suite/production grid.
- `docs/ui.md`, `docs/verification/calendar-event-readability-t_53ee06ca.md`: узкий UI контракт и task-specific evidence.

На момент завершения implementation lane оставались: canonical bundle build из-за sandbox iconutil, реальная Button AX/click/keyboard activation и появление полной detail form, spoken VoiceOver, System theme transition, human acceptance и независимые Hermes review/integration. Это исторический результат Codex, не итог независимой проверки. Поведение native Button/onEdit и restrictions не заменялось ради тестового окружения.

## Независимая проверка Hermes — 2026-10-08

Hermes перечитал полный production/test diff и выполнил canonical wrappers самостоятельно, после завершения единственного Codex lane:

- `./scripts/test.sh`: exit 0, `ASSERTIONS=496`; `.hermes/task-t_53ee06ca/hermes-invariants.log`.
- `./scripts/test-native-ui.sh`: exit 0, `NATIVE_UI_ASSERTIONS=898`; `.hermes/task-t_53ee06ca/hermes-native.log`. Отдельные totals: 237 toolbar, 641 timed-card, 20 существующих native scroll/keyboard assertions.
- `./scripts/build-app.sh`: exit 0; `.hermes/task-t_53ee06ca/hermes-build.log`. Canonical build прошёл без изменения pipeline; sandbox `Invalid Iconset` у Codex не воспроизвёлся. Ignored `dist/` создан перед build.
- `codesign --verify --strict dist/g-calendar.app` и `plutil -lint dist/g-calendar.app/Contents/Info.plist`: exit 0. Bundle не устанавливался и не запускался.
- `git diff --check`: exit 0.
- `OPENSPEC_TELEMETRY=0 openspec validate g-calendar-mvp --strict` из основного checkout: exit 0. Никакие source OpenSpec/planning files не записывались и checklist автоматически не закрывался.
- Все пять immutable input source SHA256/mtime и snapshot SHA256 повторно совпали с manifest. Baseline `CalendarLayout.swift`, `CalendarTimeGrid.swift`, `AppTheme.swift` побайтово совпадают с commit `c0a0f5212d5e1a81b00d139f0bea58f1d2a70b33`.
- Hermes самостоятельно пересобрал и выполнил `.hermes/task-t_53ee06ca/baseline/render.sh`: exit 0, 28 baseline assertions; `.hermes/task-t_53ee06ca/hermes-baseline.log`. Baseline сохраняет обнаруженный дефицит 14 pt: контент 32 pt в карточке 18 pt.

Независимые after artifacts: `.hermes/task-t_53ee06ca/hermes-after/` (158 PNG и `metrics.json`); toolbar artifacts: `.hermes/task-t_53ee06ca/hermes-toolbar/`. Все 27 Calendar toolbar PNG побайтово совпали с независимыми parent artifacts `t_05589f87`: поиск/toolbar не изменились.

Hermes визуально изучил статические contact sheets для всех 3 ширин × 3 тем × 2 font categories, production grid sheets для duration/overlap/end-of-day во всех темах и Light/Dark color matrices. Целые title/time строки, горизонтальный tail ellipsis и отдельные полосы коротких событий подтверждены этим offscreen review, не live acceptance. Review sheets: `.hermes/task-t_53ee06ca/hermes-review-{light,dark,system}-{large,accessibilityExtraExtraExtraLarge}.png` и `hermes-grid-review-{light,dark,system}.png`.

Повторно полученные native metrics: 108 card pixel cases, минимальный верхний/нижний glyph clearance 5/4 px; 36 composed color cases, минимальный contrast 8.989:1. Для обычного шрифта minimum/two-line/time = 24/40/56 pt; для enlarged font = 38/70/98 pt. Native document extent и bottom-scroll проверены для 24-часового дня и обеих font categories; 23/25-часовые DST дни проверены существующими pure layout/axis invariants, не native document render. Это не утверждение о полном системном Dynamic Type или доступности на macOS 13: build target 13, выполнение на текущем macOS host.

Review не обнаружил блокирующего дефекта в проверенном scope. Прежние production `Button`/`onEdit`, edit-permission checks, all-day/date-only Tasks и Google mutation paths сохранены; `Color(hex:)` только перенесён без семантического изменения для явного test compilation target.

Остались явно непроверенными: live glass/compositing и пользовательская visual acceptance; native mouse/keyboard/AX activation с открытием полной detail form; spoken VoiceOver; OS System-appearance transitions; полный системный font-growth workflow и запуск на macOS 13. Offscreen AX children не опубликованы, direct synthetic Space не активировал Button: эти probes честно остаются `UNVERIFIED`, а не PASS. GUI/CUA/desktop input, live Google, secrets, установка/запуск bundle и push не использовались.

Scoped commit и serialized integration evidence сохраняются отдельно в Kanban handoff и `.hermes/task-t_53ee06ca/integration-result.json`; immutable ExecPlan и чужой root WIP не входят в feature commit.
