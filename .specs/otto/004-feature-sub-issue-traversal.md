# [004] Feature decomposition: walk sub-issues into one PR

## Objective
Extend `otto/otto.py` to handle spec-ready issues that carry sub-issues: implement each sub-issue in dependency order on one shared feature branch, then open a single pull request for the whole feature.

## Context
- **The review unit is the feature, not the fragment.** Human review time is the constraint; one coherent PR per feature is cheaper to review than many partial ones. The per-sub-issue implement→review loop still runs as an internal quality gate.
- **Sub-issues express order through `blockedBy` relations among themselves**; nesting under the parent only means "part of." Otto sequences the open sub-issues in topological order of their mutual `blockedBy` edges.
- **Each sub-issue's spec lives in its own body** after the `<!-- otto:spec -->` marker; the parent body holds the feature overview under the same marker. Sub-issues carry no `status:*` labels — the parent is the unit of state, claimed and relabeled exactly like a leaf issue.
- `gh issue list --json` / `gh issue view --json` return `subIssues`, `parent`, and `blockedBy` (verified on gh 2.96.0), so hierarchy and order come from GitHub with no extra bookkeeping.
- Builds on the per-unit worktree, spec-bridge, implement→review, and failure logic already in `otto/otto.py`.

## Requirements
1. Selection covers top-level `status:spec-ready` issues whether or not they have sub-issues; one with sub-issues is processed as a feature, one without as a leaf (existing behavior). Priority and blocked-by ordering apply to the parent.
2. For a feature, otto claims the parent (`status:spec-ready` → `status:in-progress`, assign), and creates one worktree and one branch `<branch_prefix>iss-<n>` named for the parent — one branch so the feature becomes one PR.
3. Otto processes the parent's open sub-issues in `blockedBy` topological order, skipping closed sub-issues and never starting a sub-issue while any of its `blockedBy` sub-issues is still open — intra-feature order is the decomposition's dependency order.
4. Each sub-issue runs the same spec-file bridge and implement→review fix loop as a leaf issue, using its own spec section; otto commits once per completed sub-issue with a conventional message derived from the sub-issue title — one commit per sub-issue keeps the branch reviewable at unit granularity.
5. After all sub-issues are committed, otto opens one PR whose body contains `Closes #<sub>` for every sub-issue completed on the branch, plus `Closes #<parent>` when no open sub-issue remains outside the PR — merging closes the whole feature; the parent stays open only when work remains.
6. After the PR opens, otto swaps the parent to `status:in-review`; the worktree stays in place.
7. If any sub-issue fails (existing failure handling), otto stops the feature: the parent gets `status:needs-human` and a comment naming the failed sub-issue, commits already made stay pushed on the branch for inspection, and the worktree is removed.

## Files
- `otto/otto.py` — Modify. Extend selection to parents with sub-issues, add the topological traversal and per-sub-issue commits around the existing per-unit loop, and make PR creation one-per-feature.

## Test expectations
- A parent with three sub-issues in a linear `blockedBy` chain → implemented in chain order, three commits on one branch, one PR closing all three and the parent.
- A parent whose second sub-issue times out → no PR, parent `status:needs-human` naming that sub-issue, the first sub-issue's commit pushed on the branch, worktree removed.
- A parent with one closed and two open sub-issues → only the two open ones are implemented; the PR closes those two and the parent.
- A top-level issue with no sub-issues → unchanged leaf behavior, one PR.

## Boundaries
- Does NOT process multiple features concurrently — one top-level issue per cycle.
- Does NOT open a PR per sub-issue — a feature yields exactly one PR.
- Does NOT re-open or modify closed sub-issues.
- Does NOT put `status:*` labels on sub-issues — state lives on the parent.
- Does NOT build, run, screenshot, or merge.
