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
- [x] 2.5 Implement explicit UI-triggered mutation command paths for supported event/task/task-list operations; automated tests assert argument construction and confirmation boundaries only with fixtures.
- [x] 2.6 Run privacy-safe live read-only gws smoke for calendar/task-list metadata and counts only; record sanitized output/exit codes, never titles, email or identifiers.
- [x] 2.7 Add typed exact-resource GET/read-back for event/task mutations and a narrow actual-app workflow for this run's uniquely marked synthetic event/task; use a private ID ledger and exact GET before and after every authorized create/edit/complete/reopen/delete operation. Never touch unrelated objects.
- [x] 2.8 Refresh the Tasks domain independently after verified task mutations; preserve calendar data and coverage without cross-domain reads.

## 3. Calendar and Task Workflows

- [x] 3.1 Build SwiftUI navigation, calendar/task-list selectors, Today/Search/sync states and week/day calendar view matching `docs/ui.md`.
- [x] 3.2 Render timed/all-day events and visible tasks with read-only calendar affordances; disable recurring-instance mutations until exact scope UX is implemented.
- [x] 3.3 Build task list/column view with Today/Upcoming/Overdue/search and complete/uncomplete controls.
- [x] 3.4 Implement event/task draft create/edit/delete flows with cancel/save separation and confirmation for destructive actions; automated fixtures never issue live writes; separately authorized native synthetic acceptance is scoped by task 2.7.
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
- [x] 4.3 Cover permission denial, duplicate prevention, reschedule, task completion/deletion, remote removal/partial sync and wake/app-activation reconciliation with fake scheduler tests; expose actual-bundle authorization/pending/delivered status without prompting.
- [x] 4.4 Implement the specified opt-in local-only exact-time reminder for a specific timed, non-recurring Calendar event; do not mirror Google reminder fields or guess all-day/recurrence behavior. Verify composite identity, exact deletion evidence and seconds precision.

## 5. Verification and Handoff

- [x] 5.1 Verify loading/empty/offline/stale/error states, visible focus, keyboard actions, VoiceOver labels, light/dark/system and resizing.
- [x] 5.2 Run the current-source build and focused test commands plus the fixture integration suite with a compatible installed compiler/SDK; report environment blockers separately from source test failures.
- [x] 5.3 Launch the real built `.app` in isolated synthetic demo mode; verify GUI/process behavior. Computer-use testing and synthetic screenshots are owner-authorized; respect actual OS permission availability.
- [x] 5.4 Refresh `docs/verification.md` with current-source commands/exit codes, sanitized live acceptance results and human gates; update README and roadmap/status only where current behavior changed.
- [x] 5.5 Inspect sources, scripts and tracked/untracked state for accidental personal data, user-file deletion, or unsupported claims; do not publish releases; the owner separately authorized source checkpoint commit/push.

## 6. Product Quality Follow-up

- [x] 6.1 Make Today, Upcoming, Overdue and Without due use consistent local date-only predicates across task filters, groups and calendar visibility.
- [x] 6.2 Add a compact, accessible collapse/expand control for the single week-level undated-task region.
- [x] 6.3 Make list the default task presentation and expose columns as an explicit alternative with a readable narrow-width fallback.
- [x] 6.4 Complete shared semantic Material-inspired color/surface/state roles across calendar, tasks, forms and status while preserving SF typography and System appearance default.
- [x] 6.5 Distinguish and provide contextual recovery for loading, empty, no-match, setup-required, offline, stale and failure states; preserve drafts and cache on errors.
- [x] 6.6 Complete native keyboard, visible focus, selected/accessibility states for primary navigation, calendar visibility and task controls.
- [x] 6.7 Measure fixed synthetic local interaction scenarios before choosing performance budgets; optimize only measured bottlenecks and record method/results.

## 7. Screenshot Audit and Interaction Reliability — 2026-10-05

Scope and acceptance: `docs/plans/2026-10-05-final-product-completion.md`. Implementation resumed by the owner on 2026-10-05; checkboxes require current evidence.

