## Why

Пользователь хочет native macOS-пространство для Google Calendar и Google Tasks, а не browser wrapper: быстро просматривать неделю, списки задач и синхронизацию в одном доступном интерфейсе. Сейчас подтверждена локальная авторизация `gws`, но отсутствует приложение; Google Tasks API не хранит время due, а SwiftPM в активной CLT среде имеет воспроизводимый manifest-link blocker, который надо честно исследовать.

## What Changes

- Создать SwiftUI/AppKit macOS application bundle с week/day calendar и task-oriented list, selectors, Today/Overdue/Search, Light/Dark/System.
- Подключить Google Calendar/Tasks через текущий `gws` executable как allowlisted subprocess, первоначально только read-only; читать календарные события, task lists и tasks с корректной pagination/error handling и last-known-good local cache.
- Реализовать безопасные event/task CRUD и completion flows с явным пользовательским действием в UI; automated tests используют fake process fixtures. Owner отдельно разрешил узкую synthetic live acceptance с GET/read-back через actual app workflow; production/personal objects не изменять. Read-only calendars остаются неизменяемыми.
- Добавить локальные reminders и native UserNotifications UX для Tasks и opt-in точного local time для одного timed non-recurring Calendar event; ни скрытых Google event copies, ни зеркалирования `event.reminders`.
- Добавить unit/integration fixtures, build/bundle/run scripts, privacy-safe real read-only smoke и `docs/verification.md`; зафиксировать точные limitations, включая SwiftPM environment blocker.

## Capabilities

### New Capabilities
- `macos-app-lifecycle`: Native bundle identity, application lifecycle, build/package/run surface and permission-gated macOS notifications.
- `calendar-workspace`: Week/day views, calendar selectors/read-only affordances, event details and safe event-edit UI.
- `google-workspace-adapter`: Process-isolated gws execution, read/write allowlists, typed error handling, pagination and cache safety.
- `task-management`: Task-list selectors, list/column workflows, date-only Google due, task CRUD/completion and app-local extensions.
- `local-reminders`: Transparent local-only schedule metadata and UserNotifications planning/cancellation/reconciliation.

### Modified Capabilities

None.

## Impact

- New Swift sources, tests, scripts, resources and app bundle in `dist/`; repository-owned docs and repo-local OpenSpec change.
- Current local `gws` configuration is reused by subprocess; no token access/export, OAuth changes, hosted backend, paid key, public release, or Apple signing. Production/personal Google objects are never mutated by agents. The owner has separately authorized a tightly-scoped live smoke using only this run's synthetic event/task objects through the actual app adapter/UI and exact GET/read-back; test-object deletion remains separately approval-gated.
- CLI compatibility and currently broken SwiftPM manifest linking are explicit risks. If SPM cannot be repaired without changing/installing system tools, use a reproducible direct-`swiftc` path only if tests and bundle can be built and truthfully reported; never claim failing SwiftPM passed.
