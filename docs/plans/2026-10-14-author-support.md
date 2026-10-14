# Добавить поддержку автора и переносимый skill

Этот ExecPlan поддерживается по `/Users/alexbeketov/.codex/Plans.md`. Разделы Progress, Surprises & Discoveries, Decision Log и Outcomes & Retrospective обновляются при выполнении.

## Purpose / Big Picture

Пользователь открывает настройки g-calendar, нажимает постоянную кнопку «Поддержать автора» в нижнем левом углу и получает отдельное окно с CloudTips по умолчанию. Segmented Control переключает QR, логотип и ссылку на Boosty. Сканирование камерой, явное открытие браузера и копирование ссылки дают три удобных способа перейти к поддержке. Надписи о необходимости регистрации или её отсутствии исключены по просьбе владельца.

После реализации переносимый skill в Dev Kit позволит агентам добавлять такие же адреса и QR в любые репозитории, включая репозитории документов. Авторский материал будет размещён в custom и установлен в общий `~/.agents/skills` и разрешённые агентские endpoints.

## Progress

- [x] (2026-10-14) Согласованы расположение, макет и удаление подписи «Без регистрации».
- [x] (2026-10-14) Проверены настройки, сборка и схема Dev Kit; создан отдельный worktree Dev Kit от origin/main.
- [ ] Подготовить проверенные QR и официальные марки, реализовать окно и постоянную кнопку.
- [ ] Проверить ресурсы, действия, Light/Dark, OpenSpec и пересобрать приложение; отправить изменения g-calendar в main.
- [ ] Создать custom skill, обновить реестр и спецификацию Dev Kit, проверить полный пакет.
- [ ] Выполнить точный dry-run и установку skill в разрешённые endpoints; отправить отдельный коммит Dev Kit в main.

## Surprises & Discoveries

Настройки — sheet с прокручиваемым содержимым и постоянным footer. Сборка копирует только AppIcon и Info.plist; новые PNG нужно явно упаковать в `Contents/Resources/AuthorSupport`. В Dev Kit есть незакоммиченные изменения и локальный коммит другой работы; isolated worktree `/private/tmp/dev-kit-support-author-20261014` создан от удалённого main, чтобы не включать их в публикацию.

## Decision Log

2026-10-14, владелец: утвердить footer entry и отдельное окно по макету; исключить подписи о регистрации для всех провайдеров. CloudTips основной, Boosty дополнительный. Computer use не использовать. Авторизация коммита, push main и пересборки дана явно; Dev Kit публикуется отдельным коммитом без чужих изменений.

## Outcomes & Retrospective

Реализация и проверки ещё не завершены.

## Context and Orientation

`Sources/GCalendar/SettingsAndForms.swift` содержит SettingsView: новое действие добавляется в нижний HStack, вне ScrollView. `AppTheme.swift` и `ThemePalette.swift` определяют цвета и интервалы. Все Swift-файлы Sources/GCalendar включаются `scripts/build-app.sh`; бинарь собирается swiftc для arm64/macOS 13. Новые ресурсы хранятся в `Resources/AuthorSupport`. `docs/FUTURE.md`, `docs/roadmap.md` и `docs/PENDING_DECISIONS.md` пока описывают поддержку как будущую. OpenSpec находится в `openspec/changes/g-calendar-mvp`.

Ссылки — https://pay.cloudtips.ru/p/bf792932 и https://boosty.to/gcalendar/donate. Исходные QR предоставлены владельцем во временных файлах `codex-clipboard-d933df76-3647-4979-b4a9-46e743ea86c2.png` и `codex-clipboard-7a03aa76-29be-4272-8846-3866727163f3.png`. После копирования временные пути не входят в runtime или skill.

## Plan of Work

Milestone 1 создаёт `AuthorSupport.swift` с ordered provider model, фиксированными HTTPS-адресами, относительными именами ресурсов и проверяемыми обработчиками явных действий. `AuthorSupportView.swift` отображает согласованное окно и использует native segmented Picker, dismiss и AppTheme. SettingsView хранит локальный флаг sheet. В ресурсы копируются QR и логотипы с указанием официальных источников. `build-app.sh` упаковывает весь небольшой каталог до подписи bundle.

