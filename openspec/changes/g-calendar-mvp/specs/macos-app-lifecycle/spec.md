## ADDED Requirements

### Requirement: Approved Pixel Paper identity includes Color Atlas task metadata
The app SHALL use the owner-approved Pixel Paper visual foundation with solid light-first surfaces, blue primary accent, native SF typography and classic sidebar. Task rows SHALL adopt aligned due/status, list tags and existing local metadata from Color Atlas. System/Dark SHALL remain supported; the rejected rail/glass/combined-calendar-pane concepts SHALL NOT be introduced by this change.

#### Scenario: Review the approved task workspace
- **WHEN** the task workspace opens in the main list presentation
- **THEN** compact grouped rows display readable titles and aligned supported metadata with independent completion/menu actions in the shared Pixel Paper system

### Requirement: Final modal spacing is verified in code and actual UI
After UI implementation the project SHALL audit consistent outer insets, field/section spacing, header/footer alignment and content sizing in code and through owner-authorized synthetic computer-use inspection across task/event/list editors, settings and reminder surfaces. A successful build alone SHALL NOT count as visual acceptance.

#### Scenario: Review modal padding and reachability
- **WHEN** short or long drafts/errors are shown in supported light/dark and narrow windows
- **THEN** fields and footer remain reachable with consistent spacing, without oversized blank regions or clipped actions
- **AND** evidence records the actual surfaces inspected and any remaining OS or human limitations

### Requirement: Visible navigation areas are reliable native interaction targets
The app SHALL make the visible action area of each sidebar navigation row respond consistently to pointer activation, including the icon, label and blank area within the row. It SHALL expose matching keyboard and accessibility activation/selection state and SHALL preserve independent adjacent actions such as calendar visibility.

#### Scenario: Activate a sidebar row outside its text
- **WHEN** the user clicks the icon, center blank area or interior edge of a section, task-list or filter row
- **THEN** that row's action occurs exactly once and the selected presentation matches its accessibility state

#### Scenario: Activate calendar visibility beside selection
- **WHEN** the user activates a calendar visibility checkbox
- **THEN** only visibility changes and the selected calendar context does not change

### Requirement: Headers and editors retain usable geometry across supported windows
The app SHALL preserve readable labels, reachable actions and native focus at supported window sizes and in Light, Dark and System appearance. Headers SHALL NOT compress labels into letter-by-letter columns. Editors SHALL fit their content and viewport while keeping fields, inline errors and action footer reachable. Repetitive technical guidance SHOULD be consolidated into contextual help.

#### Scenario: Resize with long labels and sidebar changes
- **WHEN** the window is resized or the sidebar is hidden while synthetic names are long
- **THEN** header action groups adapt as whole controls without overlap, clipped primary actions or fragmented labels
- **AND** filters remain reachable when the sidebar is hidden

#### Scenario: Show an editor error
- **WHEN** a task, event or list editor displays a long error after an unsuccessful save
- **THEN** the draft remains visible and the footer is reachable with pointer and keyboard without excessive fixed empty space

### Requirement: Performance acceptance separates local UI and remote work
The project SHALL record a reproducible optimized-build baseline for local interactions, scrolling, launch, CPU and memory separately from CLI startup, network requests and exact read-back. It SHALL document machine/build/dataset/viewport and repeat methodology before choosing budgets; algorithm microbenchmarks SHALL NOT substitute for GUI latency or frame evidence.

#### Scenario: Measure task and calendar interactions
- **WHEN** fixed synthetic datasets are profiled
- **THEN** results report local event-to-visible-update p50/p95 and scrolling hitches with their measurement conditions, while remote timing is recorded separately

### Requirement: Native app bundle is launchable and lifecycle is explicit
The system MUST provide a macOS `.app` with a stable bundle identifier, valid Info.plist and a documented reproducible build path. Closing the last window MUST NOT be represented as an explicit Quit action.

#### Scenario: Launch the built app bundle
- **WHEN** a user opens `dist/g-calendar.app`
- **THEN** macOS launches the native SwiftUI application and its primary window without a browser wrapper

#### Scenario: Close window versus quit
- **WHEN** the user closes the last app window
- **THEN** the process remains available for scheduled local notifications until the user explicitly chooses Quit

### Requirement: System appearance and accessible controls
The system MUST support System, Light and Dark appearance and expose primary calendar/task navigation and actions to keyboard and assistive technology.

