# [003] Core loop: spec-ready issue to pull request

## Objective
Extend `otto/otto.py` with the implementation pipeline: each cycle, pick the highest-priority spec-ready issue without sub-issues, drive it through the implement and review skills in a dedicated worktree, and open a pull request for human review.

## Context
- **Source of truth is GitHub.** Otto holds no durable local state for this pipeline; everything derives from `gh` each cycle, so the process restarts freely and the laptop and Mac Mini coordinate through GitHub.
- **The skills are reused unchanged.** `/implement <file>` reads a spec file, implements, runs tests, and leaves changes uncommitted (`claude/.claude/skills/implement/SKILL.md:44-51` — the skill forbids committing; otto owns git). `/review <file>` reviews the uncommitted diff against the spec. Both take absolute paths, which is what makes the issue→file bridge work.
- **Spec extraction:** the spec is the issue-body text following the `<!-- otto:spec -->` marker. Otto writes it to `data_dir/specs/iss-<n>.md` — outside the worktree, so nothing needs gitignoring — and passes that path to the skills.
- **Verdict line:** the review skill emits no machine-readable verdict, so otto appends to the review prompt: "End your final message with exactly `VERDICT: CLEAN` or `VERDICT: ISSUES` on its own line." That appended sentence is the enforcement point for parseable review outcomes.
- **Within-issue fix context** is preserved by capturing the implement run's `.session_id` (`claude -p --output-format json`) and resuming it (`claude -p --resume <id>`) for fix rounds; each review is a fresh process so it judges the diff cold.
- **Worktree placement follows the worktrunk template** `~/.worktrees/{{ repo }}/{{ branch | sanitize }}` (`terminal/.config/worktrunk/config.toml:46`, sanitize: `/` and `\` become `-`). Mutagen syncs `~/.worktrees` between the Mac Mini and the laptop (`wolf-sync.md`), so `wt switch <branch>` on the laptop opens otto's worktree with all uncommitted state — the operator's test loop. Cross-machine worktrees require the main clone to live under `~/code` (`wolf-sync.md:33-34`), which `clone_path` satisfies.
- **The worktree stays after the PR opens** — it is the operator's synced test environment and the workspace for revision rounds. Only the failure path removes it.
- **Priority is a label**, `priority:N`, because `gh issue list --json` cannot return GitHub's native priority field. Lower N wins; an unlabeled issue sorts after `priority:4`; ties go to the lower issue number (oldest first) — unlabeled work still gets done without the operator labeling everything.
- Every `claude` invocation passes `--dangerously-skip-permissions` (headless runs cannot answer prompts) and runs with its working directory inside the worktree so the skills read and write the right checkout.

## Requirements
1. Selection: open issues labeled `status:spec-ready`, no parent, zero sub-issues, whose spec marker is present in the body, and whose `blockedBy` issues are all closed; order by `priority:N` ascending with unlabeled last, then by issue number ascending. At most one issue enters implementation per cycle.
2. Claiming: swap `status:spec-ready` → `status:in-progress` and assign the authenticated user — the label swap is the lock against re-picking from either machine.
3. Otto fetches and fast-forwards `default_branch` in `clone_path`, then creates a worktree via `git worktree add` at `worktree_root/<sanitized-branch>` on a new branch `<branch_prefix>iss-<n>` based on `default_branch` — the path matches what `wt switch` computes so the laptop finds it.
4. Otto writes the issue's spec section to `data_dir/specs/iss-<n>.md` and runs `claude -p "/implement <that path>"` in the worktree with `--output-format json`, capturing the session id.
5. Review loop, up to `max_fix_rounds` passes: each pass runs a fresh `claude -p "/review <spec path>"` in the worktree with the verdict-line instruction appended; on `VERDICT: ISSUES` otto resumes the implement session with the findings verbatim plus the instruction to fix them and leave changes uncommitted — findings are forwarded untriaged because otto never judges code; on `VERDICT: CLEAN` the loop ends.
6. After a clean review or exhausted rounds, otto commits all worktree changes with a conventional-prefix message derived from the issue title, pushes the branch, and opens a PR via `gh pr create` whose body contains `Closes #<n>` — merging closes the issue.
7. After the PR opens, otto swaps `status:in-progress` → `status:in-review`; the issue stays assigned and the worktree stays in place.
8. Every `claude` step runs under a `step_timeout_s` wall-clock timeout; on timeout otto kills the process tree and routes the issue to failure handling.
9. Failure handling (a step raises, a subprocess exits non-zero after one retry, or a timeout): remove `status:in-progress`, add `status:needs-human`, comment a failure summary on the issue, remove the worktree and its branch, continue to the next cycle — fail safe, never block the queue. Any commits already pushed stay on the remote branch for inspection.
10. Structured stdout lines per step: issue number, step name, pass number, verdict, outcome.
11. No commit message, branch name, PR body, or comment otto creates contains AI attribution — enforced by the templates in `otto.py` containing no attribution text.
12. `otto/config.toml` gains `worktree_root`, `branch_prefix`, `max_fix_rounds`.

## Files
- `otto/otto.py` — Modify. Add selection, claiming, worktree creation, the spec-file bridge, the implement→review→fix loop, commit/push/PR, relabeling, and failure handling.
- `otto/config.toml` — Modify. Add `worktree_root = "/Users/mikaelweiss/.worktrees/strive"`, `branch_prefix = "otto/"`, `max_fix_rounds = 3`.

## Test expectations
- One spec-ready leaf issue → implemented in `~/.worktrees/strive/otto-iss-<n>`, PR opened containing `Closes #<n>`, issue ends `status:in-review`, worktree still present.
- Two qualifying issues labeled `priority:1` and `priority:3` → the `priority:1` issue is worked first; an unlabeled third issue is worked last.
- An issue whose `blockedBy` includes an open issue → not picked.
- Reviews returning `ISSUES`, `ISSUES`, `CLEAN` → one implement session, three review passes, two fix resumes, then one commit and a PR.
- Reviews returning `ISSUES` every pass → stops after `max_fix_rounds`, still commits and opens the PR — the human reviewer sees the residue rather than the work vanishing.
- An implement step exceeding `step_timeout_s` → `status:needs-human`, failure comment, no PR, worktree removed.
- No qualifying issue → an idle log line and a sleep, nothing labeled.

## Boundaries
- Does NOT process issues that have sub-issues — leaf issues only.
- Does NOT build, run, or screenshot the app — review at this layer is static.
- Does NOT merge PRs — merging is always the operator's act.
- Does NOT read or respond to issue or PR comments.
- Does NOT remove the worktree after opening a PR — the synced copy is the operator's test environment.
- Does NOT hold more than one issue in flight per cycle.
- Does NOT create labels — it assumes the `status:` and `priority:` labels exist.
- Does NOT use the Agent tool, sub-agents, or the Task system — the only model calls are subprocess invocations of `claude_bin`.
