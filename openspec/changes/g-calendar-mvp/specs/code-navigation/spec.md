## ADDED Requirements

### Requirement: Explicit local code indexing

The repository SHALL provide `scripts/index-code.sh` to incrementally update Graphify and tgrep caches under ignored `/.local-indexes/`. `--force` SHALL request a full rebuild. Indexing SHALL use current worktree contents, including uncommitted changes, and SHALL NOT call a semantic LLM or install automatic Git hooks.

#### Scenario: Successful explicit update
- **WHEN** the owner runs the indexing script after important source changes
- **THEN** Graphify runs with local code extraction, tgrep updates the same repository, and a manifest records the repository, Git snapshot, source fingerprint, tool versions and build time

#### Scenario: Verified readiness
- **WHEN** indexing completes
- **THEN** Graphify contains non-empty nodes and edges/links with repository source paths, tgrep metadata has the exact repository root and `complete: true`, and source contents remain unchanged during indexing

#### Scenario: Failure or concurrent source changes
- **WHEN** either tool fails, validation fails or source changes during indexing
- **THEN** the script exits unsuccessfully, does not publish a ready manifest and reports any partially completed tool output

### Requirement: Retrieval without implicit rebuild

Agents SHALL use existing readable indexes for navigation and verify results against current source. Ordinary retrieval SHALL NOT automatically rebuild an index. Swift AST edges SHALL be treated as navigation hints rather than compiler-level proof of overload resolution, dynamic dispatch or SwiftUI result-builder behavior.

#### Scenario: Important commit or disruptive change
- **WHEN** a meaningful source commit is complete
- **THEN** agents explicitly refresh indexes incrementally, using `--force` for major deletion/rename, branch changes or corruption