#### Scenario: Follow macOS appearance
- **WHEN** the user switches macOS between Light and Dark while app appearance is System
- **THEN** app surfaces and semantic text colors adapt without requiring restart

#### Scenario: Navigate without a pointer
- **WHEN** a keyboard or VoiceOver user focuses primary navigation and actionable items
- **THEN** each item has a visible/announced focus state, meaningful accessible label and keyboard-reachable action

### Requirement: Notification permission is explicit
The system MUST request UserNotifications authorization only after a deliberate user action that enables a local reminder. Automated tests MUST inject a fake notification scheduler.

#### Scenario: Enable reminder with no prior permission request
- **WHEN** the user explicitly enables a reminder
- **THEN** the app requests the relevant macOS permission and reports the resulting authorization state

#### Scenario: App launch without reminder action
- **WHEN** the app launches or a test suite runs without an explicit reminder-enable action
- **THEN** no permission prompt is triggered

### Requirement: Synthetic demo mode is isolated from personal app data
The app MUST provide an explicit synthetic-only verification/demo launch mode that uses a separate storage namespace and fixture adapters, displays only synthetic or empty data, and never reads/writes the normal Google cache or invokes `gws`.

#### Scenario: Launch isolated demo mode
- **WHEN** the user starts the app with the documented demo/verification option
- **THEN** only synthetic fixtures and separate demo storage are used, and the UI clearly labels the demo state

#### Scenario: Keep demo mode offline
- **WHEN** an operator uses demo mode to exercise UI forms
- **THEN** mutations are confined to the fixture adapter and no real Google operation or user cache access occurs

### Requirement: Notification state can be inspected without requesting permission
The system MUST expose a read-only query of authorization, pending-request count, delivered-request count, and foreground delegate capability that does not request authorization or change notification settings.

#### Scenario: Inspect notification status
- **WHEN** status is queried from the app's real bundle
- **THEN** it reports actual authorization and pending/delivered counts without a permission prompt or content/title disclosure

### Requirement: Semantic appearance adapts across system modes
The app MUST use a small shared semantic palette for canvas, surfaces, primary and secondary text, outlines, primary accent, event/task identity, and status feedback. System appearance MUST remain the default; Light and Dark MUST use paired adaptive values. SF typography and native macOS controls remain the baseline. Calendar color MUST be supplemental identity information, not the only way to understand an event or selected state.

#### Scenario: Follow system appearance
- **WHEN** app appearance is System and macOS appearance changes
- **THEN** semantic text and surface roles adapt without restarting the app

#### Scenario: Read event and task state without color
- **WHEN** an event or task is selected, overdue, read-only, or in an error state
- **THEN** text, icon, or accessible label communicates that state in addition to color

### Requirement: Primary navigation and actions expose keyboard and accessibility state
Primary navigation, task filters, calendar visibility, and actionable task/event rows MUST expose meaningful names and selected states to assistive technology. Important controls MUST provide visible keyboard focus and remain reachable without reducing their effective target below 44 by 44 points where the native control permits it. Native menu commands MUST document implemented shortcuts.

#### Scenario: Navigate with keyboard
- **WHEN** the user moves through primary navigation and actions with the keyboard
- **THEN** visible focus follows the selection and each action can be activated without a pointer

#### Scenario: Inspect selected and disabled actions
- **WHEN** a calendar, task list, filter, read-only role, or unsupported recurring event is selected
- **THEN** accessibility output reports its selected/disabled state and any relevant explanation

### Requirement: Workspace status is distinct and recoverable
The app MUST distinguish initial loading, setup-required, empty, no-match, offline, stale-cache, and failed-refresh states. A failure MUST preserve the last-known-good cache. Any retry or clear-search action MUST be adjacent to the state it resolves. The app MUST NOT claim that unsaved work is queued when no durable offline write queue exists.

#### Scenario: Refresh fails with cached data
- **WHEN** a refresh fails after a prior successful sync
- **THEN** the app keeps cached data visible, marks it stale, and offers a contextual retry

#### Scenario: Search has no matches
- **WHEN** the current query matches no items in a non-empty selected scope
- **THEN** the app presents a no-match state with an adjacent action that clears the query

#### Scenario: Initial empty scope
- **WHEN** the current range or selected task list has no data and no prior snapshot
- **THEN** the app presents an empty/setup state rather than a no-match or stale-data message
