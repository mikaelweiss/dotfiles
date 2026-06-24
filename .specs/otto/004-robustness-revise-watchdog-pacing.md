# [004] Robustness: revise-on-comment, watchdog, pacing, pause

## Objective
Make otto.py safe to run unattended 24/7: respond to the operator's PR/issue comments by making the requested change, recover from interrupted runs, bound how much unreviewed work piles up, and support a pause switch.

## Context
- **The operator reviews and steers from GitHub.** A new comment from the operator on a waiting PR or issue is a change request; otto.py resumes the work via `claude -p --from-pr <pr>`, which reattaches to the agent that built the PR with full context (sessions link to PRs the CLI opened, per code.claude.com/docs/cli-reference) — so changes are driven by commenting, no webhooks.
- **The orchestrator is the reliability layer only while attended.** These mechanisms keep an unattended run from spinning, flooding the review queue, or stranding a claimed issue after a crash or reboot.
- **A claimed issue (`status:in-progress`) with no open Otto PR is orphaned** — its `claude -p` died with the process. otto.py reconciles these on startup and each cycle.
- Builds on the loop, claim transitions, and PR flow already in `otto/otto.py`.

## Requirements
1. Each cycle, before picking new work, otto.py finds open PRs it created (labeled `status:in-review`) and parent issues labeled `status:needs-human` that carry a comment authored by the configured operator newer than otto.py's last action on that thread. For each, otto.py checks out the branch, runs `claude -p --from-pr <pr>` with the comment text as the instruction, then commits, pushes, and replies on the thread — the operator's comment drives the revision.
2. otto.py distinguishes operator comments from its own by author login and tracks "its last action" by the timestamp of its most recent comment on the thread — so it never reacts to its own messages.
3. On startup and each cycle, otto.py reconciles stale claims: any issue labeled `status:in-progress` with no open Otto PR is relabeled `status:needs-human` with an explanatory comment — recovers orphaned work after a crash or reboot.
4. config.toml gains `max_open_prs`. When the count of open Otto PRs awaiting review is at or above `max_open_prs`, otto.py starts no new work and logs that it is waiting on review — bounds unreviewed work at the constraint.
5. otto.py checks for a `PAUSED` sentinel file under the otto data dir each cycle; while it exists, otto.py starts no new work and performs no revisions, logging that it is paused — pause/resume without stopping the service.
6. If an issue otto.py is actively working is closed or loses `status:in-progress` externally, otto.py aborts the run, removes the worktree, and opens no PR — respects a human cancelling mid-run.

## Files
- `otto/otto.py` — Modify. Add the revise-on-comment pass, stale-claim reconciliation, the `max_open_prs` gate, the `PAUSED` sentinel check, and mid-run cancellation.
- `otto/config.toml` — Modify. Add `max_open_prs`.

## Test expectations
- A `status:in-review` PR with a new comment from the configured operator → otto.py makes a change on the branch, pushes, replies, and does not pick up a new issue that cycle.
- A comment authored by otto.py itself → no revision action.
- An issue labeled `status:in-progress` with no open Otto PR at startup → relabeled `status:needs-human`.
- `max_open_prs` open Otto PRs → no new issue started, logs waiting.
- A `PAUSED` sentinel file present → no new work and no revisions.
- An in-progress issue closed mid-run → no PR, worktree removed.

## Boundaries
- Does NOT act on comments from logins other than the configured operator — it is single-operator.
- Does NOT merge PRs.
- Does NOT use webhooks — it discovers comments by polling.
- Does NOT parallelize — `max_open_prs` pauses production rather than spawning concurrent work.