- [x] 7.1 Reproduce task-save read-back rejection with synthetic fixtures, including empty/omitted notes, due normalization, genuine field/identity mismatch, read failure and missing create-response ID; establish the cause before changing verification semantics.
- [x] 7.2 Model unresolved writes separately from pre-write rejection, retain known exact identity and draft across reopen/relaunch, provide read-only recheck, and prevent repeated INSERT for the same unresolved attempt across tasks/events/task lists; never accept an unverified write as success. Interprocess lease, exact attempt ownership, atomic UI review and stale-instance/separate-process regression fixtures now pass; current-bundle draft/recovery/busy UI acceptance passed on 2026-10-07.
- [x] 7.3 Align sidebar visible row and hit area across sections, task lists, workspace filters and calendar selection; verify icon/text/blank area/edges plus keyboard/AX activation and independent visibility checkbox, then audit equivalent controls throughout the app.
- [x] 7.4 Make calendar/task headers adapt without letter-by-letter labels, crowding or inaccessible actions; simplify duplicate filter controls while preserving access with sidebar hidden and retaining Week in narrow windows.
- [x] 7.5 Compact empty date-only calendar content with one shared bounded content-aware height, preserve overflow and pinned column alignment, and keep the shared hour axis visible during horizontal scrolling and verify time-axis clipping, seven-day horizontal reachability and initial/manual scroll behavior.
- [x] 7.6 Improve default task-list density and empty-group treatment; define stable chronological due order for dated views without rewriting Google/manual order or mixing completed/undated tasks.
- [x] 7.7 Make task/event/list forms fit content and viewport, preserve reachable footer and drafts/errors, clarify creation context and navigation selection symbols, and consolidate repetitive technical help across themes.
- [x] 7.8 Execute the synthetic cross-app interaction/layout/accessibility/state regression matrix, verify test-resource isolation and exact-ledger cleanup policy, and record results without personal screenshot data or unverified closure claims.
- [x] 7.9 Establish an optimized-build GUI baseline including cached launch, search, selection, week navigation, resize, scroll, forms, CPU and memory; distinguish CLI/network/read-back time, profile hotspots, then choose budgets and link evidence to task 6.7.

## 8. Approved Pixel Paper and Final Spacing Acceptance — 2026-10-05

- [x] 8.1 Record Pixel Paper as the approved identity with only Color Atlas task-row metadata, consolidate plans and remove rejected design artifacts.
- [x] 8.2 Implement aligned due/status/list/local metadata and selected-row treatment using the approved solid light-first Pixel Paper system; retain native System/Dark and supported semantics.
- [x] 8.3 Audit padding, alignment, content sizing and footer reachability in code and through computer use for all modal and primary surfaces after UI development; fix equivalent spacing defects and record evidence. Source audit and current-bundle visual/resize/theme acceptance completed on 2026-10-07, including overflow inset, decorative hit testing and short-window footer reachability.

Current evidence (2026-10-07): optimized current app run-54154 built and externally accepted; ordinary/optimized model suites 440 assertions, native UI suite 20 assertions, installer fixtures 26 scenarios. Complete matrix and spacing evidence: docs/verification.md; actual GUI timing limits/budgets: docs/GUI_PERFORMANCE.md. AX labels were inspected; full spoken VoiceOver walkthrough and human notification-banner observation are separate external checks, not claimed by this checklist.

## 9. Installation implementation and local acceptance

- [x] 9.1 Implement an explicit arm64/macOS 13+ source installer with verified bundle identity, destination lock, atomic upgrade/rollback and preservation of all app data; uninstall removes only the owned application bundle.
- [x] 9.2 Package a light Pixel Paper DMG with Applications shortcut plus versioned ZIP, manifest and final checksums; verify the image and its contents without claiming ad-hoc artifacts are notarized.
- [x] 9.3 Implement a pinned GitHub release installer with checksum, architecture/minOS, bundle ID and expected Developer ID Team ID verification before installation; provide the current-checkout one-command source workflow and an exact public installer SHA/digest pinning contract, with no Gatekeeper bypass or silent OAuth. A real public download command requires a separately approved signed release and is explicitly not claimed available today.
- [x] 9.4 Implement Developer ID/notarization/stapling/verification scripts and release documentation; final signed distribution acceptance requires owner-supplied credentials, license/release decision and a downloaded clean-machine launch. Do not publish releases implicitly.
- [x] 9.5 Run isolated installer fixtures for installs, repeat/upgrade/rollback, failure/recovery/concurrency, foreign/running bundles, archive safety, spaces/permissions, signature/checksum mismatch and data preservation; complete native DMG/setup/upgrade acceptance and accurately document external release gates.

## External distribution acceptance — explicitly outside local completion

Developer ID credentials, license/publication approval, real published installer SHA/tag and downloaded clean-Mac acceptance remain open. No public signed/notarized distribution has been claimed or published. This is the credential/release gate already required by task 9.4 and the app-installation specification; tasks 9.1–9.5 mark implemented scripts, fixtures and local-bundle acceptance. Full spoken VoiceOver and visible notification banner remain human checks. See docs/PENDING_DECISIONS.md and docs/RELEASING.md.


## 12. Workspace improvements (2026-10-10)

- [x] 12.1 Configurable shortcuts and Command-B sidebar toggle; verify, commit and push main.
- [x] 12.2 Inline local reminder time, current notification icon and alert preference; verify, commit and push main.
- [ ] 12.3 Login at system start with real macOS status; verify, commit and push main.
- [ ] 12.4 Writable-first calendar ordering and default selection; verify, commit and push main.
- [ ] 12.5 Down/up calendar task disclosure; verify, commit and push main.
- [ ] 12.6 Pointer cursor on full interactive hit regions and repository rule; verify, commit and push main.
- [ ] 12.7 All boards by default and columns grouped by board; verify, commit and push main.
- [ ] 12.8 Verified move to another board from task editor; verify, commit and push main.
