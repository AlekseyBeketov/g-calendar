# Repository instructions

## Package Manager
- This is a native SwiftUI/AppKit macOS app; no package-manager workflow is required.
- Use `./scripts/build-app.sh` and `./scripts/test.sh` for the project build and invariant suite.
- After completing an implementation session (one or several features/fixes), rebuild with `./scripts/build-app.sh` so `dist/g-calendar.app` contains the latest changes before handing off for manual UI testing. Report the resulting bundle path; do not claim UI verification from a successful build.
- Use computer-use for checks only when the user explicitly requests it.

## Releases
- For release packaging, follow `docs/RELEASING.md`: build the app, create and verify the DMG with the repository scripts, and report exact artifact paths and signing status.
- The owner has declined Apple Developer Program enrollment. Never describe an ad-hoc/local-preview DMG as notarized or Gatekeeper-ready; do not start Developer ID signing or notarization unless the owner explicitly reverses this decision. Tagging or publication still requires an explicit release request.
- A DMG build is not a GitHub Release. Do not publish or upload release assets without explicit owner authorization.

## Commit Attribution
- Repository scope: `/Users/alexbeketov/g-calendar` only.
- The owner requests a separate Git commit for each verified logical product change.
- Stage explicit paths, review the staged diff, and commit only after relevant checks pass.
- Push to remote `main` is allowed when requested by the user. Do not publish releases, rewrite history, or include local caches, credentials, personal data, `.codegraph/`, `.hermes/`, `dist/`, or `.DS_Store`.

## Key Conventions
- Preserve native macOS/SwiftUI interaction and accessibility.
- Enabled action controls must show the pointing-hand cursor across their full click region, including clickable label padding. Use `.pointingHandCursor()` on SwiftUI actions before `.disabled(...)`; native action buttons use the window cursor bridge. Preserve I-beam for editable text, system menu behavior, and the native cursor for disabled controls and non-actionable areas. Do not change hit testing or accessibility to add a cursor.
- Keep Google mutations explicit, narrowly scoped, and read-back verified; tests use synthetic fixtures.
- Use bounded parallelism for independent operations whenever possible; respect API quotas, dependency ordering, and durable mutation recovery.
- Keep Calendar Tasks due dates date-only; local reminders are device-local.
- Treat `.hermes/plans/` as local planning artifacts, not repository content.
- Do not trust historical status/audit notes without checking their date and current source.

## Local Skills
- Follow the active Hermes `coder` profile skills when relevant; do not copy profile skill content into this repository.
- For structured product changes, use the repository's OpenSpec change at `openspec/changes/g-calendar-mvp/` when the installed CLI is available.

## Code Navigation
- Use `structural-code-search-v3` for retrieval and `code-indexing` for explicit index updates. This repository keeps derived caches in ignored `/.local-indexes/` by owner request.
- After important source commits, run `rtk proxy ./scripts/index-code.sh`; use `--force` after large renames/deletions, branch changes or index corruption. Indexing includes uncommitted source changes.
- Graph: `.local-indexes/graphify/graphify-out/graph.json`; text index: `.local-indexes/tgrep`; verified snapshot: `.local-indexes/manifest.json`.
- Run Graphify retrieval from `.local-indexes/`: `rtk proxy graphify query "symbol" --graph graphify/graphify-out/graph.json` (Graphify writes auxiliary caches in the current directory). From the repository root use `rtk proxy tgrep --index-path .local-indexes/tgrep "symbol" .`.
- Swift AST relationships are navigation hints; verify overloads, dynamic dispatch and SwiftUI result-builder behavior against current source. Retrieval never rebuilds indexes automatically.

## Engineering Boundaries

- Treat external API, file, config, and tool payloads as untrusted. Validate unknown values once at the boundary that owns them, then pass typed values inward; do not repeat checks guaranteed by a schema, constructor, or internal type. A cast or type assertion alone is not runtime validation. Keep authorization, security checks, and mutable business invariants enforced where required.
- Before adding speculative reliability or edge-case behavior, state the concrete failure mode, evidence or uncertainty about its likelihood, and complexity/maintenance cost, then get the user's approval. Do not invent probabilities. Track out-of-scope proposals as explicit pending decisions; no reply is not consent. Mandatory security controls are not optional.

## SwiftUI / AppKit Conventions

- Use concrete Swift structs, enums, and typed internal models; use `Codable` at serialization boundaries. Reserve `Any` and `[String: Any]` for justified Foundation/Google JSON boundaries, validate there, and convert to typed values before passing inward.
- Prefer `let` and `guard` for straightforward happy paths; use `var` for genuinely mutable state, including SwiftUI view state.
- Handle `throws` explicitly. Use `catch` only for meaningful recovery or error translation at a boundary; use `defer` for cleanup. Avoid `try?` unless the operation is intentionally best-effort and that intent is documented.
- Extract helpers only for real reuse or a meaningful domain/system boundary; avoid one-off wrappers.
- Extend the existing invariant tests to exercise production implementations with synthetic fixtures; use `./scripts/test.sh` and do not rely on live Google/provider calls for routine verification.
