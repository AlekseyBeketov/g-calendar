## ADDED Requirements

### Requirement: Date-only space is compact when empty and aligned when populated
The calendar SHALL use one content-aware, bounded date-only height shared by the displayed day columns. When all displayed days have no date-only content, it SHALL use a compact empty presentation rather than a full repeated empty region for every day. Populated overflow SHALL remain reachable without disrupting the shared time axis or pinned headers.

#### Scenario: Display a week without date-only content
- **WHEN** every visible day has no all-day event or dated task
- **THEN** the date-only region uses a compact shared empty presentation and leaves usable space for the timed grid

#### Scenario: Display unequal amounts of date-only content
- **WHEN** one day contains many all-day events or dated tasks and other days have fewer
- **THEN** every column keeps the same bounded date-only height, its overflow is reachable and corresponding hour lines remain aligned

#### Scenario: Preserve initial and manual scroll intent
- **WHEN** the timed grid first opens, the user scrolls manually and an unrelated state update follows
- **THEN** the initial working-hour anchor is applied at the appropriate initial transition and the unrelated update does not reset manual scroll
- **AND** the hour axis is unclipped and all seven days remain reachable at supported widths

### Requirement: Week-first calendar displays events with correct date semantics
The system MUST provide week and day views that represent timed and all-day events using their calendar timezone and all-day end-date semantics. A month view MAY follow after week/day acceptance.

#### Scenario: Display a timed event
- **WHEN** an event has start and end timestamps with a timezone
- **THEN** the calendar places it at the corresponding local time and duration in the selected view

#### Scenario: Display an all-day event
- **WHEN** an event spans all-day start and exclusive end dates
- **THEN** it appears in the all-day region for the correct inclusive visual dates without an off-by-one-day error

#### Scenario: Navigate the selected range
- **WHEN** the user changes week/day or moves to a previous/next range
- **THEN** the visible dates and fetched request bounds update consistently

### Requirement: Calendar selectors convey access role
The system MUST show available calendars and distinguish read-only access. The UI MUST NOT offer event mutation for a read-only calendar.

#### Scenario: Select a read-only calendar
- **WHEN** the selected calendar grants only reader access
- **THEN** its events remain visible and create/edit/delete actions are unavailable with a clear read-only indication

#### Scenario: Select a writable calendar
- **WHEN** the selected calendar grants a role with event write access
- **THEN** the UI may offer supported create/edit/delete workflows for that calendar

### Requirement: Event edits are explicit drafts and safe in scope
The system MUST keep event changes as local drafts until the user saves. Delete MUST require confirmation. Attendees/invitations are outside the initial scope. Recurring instances MUST NOT be edited unless the UI communicates and enforces the exact supported scope.

#### Scenario: Save an ordinary event draft
- **WHEN** a user saves an event draft in a writable calendar
- **THEN** the app requests the corresponding event write through its adapter only after that explicit action

#### Scenario: Cancel an unsaved event draft
- **WHEN** the user cancels event editing
- **THEN** no event mutation command is issued

#### Scenario: Confirm event deletion
- **WHEN** the user chooses delete and confirms the destructive action
- **THEN** the adapter receives one deletion request for the selected supported event

#### Scenario: Recurring event without supported scope UI
- **WHEN** the selected event is a recurring instance and no explicit scope choice is implemented
- **THEN** event mutation actions are disabled and the app explains that recurring-event editing is not supported in this build

### Requirement: Week and day views spatially represent time and overlap
The calendar MUST provide an actual time grid for timed events, with placement and duration based on the selected calendar timezone. Events with overlapping intervals MUST remain simultaneously visible through a deterministic lane/column layout; all-day events occupy a separate date region, and date-only Tasks remain visually distinct from timed events. The timed region MUST scroll vertically as one shared viewport so every day remains aligned; date-only regions MUST use a consistent bounded height so content in one day cannot offset another day's time axis. The hour labels MUST appear once on a shared time axis. Day headers and the date-only row MUST remain visible while timed content scrolls, and initial timed content MUST open at the configured working-hour anchor. Day mode MUST use the available detail width; week columns MUST expand to use the available width when the configured readable minimum permits, and otherwise retain an explicit horizontal week viewport without silently changing the selected mode.

