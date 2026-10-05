# Проверка g-calendar

Обновлено: 2026-10-05, Europe/Moscow. Реализация продолжается; полная внешняя приёмка ещё не завершена.

## Код и сборка

`rtk ./scripts/test.sh`: exit 0, 254 assertions. Последний current-source оптимизированный запуск `rtk proxy env G_CALENDAR_TEST_OPTIMIZE=1 ./scripts/test.sh`: exit 0, 268 assertions; включает explicit-ledger guards, selection reconciliation после remote удаления списка и overdue status predicates. Первоначальный повторный запуск не компилировался из-за отсутствия LedgerAcceptance.swift в test source list; файл добавлен, suite прошёл.

Проверены pagination, сохранение кэша при ошибке страницы, date-only/DST/all-day, overlap, независимые refresh domains, latest-wins, mutation guards, точный read-back, reminders и изоляция demo. Регрессии покрывают пустые/отсутствующие notes, настоящий field/identity mismatch, неизвестный create ID, failed GET, persisted journal, запрет повторного INSERT и read-only recheck. Время событий приводится к секундам до отправки и journaling; несовпадение на целую секунду отвергается.

Deletion tombstone принимается только после совпадения точного ID. Отсутствие ресурса подтверждается структурированным HTTP 404/410 или явным HTTP статусом; случайное «404» внутри идентификатора не является доказательством удаления. При nonzero exit DELETE возможен только один точный GET; повторной записи нет. Cleanup fixture запрещает identity вне ledger и повтор уже отправленного DELETE.

Последняя завершённая `rtk ./scripts/build-app.sh`: exit 0; включает notification-test, FocusState и общие spacing constants. arm64, macOS 13+, оптимизация `-O`, Info.plist valid, локальная ad-hoc подпись проверена. Последние правки explicit ledger path, settings spacing, list selection reconciliation и overdue/metadata accessibility сделаны после сборки. Повторную сборку отклонил automatic approval review из-за общего правила AGENTS.md о сборках владельцем; запрошено точное разрешение. Direct-swiftc scripts используют process-local toolchain overlay без изменения системного SDK.

## Реальная интеграция Google

Разрешены только собственные синтетические задачи, списки и события с уникальной меткой и приватными точными ID. Перед edit/complete/reopen/delete выполняется GET, после записи — точная проверка. Личные объекты не изменяются; ledger и черновики находятся вне репозитория.

Первый запуск обнаружил округление времени Google Calendar до секунд: timestamp отличался на 332 мс. Созданное событие удалено после exact GET и проверки своего маркера; post-GET подтвердил cancelled. Этот запуск не объявлен успешным.

Два последующих native-app запуска завершили каждый 11 проверенных шагов: event/list/task create, edit, complete/reopen и удаление всех трёх объектов. Они включали остановку после неподтверждённого DELETE и явное продолжение cleanup: сначала read-only recheck уже отправленного DELETE, затем удаление оставшихся собственных ресурсов. В обоих ledger complete=true, deleted=3, pending отсутствует. Это успешная проверка lifecycle и восстановления, а не утверждение о непрерывном прохождении без ошибок.

Последний свежий запуск завершился timeout до первой записи: verified_steps=0, created=0, pending отсутствует. Очистка для него не нужна. При неподтверждённом INSERT повторная запись запрещена.

Измеренные отдельные оставшиеся cleanup операции заняли 1582.9 и 1326.2 мс (mutation + exact GET). Эти значения не являются p50 всего lifecycle или UI latency.

## Интерфейс и отступы

Утверждён [Pixel Paper](../design/DESIGN.md) с компактными task rows Color Atlas. Отвергнутые варианты удалены, сохранены два выбранных референса.

Code audit охватил task/event/list editors, list manager, reminder, settings и recovery sheet: общий outer inset 24 pt, EditorField gap 8 pt, основные секции 16 pt; content-fit editors и ограниченная прокрутка тела с footer снаружи. Во время pending/in-flight Google write поля заблокированы; title использует native FocusState/defaultFocus. Внешняя проверка каждого окна и крайних размеров требуется отдельно.

После явного разрешения владельца старая обычная копия закрыта через Cmd+Q. Привязка по пути к одному изолированному demo восстановилась: native clicks и synthetic task workflows прошли. Calendar screenshot показывает начальное положение около 08:00, но подпись 08:00 обрезана верхней границей; это открытый дефект, требующий исправления и повторного снимка. Settings вызывает падение SkyComputerUseService (EXC_BREAKPOINT/SIGTRAP, Array.remove(at:)); g-calendar остаётся живым. Свежий собственный demo перезапущен без личных данных. Primary reports аналогичного helper stack: https://github.com/openai/codex/issues/43573 и https://github.com/openai/codex/issues/34432. Совпадение стека не доказывает точную внутреннюю причину. Рассмотрены новая привязка, один demo process, REPL reset, restart target и helper update владельцем; изменение TCC/helper binary и raw input обход не применяются.

Task-list sidebar icon/text/blank/edge clicks и create/edit-cancel/complete/reopen подтверждены в предыдущей demo-сборке. Task/reminder screenshots показывают симметричные outer insets 24 pt и reachable footer. Calendar selection/visibility, workspace filters, Light/Dark/System и полная focus/resize/state matrix остаются открытыми. Полный ручной VoiceOver проход отдельно не проведён.

