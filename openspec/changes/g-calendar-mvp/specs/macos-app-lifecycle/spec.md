## ADDED Requirements

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
