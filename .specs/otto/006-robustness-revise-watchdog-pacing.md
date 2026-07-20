# [006] Robustness: PR revisions, watchdog, pacing, pause

## Objective
Make `otto/otto.py` safe to run unattended: revise PRs from the operator's GitHub feedback, escalate failures to Slack so they get seen, recover interrupted runs, bound how much unreviewed work piles up, clean up after merged PRs, and support a pause switch.

## Context
- **GitHub is where PRs get reviewed; Slack is where otto gets the operator's attention.** The operator reviews a PR in the GitHub UI and leaves feedback there — top-level comments, review bodies, and inline code comments all count, because real review feedback arrives as a review with line comments, not one tidy comment. Slack carries only outbound escalations (an issue's thread) so the operator notices without watching GitHub notifications.
- **`claude -p --from-pr <n>` resumes the session linked to a PR the CLI opened** (flag verified in claude 2.1.215) — revisions reattach to the agent that built the PR with full context of why the code is how it is.
- **Recovery from `status:needs-human` is label-driven, not comment-driven:** the operator fixes or clarifies, then relabels (`status:spec-ready` to re-queue implementation, or removes all `status:*` labels to re-ideate). Labels already are the state machine, and a non-PR issue has no session to resume, so comment parsing there would add a second, weaker control channel.
- **Otto identifies its own PRs** as open PRs whose head branch starts with `branch_prefix` — derivable from GitHub alone, no local registry.
- **A claimed issue (`status:in-progress`) with no open otto PR is orphaned** — its subprocess died with the process. Reconciled on startup and each cycle.
- **Worktrees outlive their PRs deliberately** (the operator tests in the synced copy), so their cleanup keys off PR closure. Removing a worktree on the Mac Mini does not fire worktrunk hooks, so a laptop tmux/herdr tab for that branch lingers; `wt hook post-remove` closes it manually (`wolf-sync.md:135`) and the operational README documents this.
- `max_open_prs` pauses production rather than parallelizing — the constraint is operator review capacity, and more concurrency would just deepen the unreviewed pile.

## Requirements
1. Each cycle, before starting new implementation, otto checks its open PRs for operator feedback: top-level PR comments, review bodies, and inline review comments authored by `operator_login`, newer than otto's most recent comment or reply on that PR. All new feedback for a PR is gathered into one revision run.
2. A revision run checks out the PR's branch in its worktree — recreating the worktree from the branch at the standard path if it is missing (a reboot or cleanup may have removed it) — then runs `claude -p --from-pr <n>` with the feedback verbatim, commits, pushes, and replies on the PR summarizing what changed. At most one revision run per cycle, and revisions take precedence over starting new work — feedback means the operator is actively waiting.
3. Otto distinguishes operator activity from its own by comment author login, and tracks "its last action" as the timestamp of its most recent comment or reply on that PR — so it never reacts to its own messages.
4. On startup and each cycle, any issue labeled `status:in-progress` with no open otto PR is relabeled `status:needs-human` with an explanatory comment — recovers work orphaned by a crash or reboot.
5. Every transition to `status:needs-human`, from any stage, posts a one-line summary to the issue's Slack thread (created if needed) naming the failure and the recovery move (fix, then relabel) — the operator watches Slack, and a silent failure label defeats the escalation.
6. When the count of open otto PRs is at or above `max_open_prs`, otto starts no new implementation and logs that it is waiting on review; revisions and ideation are unaffected — review capacity gates production, not thinking or feedback handling.
7. When otto detects one of its PRs is closed (merged or not), it removes that branch's worktree and local branch — the test environment is only needed while the PR lives.
8. While a `PAUSED` file exists in `data_dir`, otto performs nothing — no ideation, no Slack polls, no revisions, no new work — and logs that it is paused each cycle; deleting the file resumes on the next cycle. One switch, total stop, no supervisor involvement.
9. If the issue otto is actively implementing is closed or loses `status:in-progress` externally, otto aborts the run, removes the worktree, and opens no PR — a human cancelled mid-run.
10. `otto/config.toml` gains `max_open_prs` and `operator_login`.

## Files
- `otto/otto.py` — Modify. Add the revision pass, stale-claim reconciliation, the needs-human Slack escalation, the `max_open_prs` gate, closed-PR worktree cleanup, the `PAUSED` check, and mid-run cancellation.
- `otto/config.toml` — Modify. Add `max_open_prs = 3`, `operator_login = "mikaelweiss"`.

## Test expectations
- A review with two inline comments and a summary body on an otto PR → one revision run receives all three, new commits appear on the PR, otto replies once.
- A comment authored by otto itself → no revision.
- `status:in-progress` with no open otto PR at startup → `status:needs-human`, explanatory comment, one Slack line in the issue's thread.
- Three open otto PRs → no new implementation starts, waiting logged; a new `AI Ready` issue still gets ideated that same cycle.
- An otto PR merged on GitHub → its worktree and local branch are gone within a cycle.
- `PAUSED` present → a pause log line and nothing else, including no Slack polling.
- The in-progress issue closed mid-run → no PR, worktree removed.
- A `status:needs-human` issue relabeled `status:spec-ready` by the operator → picked up as normal work on a later cycle.

## Boundaries
- Does NOT act on feedback from logins other than `operator_login` — single-operator by design.
- Does NOT merge PRs.
- Does NOT use webhooks — comments are discovered by polling.
- Does NOT parallelize implementation — the cap pauses production instead of spawning concurrent work.
- Does NOT close laptop tmux or herdr tabs when it removes a worktree — worktrunk hooks don't fire for git operations on the Mac Mini.
- Does NOT delete remote branches — GitHub's own delete-on-merge setting owns that.
