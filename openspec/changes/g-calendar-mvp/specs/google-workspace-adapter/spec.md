## ADDED Requirements

### Requirement: Unresolved writes preserve identity and prevent accidental repetition
The app SHALL distinguish rejection before a write from a write whose outcome is unresolved after sending or acceptance. It SHALL retain the draft and any known exact resource identity for recovery across closing/reopening the editor and app restart, SHALL NOT repeat an INSERT for the same unresolved attempt through Save or retry, and SHALL NOT claim success without exact identity and semantic field verification. Recovery records SHALL NOT act as an automatic write queue.

#### Scenario: Create succeeds but exact verification fails
- **WHEN** a create response identifies a resource but its exact GET fails or fields do not verify
- **THEN** the app retains that identity, explains the unresolved result and offers a read-only exact recheck instead of another create request
- **AND** repeated clicks or reopening the draft do not create a duplicate for that attempt

#### Scenario: A write outcome has no known resource identity
- **WHEN** the write may have reached Google but the response does not establish an exact resource ID
- **THEN** the app preserves the unresolved state without automatically resending the write or presenting title-only search as verification

#### Scenario: Verify equivalent empty values without hiding mismatches
- **WHEN** documented or fixture-established API normalization changes representation of an optional empty field or date-only due
- **THEN** verification applies the explicitly defined semantic equivalence for that field
- **AND** mismatching identity, nonempty content, date or completion state still fails verification

#### Scenario: Rejection occurs before sending
- **WHEN** validation or authorization prevents a request from being sent
- **THEN** the app reports a pre-write rejection, retains the draft and permits a corrected explicit Save without falsely recording an accepted write

### Requirement: Google account connection is the default and gates workspace access
The normal application connection MUST use the direct Google Calendar and Tasks APIs. A fresh install and an existing install without an explicit transport choice MUST select Google account connection by default. Until a Google account has completed OAuth authorization, the app MUST show its first-run connection experience and MUST NOT expose calendar/task data operations or silently fall back to `gws`. The OAuth flow MUST use the app's configured Desktop OAuth client, PKCE and a validated loopback callback; long-lived credentials MUST be stored in macOS Keychain and MUST NOT be written to app cache, logs or screenshots. Only after authorization is saved may the app begin read operations.

#### Scenario: Open the app without a connected account
- **WHEN** the app launches with no saved Google authorization
- **THEN** the required Google connection experience is shown before the calendar/task workspace
- **AND** no calendar/task request or `gws` process is started

#### Scenario: Complete the first Google sign-in
- **WHEN** the user explicitly chooses to connect Google and authorization completes
- **THEN** the app stores the refresh credential in Keychain, then begins read-only calendar/task synchronization
- **AND** a failed, cancelled or rejected authorization leaves the workspace gated and offers retry

#### Scenario: Preserve an explicit optional gws selection
- **WHEN** a user has explicitly selected `gws` in Settings
- **THEN** the stored selection remains `gws` across launches until changed by the user
- **AND** an unresolved mutation journal continues to block transport switching until safely recovered

### Requirement: gws is an optional transport executed through a constrained process boundary
The system MUST expose `gws` only as an optional connection choice in Settings. It MUST resolve a configured absolute executable or a documented safe candidate and invoke it with `Foundation.Process` and a separate argument vector. It MUST NOT auto-install `gws`, construct shell command strings, accept arbitrary service/method commands from UI input, read/export its credentials, or invoke auth-changing commands. Selecting `gws` MUST NOT happen as an implicit fallback when Google account authorization is missing or fails.

#### Scenario: User chooses gws in Settings
- **WHEN** the app starts without an interactive shell PATH
- **THEN** it uses a validated configured absolute executable or a documented safe candidate and reports a non-secret setup error if unavailable

#### Scenario: Missing optional CLI
- **WHEN** the user explicitly selects `gws` but no executable is available
- **THEN** the app explains that this optional method requires `gws` and offers the configured-path setting
- **AND** it does not attempt to install the CLI or silently switch connection methods

#### Scenario: Invoke a supported list operation
- **WHEN** the adapter performs a supported read request
- **THEN** it starts only an allowlisted gws service/resource/method with separately encoded arguments

#### Scenario: Reject an unapproved command
- **WHEN** a UI value or malformed state attempts to select a command outside the allowlist
- **THEN** the adapter rejects it without launching a process

### Requirement: Pagination and errors preserve complete last-known-good data
The system MUST traverse every page before committing a refreshed snapshot. Process failure, auth/network/quota error, malformed JSON or incomplete pagination MUST be reported as a failed refresh, not converted to an empty result; an existing cache MUST remain intact.

Calendar snapshots MUST record the date range and timezone for which event data was fetched. A legacy or non-covering snapshot MUST NOT be treated as proof that the selected calendar range is empty. When several range requests overlap, only the active request or the latest coalesced range may be published to the UI; navigation to an intermediate range may be coalesced, but the final requested range MUST NOT be lost.

