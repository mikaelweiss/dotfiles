# [002] Feature decomposition: walk sub-issues into one PR

## Objective
Extend otto.py to handle issues that decompose into sub-issues: implement each sub-issue in dependency order on a single shared feature branch, then open one pull request for the whole feature.

## Context
- **The review unit is the parent feature, not the individual sub-issue** — human review time is the constraint, and reviewing a coherent feature at once is cheaper than many fragments. Per-sub-issue review still runs as an internal quality gate.
- **Sub-issues express order through `blockedBy` relations among themselves, not through nesting**; nesting only means "part of." otto.py sequences sub-issues in topological order of `blockedBy`.
- `gh` 2.94.0 returns `subIssues`/`subIssuesSummary` on the parent and `blockedBy` on each sub-issue, so hierarchy and order come from `gh issue list --json` / `gh issue view --json`.
- Each sub-issue's spec lives in its own issue body; the parent body is the feature overview. otto.py bridges each sub-issue body to its own scratch spec.
- Builds on the existing per-unit implement→review→commit logic in `otto/otto.py`.

## Requirements
1. Issue selection includes top-level issues (no `parent`) labeled `status:spec-ready` with no open blockers, choosing the highest `priority:N`. A selected top-level issue with sub-issues is processed as a feature; one without is processed as a leaf (existing behavior).
2. For a feature, otto.py creates one worktree and one branch `<branch_prefix>iss-<n>` for the parent and processes its open sub-issues in `blockedBy` topological order — one branch so the whole feature becomes one PR.
3. otto.py skips already-closed sub-issues and does not start a sub-issue whose `blockedBy` set still has an open sub-issue — respects intra-feature order.
4. Each sub-issue runs the same implement→review fix loop as a leaf issue, and otto.py commits once per sub-issue with a message derived from the sub-issue title — one commit per sub-issue for reviewable granularity on the branch.
5. otto.py claims the parent (`status:in-progress`) for the duration; after all sub-issues are committed it opens one PR for the branch whose body contains `Closes #<sub-n>` for every completed sub-issue and references the parent `#<n>` — so merging closes each sub-issue.
6. After the PR opens, otto.py relabels the parent to `status:in-review`.
7. If any sub-issue fails (per existing failure handling), otto.py stops the feature, labels the parent `status:needs-human` with a comment naming the failed sub-issue, leaves committed sub-issues on the branch, and removes the worktree — partial progress preserved for inspection.

## Files
- `otto/otto.py` — Modify. Add feature/sub-issue selection and topological traversal around the existing per-unit implement→review→commit logic; change PR creation to one-per-feature.

## Test expectations
- A parent with three sub-issues in a linear `blockedBy` chain → implemented in chain order, three commits on one branch, one PR closing all three sub-issues and referencing the parent.
- A parent whose second sub-issue's implement step times out → no PR, parent labeled `status:needs-human` naming that sub-issue, the first sub-issue's commit remains on the branch.
- A top-level issue with no sub-issues → processed as a single unit, one PR (unchanged leaf behavior).
- A parent with one closed sub-issue and two open → only the two open sub-issues are implemented.

## Boundaries
- Does NOT process multiple features concurrently — one feature per cycle.
- Does NOT open a separate PR per sub-issue — a feature yields exactly one PR.
- Does NOT re-open or modify closed sub-issues.
- Does NOT build, run, screenshot, or merge — those remain outside this layer.