## Производительность

Машина: Apple M4 Pro, Mac16,8, RAM 24 GiB. Оптимизированный pure-model benchmark (`-O`), фиксированный synthetic набор, 9 samples: search/filter 4096 tasks p50 1.587 мс, p95 1.817 мс; grouping 4096 tasks p50 5.079 мс, p95 6.248 мс. Overlap 1024 events — 1.30 мс за один проход. Это вычисления модели; результаты разных запусков меняются и не задают GUI budget.

Один idle snapshot собственного оптимизированного demo process: CPU 0.0%, RSS 135.3 MiB. Это не peak load или frame profile. GUI launch/search/selection/week/resize/scroll/forms и frame hitches ещё не измерены. Instruments/xctrace отсутствует в текущем CLT. CLI startup, Google/API latency и exact GET нужно учитывать отдельно от UI.

## Системные уведомления

Actual bundle `com.alexbeketov.gcalendar`: authorization=authorized, alert_setting=enabled, sound_setting=enabled, foreground_delegate_ready=true. Read-only status checkpoint: pending_count=0, delivered_count=0.

Один явный запуск `--notification-test` завершился exit 0: scheduled=1, own_notification_delivered=true. Приложение запланировало ровно одно уведомление с уникальным synthetic ID; macOS подтвердила его присутствие в Центре уведомлений. Это не доказательство видимого баннера: ответ владельца запрошен отдельно. Разрешение не запрашивалось повторно, сторонние уведомления не удалялись.

## Открытая приёмка

Продолжить [единый план](plans/2026-10-05-final-product-completion.md) и [OpenSpec](../openspec/changes/g-calendar-mvp/tasks.md). Остались текущая сборка после explicit-ledger правки, code + visual spacing pass, state/keyboard/appearance/resize matrix, GUI baseline, ответ о видимом notification banner . OS prompts подтверждает человек; TCC не сбрасывается. Лицензия/публичный релиз не входят в этот этап. Коммитов и публикации нет.

## Privacy review

Проверены 70 текстовых tracked/untracked файлов: private keys, token literals, Google API keys и OAuth client IDs не обнаружены. Единственный адрес в tests использует example.invalid; пять остальных regex совпадений — icon filenames @2x.png. Приватные live ledgers остаются вне repo. design содержит только два approved PNG и DESIGN/README; существующий .DS_Store сохранён и ignored. Пустой пользовательский download.html не изменялся. Staged content отсутствует; коммитов/публикации нет. Regex scan дополняет code review и не заявляется универсальным secrets detector.

## Текущий checkpoint перед коммитом

Владелец разрешил коммит и пуш текущего состояния, затем продолжение цели. Последний optimized suite прошёл 268 assertions, exit 0. Предшествующий запуск имел один timeout synthetic GUI-path launcher с лимитом 2 секунды; повтор без правок прошёл. Это известная нестабильность тестового окружения, а не доказанный дефект adapter. Текущие UI guard changes ещё не включены в полный bundle; все GUI результаты выше относятся к предыдущей сборке. Ничто в этом checkpoint не закрывает оставшиеся acceptance tasks.

Read-only ревью выявило P2 в MutationJournal.begin/clear: два независимых normal instances могут использовать устаревшее in-memory состояние общего journal. NSLock защищает один экземпляр, но не разные процессы. Задача 7.2 вновь открыта; требуется межпроцессная сериализация с повторным чтением и fixture на два journal instances с одним файлом. До исправления live writes не возобновляются.

Контроль блокировки 2026-10-05: повторное getApp по точному пути actual bundle снова завершилось «Sky Computer Use native pipe closed before response». Эта внешняя блокировка сохраняется три последовательных goal turns; оставшаяся приёмка требует восстановления native helper. Разрешение на current-source build после отказа automatic approval review также ещё не получено. Independent code/fixture работа выполнена; 17 задач остаются открытыми по конкретным build/UI/acceptance gates. Цель отмечается blocked, не complete. Для продолжения нужны разрешение на scripts/build-app.sh и восстановленный Computer Use; перезапуск Codex выполняет владелец.

Повторная проверка 2026-10-05 после сообщения владельца «дал доступ»: REPL reset + getState прошли; getApp(System Settings), click «Конфиденциальность и безопасность» и click «Запись экрана и системного звука» прошли с подтверждённой AX сменой страницы. Codex Computer Use.app screen recording toggle=on. Native clicks работают для macOS Settings. getApp(dist/g-calendar.app) всё ещё падает; bundle-ID lookup сообщает множество зарегистрированных старых копий. Name lookup запустил старую обычную сборку, с ней Google mutations/снимки не выполнялись. Cmd-Q этой копии отклонил automatic approval review из-за риска несохранённого состояния и недоказанного ownership; запрос закрытия отправлен владельцу, обхода отказа нет. Нельзя считать общую блокировку native clicks актуальной, но current demo binding/внешняя приёмка ещё не подтверждены. Разрешение на current-source build остаётся отдельным pending запросом.
