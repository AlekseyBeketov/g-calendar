# Repository instructions

## Package Manager
- This is a native SwiftUI/AppKit macOS app; no package-manager workflow is required.
- Use `./scripts/build-app.sh` and `./scripts/test.sh` for the project build and invariant suite.

## Commit Attribution
- Repository scope: `/Users/alexbeketov/g-calendar` only.
- The owner requests a separate Git commit for each verified logical product change.
- Stage explicit paths, review the staged diff, and commit only after relevant checks pass.
- Do not push, publish, rewrite history, or include local caches, credentials, personal data, `.codegraph/`, `.hermes/`, `dist/`, or `.DS_Store`.

## Key Conventions
- Preserve native macOS/SwiftUI interaction and accessibility.
- Keep Google mutations explicit, narrowly scoped, and read-back verified; tests use synthetic fixtures.
- Keep Calendar Tasks due dates date-only; local reminders are device-local.
- Treat `.hermes/plans/` as local planning artifacts, not repository content.
- Do not trust historical status/audit notes without checking their date and current source.

## Local Skills
- Follow the active Hermes `coder` profile skills when relevant; do not copy profile skill content into this repository.
- For structured product changes, use the repository's OpenSpec change at `openspec/changes/g-calendar-mvp/` when the installed CLI is available.
