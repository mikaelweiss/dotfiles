# [001] Otto core loop: spec-ready issue to PR

## Objective
A single Python program (`otto.py`) that, on each poll, picks the highest-priority ready leaf issue from a GitHub repo, drives it through the existing `/implement` and `/review` skills run as `claude -p` subprocesses, and opens a pull request for human review — using GitHub labels as the only state store.

## Context
- **Source of truth is GitHub.** otto.py holds no durable local state; it derives everything from `gh` each cycle — so the process can restart freely and laptop/Mac-Mini stay coordinated through GitHub.
- **Orchestration is plain Python over `claude -p` subprocesses, never the Agent/sub-agent tooling** — the sub-agent/Task machinery has been unreliable (fails to spawn, mis-steers). Each model step is an independent OS process.
- **The skills are reused unchanged.** `/implement <file>` reads a spec file, implements, runs tests, and leaves changes uncommitted (`claude/.claude/skills/implement/SKILL.md:48-65`). `/review <file>` reviews the uncommitted diff against the spec (`claude/.claude/skills/review/SKILL.md`). otto.py bridges a GitHub issue body into a scratch spec file so these file-based skills need no change.
- **Verdict line:** the review skill does not emit a machine-readable verdict on its own; otto.py's review prompt appends the instruction to end with exactly `VERDICT: CLEAN` or `VERDICT: ISSUES`, mirroring how the retired orchestrate skill drove review agents.
- **Within-issue fix context** is preserved by capturing the implement session id from `claude -p --output-format json` (`.session_id`) and resuming it (`claude -p --resume <id>`) for fix rounds; each `/review` is a fresh process. The `--resume` / `--output-format json` contract is documented at code.claude.com/docs/cli-reference.
- **Target repo** for first use is `MikaelWeiss/strive`; otto.py is repo-agnostic and reads the repo and paths from config.
- `gh` 2.94.0 returns `number,title,labels,blockedBy,subIssues,subIssuesSummary,parent,body` from `gh issue list --json`; native priority is NOT returnable, so priority is read from a `priority:N` label.
- Git isolation uses one worktree per issue (`git worktree add`) so the base checkout stays clean.

## Requirements
1. otto.py loads settings from a sibling `otto/config.toml`: `repo`, `clone_path`, `worktree_root`, `default_branch`, `branch_prefix`, `poll_seconds`, `max_fix_rounds`, `step_timeout_s`, `claude_bin` — config-driven so the same script serves any repo.
2. Each cycle, otto.py selects the next issue: open, labeled `status:spec-ready`, no sub-issues (a leaf), no open blockers (every `blockedBy` is closed), highest `priority:N` (lowest number wins), via a single `gh issue list --json` call — one call because all needed fields are returnable.
3. When no issue qualifies, otto.py logs an idle message, sleeps `poll_seconds`, and repeats. The process never exits on its own — restart is the supervisor's job, not the loop's.
4. Before working an issue, otto.py claims it: add `status:in-progress`, remove `status:spec-ready`, assign the authenticated user — the label swap is the lock against re-picking.
5. otto.py creates a worktree at `worktree_root/iss-<n>` on a new branch `<branch_prefix>iss-<n>` based on `default_branch`.
6. otto.py writes the issue body to a gitignored scratch spec file inside the worktree and runs `claude -p "/implement <scratch>"` with `--output-format json`, capturing the returned `session_id` — the bridge that lets the unchanged file-based skill consume a GitHub issue.
7. otto.py runs a review loop up to `max_fix_rounds`: each pass runs a fresh `claude -p "/review <scratch>"` whose prompt ends with the instruction to emit exactly `VERDICT: CLEAN` or `VERDICT: ISSUES`; on `ISSUES`, otto.py resumes the implement session (`claude -p --resume <session_id>`) with the verbatim findings and the instruction to fix and leave uncommitted; on `CLEAN`, the loop ends — findings are forwarded verbatim because otto.py never triages them.
8. Every model invocation is a `claude -p` subprocess; otto.py contains no Agent, Task, or SendMessage calls — enforced by the fact that the only model calls in the file are `subprocess` invocations of `claude_bin`.
9. After a `CLEAN` review (or exhausting `max_fix_rounds`), otto.py commits all worktree changes with a conventional message derived from the issue title, pushes the branch, and opens a PR via `gh pr create` whose body contains `Closes #<n>` — so merging closes the issue.
10. After opening the PR, otto.py relabels the issue: remove `status:in-progress`, add `status:in-review`, keep it assigned.
11. Each `claude -p` step runs under a wall-clock timeout of `step_timeout_s`; on timeout otto.py kills the process and routes the issue to failure handling — bounds a stuck step.
12. Failure handling (any step raises, a subprocess exits non-zero after one retry, or a step times out): remove `status:in-progress`, add `status:needs-human`, comment a failure summary on the issue, remove the worktree, continue to the next cycle — fail safe, never block the queue. Any commits made stay on the branch for inspection.
13. otto.py appends structured progress lines to stdout (launchd routes these to a log file): issue number, step, pass number, verdict, outcome.
14. No AI attribution appears in any commit message, PR body, or issue comment otto.py creates — the repo enforces a no-attribution policy. Enforced by: otto.py's message templates contain no `Co-Authored-By`, `Generated with`, or AI-assisted text, and pass only issue-derived content.

## Files
- `otto/otto.py` — Create. The polling loop, GitHub/git/claude subprocess plumbing, the issue→scratch bridge, claim/relabel transitions, the implement→review fix loop, and failure handling for leaf issues.
- `otto/config.toml` — Create. The settings in Requirement 1, populated for `MikaelWeiss/strive`.

## Test expectations
- One open issue labeled `status:spec-ready`, no sub-issues, no blockers → otto.py implements it, opens a PR containing `Closes #<n>`, issue ends labeled `status:in-review`.
- Two qualifying issues `priority:1` and `priority:3` → the `priority:1` issue is worked first.
- An issue whose `blockedBy` includes an open issue → not picked.
- A `/review` returning `ISSUES`, `ISSUES`, `CLEAN` → one implement session, three review passes, two fix resumes, then commit.
- A `/review` returning `ISSUES` every pass → stops after `max_fix_rounds` passes, still commits and opens the PR.
- An implement step exceeding `step_timeout_s` → issue ends `status:needs-human` with a failure comment and no PR.
- No qualifying issue → logs idle and sleeps without changing any issue.

## Boundaries
- Does NOT process issues that have sub-issues — it handles leaf issues only; feature traversal is a separate concern.
- Does NOT build, run, or screenshot the app — review is static at this layer.
- Does NOT merge PRs — merging is always manual.
- Does NOT read or respond to issue/PR comments.
- Does NOT hold more than one issue in flight per cycle.
- Does NOT create labels — it assumes the `status:` and `priority:` labels already exist.
- Does NOT use the Agent tool, sub-agents, SendMessage, or the Task system anywhere.