#### Scenario: Display timed event position and duration
- **WHEN** a user views a timed event in week/day mode
- **THEN** its block begins at the correct local time and height reflects its duration, with a readable event label

#### Scenario: Display overlapping events
- **WHEN** two or more timed events overlap in one calendar/day
- **THEN** the layout allocates visible non-obscuring lanes and preserves accessible event names/times

#### Scenario: Keep all-day items separate
- **WHEN** a date includes all-day events and Tasks with due dates
- **THEN** they appear in a clearly identified all-day/date-only area separate from timed blocks

#### Scenario: Scroll a week of timed events
- **WHEN** the user scrolls the timed calendar vertically
- **THEN** all visible days move together in one viewport and their hour marks remain aligned

#### Scenario: Bound date-only content
- **WHEN** one day has more all-day events or due-date Tasks than another
- **THEN** each day's date-only region keeps the same bounded height and excess content remains reachable within that region

#### Scenario: Allocate week columns to a wide detail viewport
- **WHEN** the week view has enough detail width for all seven readable columns
- **THEN** the columns expand evenly to fit the viewport without unnecessary horizontal scrolling

#### Scenario: Preserve week navigation in a narrow detail viewport
- **WHEN** the week view cannot fit seven columns at their readable minimum width
- **THEN** the selected week mode remains explicit and the user can horizontally navigate all seven days

#### Scenario: Keep one labeled time axis while scrolling
- **WHEN** the user views or vertically scrolls a multi-day calendar
- **THEN** one shared set of hour labels stays aligned with every day column, while day headers and date-only rows remain visible

#### Scenario: Open the timed grid at working hours
- **WHEN** a calendar range is displayed for the first time
- **THEN** the timed viewport opens at the configured working-hour anchor instead of midnight

### Requirement: Calendar selection and visibility are independent
The system MUST allow users to select a calendar context and independently show/hide calendars in the visible workspace, while preserving each event's calendar identity and read-only restrictions.

#### Scenario: Toggle one calendar's visibility
- **WHEN** the user hides or restores one calendar
- **THEN** only that calendar's events are hidden/restored without changing its access role or other visibility selections

### Requirement: Undated tasks use one timeless calendar region
The calendar workspace MUST display tasks without a Google due date in a separate, clearly labeled undated region. An undated task MUST NOT be assigned an arbitrary date or repeated in every day column. The region MUST honor the selected task list, search and visibility rules.

#### Scenario: Show undated tasks without dated content
- **WHEN** a week/day has no event or dated task but the selected scope contains an undated task
- **THEN** the calendar remains non-empty and presents the task once in the undated region

#### Scenario: Avoid duplicating undated tasks across days
- **WHEN** the user views a week containing an undated task
- **THEN** that task appears once in the week-level undated region, not in each day's date-only row

### Requirement: The timeless task region can be collapsed
The week-level undated region MUST be compact and collapsible. Its collapsed state MUST expose the task count and an accessible expand/collapse action. Collapsing the region changes only presentation; it MUST NOT mutate, hide from search, or re-date tasks.

#### Scenario: Collapse undated tasks
- **WHEN** the user collapses the timeless region
- **THEN** the calendar grid gains the released space and the region retains an accessible count and expand action

#### Scenario: Expand undated tasks
- **WHEN** the user expands the timeless region
- **THEN** each scoped undated task and its supported completion action is shown once

### Requirement: Writable-first calendar navigation
Calendars MUST sort writable first then by localized title and stable ID. Missing selection MUST prefer a writable calendar, preserving explicit valid selections and independent visibility. Locks MUST reflect Google access roles.

#### Scenario: Refresh without selected calendar
- **WHEN** The refreshed calendars contain a writer and a reader
- **THEN** The writer is chosen by default and appears before the reader

### Requirement: Calendar task disclosure direction
Collapsed calendar task disclosure MUST show chevron.down and expanded disclosure MUST show chevron.up.

#### Scenario: Expand tasks
- **WHEN** The user activates collapsed task disclosure
- **THEN** The list opens and the chevron points up

### Requirement: Pointer interaction regions
Enabled actionable controls MUST show a pointing hand across the complete hit area including padding. Disabled controls and text entry MUST preserve their native cursor.

#### Scenario: Hover padding
- **WHEN** The pointer enters clickable padding around a button
- **THEN** The cursor becomes a pointing hand without changing hit testing
