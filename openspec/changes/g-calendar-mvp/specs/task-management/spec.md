## ADDED Requirements

### Requirement: The default task list has readable density and predictable date order
The default list SHALL use readable title/date hierarchy and convenient independent completion/edit/menu targets without excessive card whitespace. Empty groups SHALL have a compact treatment while a wholly empty scope retains a clear empty state. Dated working views SHALL use ascending due date with a stable tie-breaker, without rewriting remote manual order; undated and completed tasks SHALL remain semantically separate.

#### Scenario: Show upcoming tasks in date order
- **WHEN** upcoming tasks arrive in a nonchronological API order
- **THEN** their local presentation is ordered by ascending date with a stable tie-breaker and no remote reordering mutation occurs

#### Scenario: Show a list with empty daily groups
- **WHEN** some groups are empty and another group contains tasks
- **THEN** empty groups use a compact treatment and active rows remain readily visible and operable

#### Scenario: Read and activate a long task row
- **WHEN** a task has a long title and the user uses completion, editing or its menu
- **THEN** the title remains readable and each independent target performs only its matching action

### Requirement: Task lists and tasks support focused daily workflows
The system MUST let the user select all boards or a Google task list and access list view, with column view available across all boards, search, Today, Upcoming and Overdue filters. It MUST distinguish completion state and task list association.

#### Scenario: Switch task list
- **WHEN** a user chooses a different task list
- **THEN** the task view displays only that selected list and preserves its selector state

#### Scenario: Filter current and overdue tasks
- **WHEN** the user selects Today or Overdue
- **THEN** tasks are filtered using their Google due date and the current local calendar date

#### Scenario: Search task content
- **WHEN** a search term is entered in the task workspace
- **THEN** matching tasks in the selected scope are shown and clearing the term restores the prior scope

#### Scenario: Clear search and show no-match state
- **WHEN** the user clears a search term or a query has no matching tasks
- **THEN** the clear action is reachable, the no-match state is distinguished from an empty list, and clearing restores the selected list/filter

#### Scenario: Narrow task workspace
- **WHEN** the window becomes too narrow for the board columns
- **THEN** the task workspace switches to a readable single-column presentation without requiring horizontal scrolling for primary actions

### Requirement: Task workflows are explicit and map to supported API fields
The system MUST support create/edit/delete and complete/uncomplete workflows where supported by the configured adapter. User edits remain drafts until saved and delete requires confirmation. Google due dates are represented as date-only; the system MUST NOT claim that Tasks API synchronizes a due time.

#### Scenario: Save a task without due-time extension
- **WHEN** the user saves a task with a Google due date
- **THEN** the adapter sends the date portion only and the app displays the task as date-only

#### Scenario: Set a local reminder time
- **WHEN** the user assigns a local reminder to a Google task
- **THEN** that reminder is stored separately from the Google task resource and labeled local-only

#### Scenario: Toggle completion
- **WHEN** the user explicitly completes or reopens a task
- **THEN** the corresponding supported adapter operation is initiated from the UI and the task state reflects confirmed result or error

#### Scenario: Confirm task deletion
- **WHEN** the user confirms task deletion
- **THEN** one matching delete operation is initiated; cancelling the confirmation issues no mutation

### Requirement: Offline task state is not fabricated
The system MUST show cached task content and freshness when available but MUST NOT represent unsaved offline edits as pending or synchronized unless a durable offline write queue has been implemented.

#### Scenario: Open tasks without network
- **WHEN** remote refresh fails and a prior task snapshot exists
- **THEN** the cached snapshot remains available with a stale/offline indicator and last successful refresh time

#### Scenario: Offline edit without write queue
- **WHEN** a user attempts a task mutation while the app cannot reach Google and there is no offline queue
- **THEN** the save is rejected or remains an explicitly unsaved draft; it is not reported as queued/saved

#### Scenario: Mutation fails after Save
- **WHEN** a Google task/list mutation fails
- **THEN** the editor remains open with its draft intact and a useful inline error is accessible, while the last-known-good snapshot remains available

### Requirement: Task filters use consistent date-only semantics
Task filters MUST use the current local calendar date and Google's date-only due field. Today contains tasks due today. Upcoming contains tasks due strictly after today. Overdue contains incomplete tasks due before today. Without due contains tasks with no Google due date. The same predicates MUST be used by the task list, groups, and calendar task visibility.

#### Scenario: Separate today's tasks from upcoming tasks
- **WHEN** a task is due today
- **THEN** it appears in Today and is excluded from Upcoming

#### Scenario: Show only future dates in Upcoming
- **WHEN** a task is due after the current local date
- **THEN** it appears in Upcoming and not in Today or Overdue

#### Scenario: Show undated tasks separately
- **WHEN** a task has no Google due date
- **THEN** it appears only in the Without due filter or timeless calendar region, never in Upcoming

### Requirement: Task list is the default presentation and columns are explicit
The task workspace MUST default to a vertical list. Users MUST be able to explicitly switch to board columns and back while all boards are selected without losing the filter. A specific board MUST always use list presentation. When the available detail width is too small for readable columns, the column mode MUST fall back to one vertical column while preserving the selected mode and task actions.

#### Scenario: Open the task workspace
- **WHEN** the user opens Tasks without a saved view preference
- **THEN** tasks appear in the list presentation

#### Scenario: Switch task presentation
- **WHEN** the user switches between list and columns
- **THEN** the selected task list and filter remain unchanged

#### Scenario: Resize columns to a narrow workspace
- **WHEN** the user narrows the detail area while columns are selected
- **THEN** the same groups and actions remain reachable in a single vertical column

### Requirement: All-board task scope and board columns
The task workspace MUST default to all boards, preserve that scope during refresh, and offer explicit individual board selection. Columns MUST be available only for all boards and group tasks by board, applying search and filters consistently. Columns MUST NOT overlap or truncate action reachability.

#### Scenario: Select columns across boards
- **WHEN** All boards is selected and the user chooses columns
- **THEN** Each board gets a readable column with its own tasks; selecting one board shows a list

### Requirement: Native verified cross-board move
Editing a task MUST allow selecting a destination board. Moves MUST use tasks.move destinationTasklist and confirm destination membership and source absence using exact reads; uncertain results MUST remain recoverable without repeated writes.

#### Scenario: Move task while editing
- **WHEN** The user saves edited fields and a different board
- **THEN** The fields and move are separately verified; the editor tracks the confirmed identity and local metadata remains attached

#### Scenario: Preserve local data when Google changes task identity
- **WHEN** a verified move returns a different task ID
- **THEN** local reminder and favorite metadata are persisted under the destination ID before the recovery journal is released
- **AND** a local persistence failure keeps the journal for read-only recheck; the old notification is cancelled before removing source metadata

#### Scenario: Refresh while move verification is pending
- **WHEN** a refresh no longer finds the source task while its move journal remains unresolved
- **THEN** reconciliation preserves the source local metadata until exact move verification persists the destination metadata
- **AND** unrelated confirmed deletions continue to reconcile normally
