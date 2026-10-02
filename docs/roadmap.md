# Roadmap

## MVP — Local native client
- Native macOS SwiftUI application with consistent Material-inspired visual direction.
- Week/day calendar and task-focused list/columns; date selectors, Today/Overdue/Search.
- Real read-only Google sync through configured `gws`, explicit cache freshness/error states.
- Calendar and task CRUD controls, including complete/uncomplete, validated with local fixtures. The owner separately authorized a narrowly scoped synthetic live write/read-back smoke through the actual app workflow; production/personal mutations and test-object deletion remain prohibited unless separately approved.
- Local-only task reminder time and UserNotifications permission/schedule/cancel/reschedule flow.
- Reproducible source build and bundle script, tests, read-only smoke report, privacy-safe screenshots/verification.

## Near-term after MVP
- Month view and stronger recurrence handling after timezone/DST and event-scope tests.
- Additional keyboard shortcuts and accessibility QA with VoiceOver, contrast/dynamic type review.
- Improve adapter version discovery/compatibility matrix and user-facing `gws` setup diagnostics.
- Optional manual calendar refresh controls and quota-conscious sync intervals.

## Later / separately approved
- All-day/recurring Calendar event reminders and Google popup/email preference mirroring remain later scope; current event reminders are explicit local-only exact-time settings for supported timed occurrences.
- Direct official Google API integration only if gws distribution, scopes, versioning, or UX becomes a material blocker; assess OAuth verification and secret storage first.
- Other platforms only after a demonstrated product need.
- Publicly signed/notarized release only with explicit release approval and appropriate Apple Developer credentials.

## Not planned
- Hosted backend, push relay, paid synchronization service, telemetry by default.
- Silent Google writes, hidden offline operation queue, or claims of Tasks due-time sync.
- Login item/helper or notifications that bypass user permission.
