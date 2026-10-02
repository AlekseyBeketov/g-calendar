## ADDED Requirements

### Requirement: Task lists and tasks support focused daily workflows
The system MUST let the user select a Google task list and access list/column view, search, Today, Upcoming and Overdue filters. It MUST distinguish completion state and task list association.

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
- **WHEN** the window becomes too narrow for the status columns
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
