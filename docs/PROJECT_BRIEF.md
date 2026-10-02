# g-calendar — исходное задание

## Цель пользователя
Нативное macOS open-source приложение в стиле Material Design/Pixel для Google Calendar и Google Tasks. Удобные списки задач и календарь, современный производительный стек, привычные нативные уведомления macOS. Без обязательных платных API keys, подписок и hosted backend. Будущая кроссплатформенность необязательна для MVP.

Пользователь поручил реализацию сейчас, с реальным распределением задач между default (оркестратор), prompter (implementation prompt), coder (реализация), research (факты), frontend-coder (UI при полезности). Строго отдельные этапы и спецификация в этом репозитории.

## Проверенные исходные факты
- Репозиторий существует. README первоначально содержит только название. Есть пользовательские `.codegraph/` и `.DS_Store` — сохранять.
- На машине есть `gws` и `gog`. Для `gws` подтверждены valid OAuth token, refresh token, scopes Calendar/Tasks. Реальные read-only вызовы CalendarList и TaskLists прошли. Primary Calendar имеет owner role. `gog` не имеет зарегистрированных accounts.
- Google Tasks REST API сохраняет только дату due; время читать/писать нельзя. Локальные time/reminder extensions должны быть честно обозначены.
- Swift 6.4, CommandLineTools и macOS 27 arm64 доступны. Полный Xcode не подтверждён.
- OpenSpec 1.4.1 запускается через `node /Users/alexbeketov/.hermes/node/lib/node_modules/@fission-ai/openspec/bin/openspec.js`, обычного openspec в PATH нет.
- Provider отклонил literal `gpt-6-luna-max` HTTP 400. Пользователь ЯВНО согласовал `gpt-6-luna` + reasoning `max` для coder и `gpt-6-luna` + `xhigh` для остальных. Постоянные настройки профилей не менять.

## Источники и референсы
- https://developers.google.com/workspace/tasks/reference/rest/v1/tasks
- https://developers.google.com/workspace/calendar/api/guides/quota
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://etasks.app/?utm_source=chatgpt.com

Исходные скриншоты находятся в attachments пользовательской сессии: task-list columns и weekly calendar. Не распространять персональные названия задач и событий.

## Исходная гипотеза стека
Swift + SwiftUI с точечным AppKit, Foundation, UserNotifications; gws adapter для существующего локального Google доступа. Сборка SPM и proper .app bundle. Это гипотеза до решения default/research, не утверждение о готовом продукте.

## Ограничения безопасности
- Агентам разрешены чтение Google, проектные файлы, локальные build/test/launch. Пользователь отдельно разрешил только минимальные synthetic event/task test objects с уникальным run marker и проверкой GET/read-back через настоящий app adapter; нельзя менять существующие личные объекты, приглашать людей, экспортировать токены, менять credentials, подключать billing, ставить login items, публиковать код/релизы или удалять test objects/пользовательские файлы без отдельного подтверждения. Production writes остаются только по явному действию владельца в UI.

## Рабочее задание
Полный completion contract и правила делегирования: `.hermes/prompts/build-goal.md`.
