# Roadmap

## Current planning checkpoint — 2026-10-05

Owner approved Pixel Paper as the base with compact Color Atlas task-row metadata. The current [design contract](../design/DESIGN.md) and [execution plan](plans/2026-10-05-final-product-completion.md) replace the exploration variants and earlier quality plans. Implementation is active, with fixture tests and synthetic computer-use acceptance authorized, including final code/visual modal spacing audit. OpenSpec tasks 2.7, 5–8 remain driven by current evidence.

## MVP — Local native client
- Native macOS SwiftUI application with consistent Material-inspired visual direction.
- Week/day calendar and task-focused list/columns; date selectors, Today/Overdue/Search.
- Real read-only Google sync through configured `gws`, explicit cache freshness/error states.
- Calendar and task CRUD controls, including complete/uncomplete, validated with local fixtures. The owner separately authorized a narrowly scoped synthetic live lifecycle for event/task objects created by this run through the actual app workflow, with exact GET before and after each mutation; production/personal mutations remain prohibited.
- Product-quality completion: Material-inspired semantic tokens, list-first Tasks with explicit columns, consistent date-only filters, a collapsible undated region, and measurable performance evidence.
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
