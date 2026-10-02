## 1. Tooling and Native App Shell

- [x] 1.1 Reproduce the active CLT SwiftPM manifest-link failure; try only safe local manifest/build options and record exact exit codes.
- [x] 1.2 Build a repeatable native app target; use SwiftPM only if it actually builds, otherwise add a direct-`swiftc` build/test script and accurately record SPM failure.
- [x] 1.3 Create stable bundle metadata, assemble `dist/g-calendar.app`, and verify actual launch/quit behavior without installing login items or signing for release.
- [x] 1.4 Add app settings for configured absolute gws executable and a non-secret setup/availability status.

## 2. Google Adapter and Safe Local Data

- [x] 2.1 Define calendar/event/task/list models with date-only Tasks due, timezone-aware Calendar timestamps and all-day exclusive end semantics.
- [x] 2.2 Implement a constrained Foundation.Process runner with executable URL, argument vector, timeout, bounded output and redacted error reporting; cover it with fake process fixtures.
- [x] 2.3 Implement allowlisted read operations for calendars/events and task lists/tasks, including explicit time range and every page.
- [x] 2.4 Add typed auth/network/quota/process/JSON errors and atomic last-known-good cache; prove a later-page failure cannot erase old data.
- [ ] 2.5 Implement explicit UI-triggered mutation command paths for supported event/task/task-list operations; automated tests assert argument construction and confirmation boundaries only with fixtures.
- [x] 2.6 Run privacy-safe live read-only gws smoke for calendar/task-list metadata and counts only; record sanitized output/exit codes, never titles, email or identifiers.
- [ ] 2.7 Add typed exact-resource GET/read-back for event/task mutations and a narrow actual-app workflow that creates one synthetic event/task with unique run marker/private ID ledger; do not live edit, complete, uncomplete or delete until separately approved.
- [x] 2.8 Refresh the Tasks domain independently after verified task mutations; preserve calendar data and coverage without cross-domain reads.

## 3. Calendar and Task Workflows

- [ ] 3.1 Build SwiftUI navigation, calendar/task-list selectors, Today/Search/sync states and week/day calendar view matching `docs/ui.md`.
- [ ] 3.2 Render timed/all-day events and visible tasks with read-only calendar affordances; disable recurring-instance mutations until exact scope UX is implemented.
- [ ] 3.3 Build task list/column view with Today/Upcoming/Overdue/search and complete/uncomplete controls.
- [ ] 3.4 Implement event/task draft create/edit/delete flows with cancel/save separation and confirmation for destructive actions; never issue live writes in agent tests.
- [x] 3.5 Validate timezone, daylight-saving boundaries, event overlap and all-day exclusive end behavior with deterministic fixtures.
- [x] 3.6 Replace the event list with a week/day time grid, overlap lanes, all-day region, date-only Tasks region, independent calendar visibility toggles, and explicit read-only/recurrence safeguards.
- [x] 3.7 Add responsive task-column fallback, actionable search clear/no-match, selected accessibility states, and inline mutation-failure feedback that preserves drafts.
- [x] 3.8 Add explicit synthetic-only demo/verification launch mode with separate storage and fixture adapter; prove it cannot read user cache or invoke gws.
- [x] 3.9 Define and implement an undated-task policy: show tasks without due date once in a separate, accessible timeless calendar region; do not assign a date or duplicate across week columns; include them in empty-state and filter/search behavior.
- [x] 3.10 Give the timed calendar one bounded, shared vertical scroll viewport and keep each day's date-only region at a consistent bounded height; verify long all-day/task rows remain reachable.
- [x] 3.11 Coalesce in-flight calendar range requests to the latest query, reject superseded UI results, and persist backward-compatible calendar range/timezone coverage in cache.
- [x] 3.12 Allocate week columns from available detail width with a readable minimum; keep narrow-window week navigation explicit and reversible.
- [x] 3.13 Share a single hour axis, pin day/date-only rows above the timed viewport, and anchor the initial scroll to 08:00.
- [x] 3.14 Refresh uncovered calendar ranges without reading Tasks API resources; preserve cached Tasks and report independent per-domain freshness.

## 4. Local Reminders and Notifications

- [x] 4.1 Store task reminder time/favorites separately in app-local metadata; omit them from Google API payloads and logs.
- [x] 4.2 Add explicit permission UX and scheduler-backed plan/cancel/reschedule/dedup/reconciliation behavior using UserNotifications.
- [ ] 4.3 Cover permission denial, duplicate prevention, reschedule, task completion/deletion, remote removal/partial sync and wake/app-activation reconciliation with fake scheduler tests; expose actual-bundle authorization/pending/delivered status without prompting.
- [ ] 4.4 Implement the specified opt-in local-only exact-time reminder for a specific timed, non-recurring Calendar event; do not mirror Google reminder fields or guess all-day/recurrence behavior. Verify composite identity, exact deletion evidence and seconds precision.

## 5. Verification and Handoff

- [ ] 5.1 Verify loading/empty/offline/stale/error states, visible focus, keyboard actions, VoiceOver labels, light/dark/system and resizing.
- [x] 5.2 Run the actual available build and focused test commands plus a fixture integration suite; report each pass/failure/not-run honestly.
- [ ] 5.3 Launch the real built `.app` in isolated synthetic demo mode; verify GUI/process behavior. Screenshot requires Screen Recording approval and remains a human gate.
- [x] 5.4 Write `docs/verification.md` with exact commands, exit codes, privacy-safe read-only smoke results and needs-human-verification items; update README and roadmap/status.
- [ ] 5.5 Inspect sources, scripts and tracked/untracked state for accidental personal data, user-file deletion, or unsupported claims; do not commit or publish.