Navigating to an uncovered calendar range MUST refresh calendars and events without refetching Tasks lists or Tasks. The range refresh MUST preserve the last complete cached task data and its independent freshness timestamp; explicit full sync remains responsible for refreshing both data domains. Calendar and task freshness MUST be tracked separately so refreshing one domain cannot imply that the other was refreshed.

Refreshing Tasks after a verified task mutation MUST fetch task lists and their tasks without refetching calendars or events. It MUST preserve calendar data, range coverage, and calendar freshness from the cached snapshot while updating Tasks freshness only after the complete paginated Tasks read succeeds.

#### Scenario: Successful multi-page refresh
- **WHEN** a list operation returns multiple pages
- **THEN** each page is decoded and every object is included in the committed snapshot

#### Scenario: Failed later page
- **WHEN** a later page fails after an earlier page succeeded
- **THEN** the partial result is not committed and the previous cached snapshot remains available as stale data

#### Scenario: Malformed response
- **WHEN** the process exits unsuccessfully or returns invalid JSON
- **THEN** the app presents an error state and does not claim that the remote collection is empty or synchronized

#### Scenario: Navigate while a range request is active
- **WHEN** the user navigates from range A to B and then C before A completes
- **THEN** A is not published as data for C, B may be coalesced, and C is requested next

#### Scenario: Read a legacy cache without range metadata
- **WHEN** a saved snapshot predates calendar coverage metadata
- **THEN** its event range is considered unknown until a successful range query records coverage

#### Scenario: Refresh a new calendar range without re-fetching Tasks
- **WHEN** the user navigates outside the covered calendar range
- **THEN** the adapter fetches calendars and events only, preserves cached task lists/tasks, and leaves Tasks freshness unchanged

#### Scenario: Refresh Tasks without re-fetching the calendar
- **WHEN** an exact task or task-list mutation has been verified
- **THEN** the adapter refreshes task lists/tasks only, preserves calendar events and range coverage, and leaves calendar freshness unchanged

### Requirement: Mutation requests originate only from explicit user UI actions
The system MUST NOT issue Google mutation commands during startup, refresh, cache load, demo mode or fixture automation. Supported mutations MUST be initiated only from the matching explicit UI action; destructive actions require confirmation. Automated integration tests MUST use a clearly-marked fake runner and MUST NOT contact real Google write endpoints. The separately approved live acceptance create/read-back is a distinct operation, never an automatic startup or test-suite action.

#### Scenario: Startup and refresh remain read-only
- **WHEN** the app starts and refreshes calendar/task data
- **THEN** only allowlisted read operations are issued

#### Scenario: User saves an edit
- **WHEN** the user explicitly saves a supported event/task edit in the UI
- **THEN** one matching write operation is sent through the adapter and the resulting status is shown

#### Scenario: Test a mutation flow
- **WHEN** the mutation UI is tested with a fixture process runner
- **THEN** the exact arguments and response handling are asserted without any live Google mutation

### Requirement: Logs exclude personal content and auth material
The system MUST NOT log event/task titles, participant emails, raw API payloads, tokens or credential paths. Safe logs MAY include operation type, exit status and sanitized error category.

#### Scenario: Report a sync error
- **WHEN** a gws operation fails
- **THEN** logs contain safe diagnostic metadata only and the UI presents an understandable non-secret error

### Requirement: Synthetic live acceptance is narrowly isolated and read back
Only the separately owner-authorized acceptance run may create or mutate live Google test objects, limited to this run's uniquely-prefixed synthetic event and task. It MUST use the actual app UI and adapter, keep exact IDs in a private local ledger, and GET the exact object before every mutation and again afterward before accepting the result. This run is separately authorized to create, edit, complete, reopen, read back, and delete only its own synthetic objects. Normal automated tests remain fixture-only. Unrelated resources, invitations, attendees, email, existing user data, and broad cleanup are excluded.

#### Scenario: Create a synthetic event
- **WHEN** the approved test workflow creates an event with `[g-calendar TEST <run-id>]` in the confirmed writable calendar
- **THEN** the app sends no attendees, sets `sendUpdates=none` when supported, captures only the returned resource ID privately, and reads back that exact event before recording success

#### Scenario: Verify a synthetic object lifecycle
- **WHEN** the authorized acceptance run edits, completes, reopens, or deletes one of its own synthetic objects
- **THEN** the app first GETs that exact ledger ID and verifies the unique marker, sends one explicit UI-triggered operation, then GETs that exact ID again and verifies the requested result; deletion is issued only for that verified ID

#### Scenario: Restrict live operation set
- **WHEN** the authorized acceptance run is exercised
- **THEN** it may operate only on this run's recorded synthetic event and task; all other Google mutations remain fixture-only

#### Scenario: Avoid duplicate test writes
- **WHEN** the workflow starts or resumes a run
- **THEN** it checks the private run ledger and exact test marker/ID before any subsequent write and never broad-cleans by title/prefix