Milestone 2 создаёт focused test script для нового модуля и изображения. Vision декодирует оба QR в точный адрес, подставные обработчики проверяют выбранный URL и clipboard success/failure, offscreen SwiftUI snapshot проверяет достижимый layout обоих providers в Light/Dark. Обновляются OpenSpec, текущие docs и результаты verification. Выполняются focused test, invariant suite и optimized build. После проверки staged diff создаётся один product commit, обновляются локальные индексы и выполняется push main.

Milestone 3 в isolated Dev Kit worktree создаёт `skills/custom/author-support/SKILL.md` с переносимыми относительными assets: оба QR и проверяемый список ссылок. Никаких зависимостей от Codex, computer use, локальных скриншотов или платёжных credentials. Skill выбирает формат репозитория, показывает CloudTips первым и Boosty вторым, даёт текстовые ссылки рядом с QR, не добавляет paywall или подписи о регистрации. Логотипы из runtime приложения не требуются для skill: переносимое README может показывать название и QR. Обновляется спецификация `docs/structure.md` и основной реестр с SHA-256 каждого файла, ownership user-authored и явными targets. Shared agents endpoint применяется для Codex/OpenCode, а полноценные Hermes/Pi endpoints сверяются с действующей схемой и видимостью общей skills-папки. Existing divergent copies не заменяются.

## Concrete Steps

В `/Users/alexbeketov/g-calendar` запускать `rtk proxy ./scripts/test-author-support.sh`, `rtk proxy ./scripts/test.sh`, `rtk proxy openspec validate g-calendar-mvp --strict --json` и `rtk proxy ./scripts/build-app.sh`. Ожидаются успешные проверки, valid=true и `APP_BUNDLE=/Users/alexbeketov/g-calendar/dist/g-calendar.app`. Изолированное offscreen изображение не является проверкой real UI или оплаты.

В `/private/tmp/dev-kit-support-author-20261014` использовать `/Users/alexbeketov/.hermes/hermes-agent/venv/bin/python` для `scripts/validate_dev_kit.py`, `-m unittest discover -s scripts/tests -v` и `scripts/sync_skills.py --skill author-support`. Только после успешного dry-run выполнить точный `--apply`, проверить полный пакет по хешам и опубликовать staged explicit paths коммит через `git push origin HEAD:main`. Перед push заново fetch; при конкурирующей публикации переиграть только свой коммит поверх актуального origin/main и повторить относящиеся проверки.

## Validation and Acceptance

Оба QR должны декодироваться в фиксированные HTTPS URL. Default selection — CloudTips; Boosty — вторым. Открытие браузера и clipboard тестируются подставными closure без реальных переводов и открытия браузера. Ресурсы должны присутствовать и в исходниках, и в финальном bundle. Окно в Light/Dark не содержит подписи «Без регистрации» и объяснения причин приоритета. Кнопка поддержки находится вне прокрутки; интерфейс сохраняет стандартный Escape, VoiceOver labels и pointing-hand cursor. Skill успешно проходит валидатор Dev Kit, содержит полные QR-assets в общем endpoint и не создаёт Codex-only copy.

## Idempotence and Recovery

Не менять чужое состояние Dev Kit; isolated worktree сохраняется как источник опубликованного результата. Registry sync создаёт только отсутствующие endpoints после dry-run. Existing conflicts сообщаются и не перезаписываются. App build использует собственную staging/rollback процедуру. Не выполнять live donation, не публиковать релиз и не менять платежные аккаунты.

## Artifacts and Notes

Утверждённый макет представлен в беседе 2026-10-14. QR и логотипы не брать из сгенерированного макета: использовать реальные ресурсы и декодирование. Итоговые проверки и commits записать здесь перед завершением.

## Interfaces and Dependencies

Используются SwiftUI, AppKit и Vision в focused tests, без внешних runtime зависимостей. `AuthorSupportProvider` содержит cloudTips и boosty, title, URL и resource names. `AuthorSupportActions` принимает closures открытия URL и записи clipboard; production использует NSWorkspace и NSPasteboard, тесты — изолированные подставные функции. Новый view загружает local assets из Bundle и не читает никакие пользовательские Google данные. Skill — обычный Markdown с PNG и public URL; его instructions не зависят от модели или конкретного приложения агента.

2026-10-14: начальная версия отражает утверждённый дизайн и отдельную публикацию Dev Kit для защиты параллельной работы.
