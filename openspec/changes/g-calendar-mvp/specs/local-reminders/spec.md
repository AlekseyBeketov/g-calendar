## ADDED Requirements

### Requirement: Automatic Google event notifications
The app MUST derive timed-event notifications from the authenticated user's Google Calendar settings without per-event local reminder configuration. useDefault=true inherits CalendarList defaultReminders; useDefault=false uses only event overrides. Only popup offsets produce native notifications; an empty set MUST NOT create a fallback start notification. All-day, cancelled and self-declined events MUST NOT notify. Recurring instances MUST use distinct occurrence identities.

#### Scenario: Inherit Google reminders
- **WHEN** a timed event uses defaults with popup offsets 10 and 0 minutes
- **THEN** g-calendar schedules one notification at each instant without a local reminder action

#### Scenario: Individually disabled reminders
- **WHEN** an event has useDefault=false with empty overrides
- **THEN** no notification is scheduled even if its calendar has defaults

#### Scenario: Changed reminders without changed updated
- **WHEN** calendar defaults or event reminder settings change
- **THEN** the next notification read recalculates requests regardless of event.updated

### Requirement: Independent complete notification coverage
The service MUST read a complete calendar catalogue and all event pages independently of the visible workspace. Independent reads MUST be bounded to four. The upper read boundary MUST account for the maximum advance offset. Refresh MUST occur after startup, successful synchronization, verified mutation, activation, wake and timezone changes, and periodically while the process runs including with its window closed.

#### Scenario: Event outside the open week
- **WHEN** the workspace displays a different week from an eligible future reminder
- **THEN** that event is still included in the notification schedule

#### Scenario: Failure on a later page
- **WHEN** any page of a calendar read fails
- **THEN** that calendar does not acquire complete coverage and previous pending notifications are preserved

### Requirement: Serialized permission-aware schedule reconciliation
The service MUST serialize writes, coalesce refreshes, reject stale reads, use stable account/calendar/occurrence/offset identities, replace changed requests and leave unchanged requests untouched. Cancellation MUST affect pending requests only and preserve delivered history. A global setting controls automatic notifications. OS permission MUST be requested only through explicit global enable without repeated prompts after denial. Demo and tests MUST NOT request real authorization or schedule system notifications.

#### Scenario: Unchanged synchronization
- **WHEN** the same schedule is reconciled twice
- **THEN** no duplicate or unnecessary replacement is made

#### Scenario: Partial failure or unknown settings
- **WHEN** settings are unknown or a calendar fails
- **THEN** absent data does not cancel its last confirmed schedule

#### Scenario: Scheduler error
- **WHEN** installing a changed notification fails
- **THEN** destructive cleanup is deferred, status is shown and the next refresh may retry

#### Scenario: Disable globally
- **WHEN** the user disables automatic notifications
- **THEN** active-account pending requests are cancelled without removing delivered history or another account's data

### Requirement: Preserve legacy metadata without manual reminder management
Legacy device-local task/event reminder definitions MUST be archived without deletion or automatic Google writes before retiring legacy pending requests. Editors and menus MUST NOT expose per-resource local reminder toggles or time pickers. Tasks due remains date-only; a local timestamp or hidden event MUST NOT substitute for true Google task-time synchronization.

#### Scenario: Migrate a manual reminder
- **WHEN** automatic scheduling replaces the legacy workflow successfully
- **THEN** original metadata is preserved in an account-scoped archive and obsolete manual pending requests are retired

### Requirement: Honest task-time capability
The app MUST distinguish Google scheduled datetime, date-only scheduled day and Google deadline. Precise task notifications MUST use confirmed synchronized Google task time. Public due MUST NOT be treated as a timestamp. Unavailable task-time access MUST be visible and MUST NOT be described as implemented synchronization. Tasks without confirmed time MUST NOT receive invented 09:00 notifications.

#### Scenario: Date-only Tasks API
- **WHEN** the transport returns only public due
- **THEN** the task date remains usable, no exact time is invented, and settings explain unavailable capability

### Requirement: Native branded notification delivery
Automatic notifications MUST use the installed app bundle's «Календарь» display name and icon, event title, localized event date and start/end time in the event or calendar timezone, optional location as body, and a non-repeating exact-time trigger. Delivery depends on macOS permission, Focus and device lifecycle. A build MUST NOT count as banner verification or promise detection of remote changes while explicitly quit.

#### Scenario: Show event details
- **WHEN** a timed event with a summary and location has an eligible notification
- **THEN** the banner shows the app identity and icon, event summary as its title, date and start/end time below it, and the location when present

#### Scenario: System settings prevent a banner
- **WHEN** a scheduled request is suppressed by Focus or macOS settings
- **THEN** scheduler/system status and a route to notification settings are shown without guaranteed delivery claims

### Requirement: Legacy and diagnostic local notification content
Native requests from the retained local scheduler MUST show the resource title, localized reminder fire date/time and a local-reminder label. The trigger MUST retain the same instant, seconds precision, non-repeating behavior and account namespace. This does not restore retired local reminder editors or imply synchronized Google task time.

#### Scenario: Local reminder crosses midnight
- **WHEN** a retained local task or event request fires on the next calendar day in the device timezone
- **THEN** its subtitle shows that local date and time, its title shows the resource summary and its exact trigger agrees with the displayed instant

#### Scenario: Synthetic diagnostic notification
- **WHEN** explicit notification-test mode schedules its single authorized test request
- **THEN** it uses the same native content factory without accessing Google or changing reminder metadata

### Requirement: Artwork-specific bundle icon resources
Builds from build number 3 onward MUST derive the bundled ICNS filename from the approved artwork digest and set CFBundleIconFile to that name. Release verification MUST reject mismatched artwork/filename pairs while retaining the same application identity and user settings. This packaging check MUST NOT be presented as proof of a visible macOS banner.

#### Scenario: Change app artwork
- **WHEN** approved ICNS bytes change
- **THEN** the next bundle uses a different icon resource filename and the plist names that exact resource

#### Scenario: Distinguish acceptance builds
- **WHEN** explicit notification-test mode runs from a bundle with a build number
- **THEN** its single synthetic banner includes that build number, without requesting permission or reading Google data

### Requirement: Native icon representation integrity
The stored ICNS MUST be generated with the native encoder from the approved raster master. The icon check MUST decode all ten standard 1x/2x representations through iconutil and compare their dimensions and rendered pixels with the master. Comparing only embedded resource bytes or the largest image is insufficient.

#### Scenario: Corrupt legacy small representation
- **WHEN** a legacy small-size ICNS representation decodes into unrelated pixels despite a valid largest image
- **THEN** the focused icon check fails before that resource is accepted
