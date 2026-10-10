## ADDED Requirements

### Requirement: Local reminders are separate from Google task data
The system MUST store local reminder time in app-local metadata, label it local-only, and never create a hidden Google Calendar event as a copy. Google Tasks due remains date-only.

#### Scenario: Persist local reminder extension
- **WHEN** a user sets a reminder time for a Google task
- **THEN** the time is stored in the app's local reminder store and excluded from the Google Tasks request body

#### Scenario: Explain date-only due
- **WHEN** a task is displayed or edited
- **THEN** the app distinguishes the Google due date from an optional local reminder time

### Requirement: Notification scheduling is permission-aware and deduplicated
The system MUST use UserNotifications only after the user has explicitly enabled reminders and received the standard OS permission flow. Schedule, cancel, reschedule and dedup behavior MUST be testable behind an injected scheduler; task completion/deletion MUST cancel any associated local reminder.

#### Scenario: Schedule after permission
- **WHEN** notification authorization is granted and an enabled local reminder has a future time
- **THEN** exactly one pending notification is scheduled for that reminder

#### Scenario: Denied permission
- **WHEN** the user denies notification authorization
- **THEN** the app reports that notifications are disabled and does not claim that a reminder is scheduled

#### Scenario: Reschedule or clear reminder
- **WHEN** a local reminder time changes or is removed
- **THEN** the previous pending request is replaced or cancelled without duplicates

#### Scenario: Complete or delete the task
- **WHEN** the task associated with a local reminder becomes complete or is deleted
- **THEN** its pending notification is cancelled

#### Scenario: Reconcile on app activation
- **WHEN** the app returns to the foreground
- **THEN** it may reconcile app-local reminder definitions with pending requests without generating duplicates

#### Scenario: Reconcile after wake
- **WHEN** macOS wakes or the app becomes active after sleep
- **THEN** the app reconciles eligible future task reminders without scheduling duplicates and reports scheduling errors safely

### Requirement: Notification delivery limitations are explicit
The system MUST explain that local notification display depends on macOS permission, Focus/notification settings and device lifecycle. It MUST NOT promise delivery while the Mac is asleep or after explicit application Quit where OS scheduling behavior is not verified.

#### Scenario: Permission and OS settings block banner
- **WHEN** the app has scheduled a local reminder but macOS notification settings prevent banner display
- **THEN** the app does not describe the reminder as guaranteed delivered and provides a route to notification settings if available

### Requirement: Local reminders support one specific timed Calendar event
The system MUST allow an explicit user action to attach a local-only notification time to a specific timed, non-recurring Calendar event. The exact local date/time is user-selected and stored in app-local metadata keyed by calendar identity and event/occurrence identity. This MUST NOT mirror, change, or claim parity with Google `event.reminders`; the UI MUST state that delivery is local to this Mac. All-day and recurring events remain unsupported until their trigger time/scope is explicitly implemented.

#### Scenario: Set a local reminder for a timed event
- **WHEN** the user chooses an exact future local reminder time for a specific supported event
- **THEN** the time is stored locally, one stable-identifier UserNotification request is scheduled when authorized, and no Google mutation is sent

#### Scenario: Reject all-day or recurring event reminder
- **WHEN** an event is all-day or part of a recurrence whose occurrence scope is not supported
- **THEN** the reminder action is disabled with an accessible explanation and no request is scheduled

#### Scenario: Preserve an event reminder outside the current sync range
- **WHEN** a refresh does not include an event because its range/page is different
- **THEN** absence from that partial date range alone does not remove its local metadata or pending request

#### Scenario: Cancel after exact remote removal is confirmed
- **WHEN** an exact event GET confirms that the event has been deleted
- **THEN** its local event reminder is cancelled and metadata is reconciled; a missing list result outside its date range is insufficient evidence

#### Scenario: Retain second-level trigger precision
- **WHEN** an authorized reminder is scheduled for a future instant that is not minute-aligned
- **THEN** the calendar trigger retains seconds and its next trigger date does not move earlier or to the next minute

### Requirement: Inline local reminder time and native alerts
The task editor MUST allow selecting local reminder date/time separately from Google due date. The app MUST request alert presentation preference and use the current app icon; it MUST explain the user-controlled macOS style.

#### Scenario: Save reminder with task
- **WHEN** A task save is read-back verified
- **THEN** The reminder is saved for that verified task ID locally; a local failure never repeats the Google mutation
