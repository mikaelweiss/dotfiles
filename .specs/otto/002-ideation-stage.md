# [002] Ideation stage: AI Ready issue to spec-in-issue

## Objective
Create `otto/otto.py` with its polling loop and the ideation stage: when the operator labels an issue `AI Ready`, otto runs the ideate skill headlessly against the repo, relays any genuine questions through the issue's Slack thread, and writes the finished spec into the issue (or into sub-issues for multi-unit work), labeling it `status:spec-ready`.

## Context
- **The operator's only action is the `AI Ready` label** (already exists in MikaelWeiss/strive, green `#4cb782` — see issue #479 for the intake shape: a rough idea plus research notes). Ideation starts on the next poll after labeling and runs regardless of how much other otto work exists — specs can sit ready indefinitely, so thinking is never queued behind implementation, which is bounded separately by human review capacity.
- **No approval gate.** The pull request is where the operator reviews otto's work; a spec produced without questions proceeds silently. Questions are asked only when research cannot settle an answer — the operator chose this so small well-described issues flow through with zero interaction.
- **The ideate skill is reused unchanged** (`claude/.claude/skills/ideate/SKILL.md`, stow-linked to `~/.claude/skills`). It normally writes `.specs/*.md` files and asks questions interactively; otto overrides both behaviors with layered prompt instructions (the technique that adds a verdict line to review runs), so the skill keeps working file-based for the operator's manual sessions.
- **Exact layered prompt** (the enforcement point for "research first, ask only when stuck" and for machine-readable output):

  ```
  /ideate for GitHub issue #<n> of <repo>.

  <issue title, body, and all issue comments inlined>

  Overrides for this run:
  - Do NOT write any files. Deliver spec content only in your final message, in the format below.
  - Research first: read this repository and search the web to answer your own questions. Ask the operator only what genuinely requires their judgment — product/UX preference, scope tradeoffs, constraints you cannot discover.
  - If questions remain after research, end your final message with a line reading exactly OTTO_QUESTIONS followed by a numbered list of the questions, nothing after the list.
  - When the spec is settled, end your final message with a line reading exactly OTTO_SPEC followed by one fenced json block: {"overview": "<markdown feature overview>", "units": [{"title": "<issue title>", "spec": "<full markdown spec with Objective, Context, Requirements, Files, Test expectations, Boundaries>", "depends_on": [<zero-based indexes of units this unit builds on>]}]}. A single-unit decomposition has exactly one entry in units.
  ```
- **Session resume carries Q&A context:** `claude -p --output-format json` returns `.session_id`; `claude -p --resume <id>` continues that session. Sessions persist on the Mac Mini's disk, so a parked ideation survives process restarts. The id is persisted on the issue as `<!-- otto:ideate-session:<id> -->` so restarts can resume from GitHub state alone.
- **Every `claude` invocation passes `--dangerously-skip-permissions`** — a headless subprocess cannot answer permission prompts.
- **Spec-in-issue format:** `<!-- otto:spec -->` followed by a `## Otto Spec` heading, appended below the operator's original text. The invisible marker makes extraction exact; the heading makes the spec readable on GitHub.
- **`gh` 2.96.0 has native sub-issue and dependency flags** (verified): `gh issue create --parent <n>`, `gh issue edit <a> --add-blocked-by <b>`; `gh issue list --json` returns `parent`, `subIssues`, `blockedBy`.
- **Orchestration is plain Python over `claude` subprocesses** — no Agent/sub-agent/Task tooling anywhere; that machinery has been unreliable, and deterministic control flow belongs in code.
- **Slack polling budget:** at most one `conversations.replies` call per cycle, round-robin across parked issues — Slack throttles non-Marketplace apps to ~1/min on that method, and answers arrive on human timescales anyway.
- Labels are the whole state machine. Otto owns `status:*`; `AI Ready` belongs to the operator and otto never removes it.

## Requirements
1. `otto/otto.py` is a single-process polling loop: each cycle runs the ideation passes below, logs, sleeps `poll_seconds`, repeats, and never exits on its own — restart is the supervisor's job. Config loads via `tomllib` from the sibling `otto/config.toml`; only the Python standard library is used.
2. `otto/config.toml` gains `clone_path`, `default_branch`, `poll_seconds`, `step_timeout_s`, `claude_bin` — machine- and repo-specific values stay out of the code.
3. Ideation eligibility: open issues labeled `AI Ready`, with no `status:*` label and no parent issue — top-level ideas only, discovered via `gh issue list --json`.
4. Otto starts at most one new ideation per cycle, lowest issue number first — bounds cycle length so reply handling and other passes are never starved by a burst of new ideas.
5. Claiming: add `status:ideating` before invoking the model — the label is the lock against double-processing and the crash marker.
6. Before invoking, otto fetches and fast-forwards `default_branch` in `clone_path` — ideation reads current code.
7. The invocation is `claude -p` run in `clone_path` with the layered prompt above, `--output-format json`, `--dangerously-skip-permissions`, killed after `step_timeout_s`; the returned `session_id` is captured.
8. `OTTO_QUESTIONS` outcome: otto posts the numbered questions verbatim to the issue's Slack thread, appends `<!-- otto:ideate-session:<id> -->` to the issue body, and swaps `status:ideating` → `status:awaiting-answers`.
9. Reply handling: each cycle otto polls at most one `status:awaiting-answers` issue's thread, round-robin. Operator messages newer than otto's last post in that thread are fed verbatim into `claude -p --resume <session_id>` together with the same override rules; the outcome is parsed identically — further questions repeat the parked flow with the new session id, a spec proceeds as below.
10. `OTTO_SPEC` outcome with one unit: append `<!-- otto:spec -->` + `## Otto Spec` + the unit's spec markdown to the issue body (operator text preserved above), then swap the `status:*` label to `status:spec-ready`.
11. `OTTO_SPEC` outcome with multiple units: create one sub-issue per unit via `gh issue create --parent <n>` whose body is `<!-- otto:spec -->` + `## Otto Spec` + the unit's spec; wire `depends_on` via `gh issue edit --add-blocked-by`; append the overview to the parent body under the spec marker; label only the parent `status:spec-ready` — sub-issues carry no status labels because the parent is the unit of state.
12. If a Slack thread exists for the issue (questions were asked), otto posts one closing reply linking the updated issue when the spec lands — the operator learns their answers resolved it; issues that never needed questions get no Slack message at all, because silence is the success path.
13. Failure handling (subprocess non-zero after one retry, timeout, or output missing both sentinels): remove otto's `status:*` labels, add `status:needs-human`, comment a failure summary on the issue, and post one line to the issue's Slack thread, creating it if needed — an ideation otto cannot finish is exactly the "can't decide alone" case that warrants a message.
14. Startup reconciliation: an issue labeled `status:ideating` at process start crashed mid-run — remove the label so it becomes eligible again; this is safe because nothing durable is written before the spec lands. If such an issue already has sub-issues containing the spec marker but never reached `status:spec-ready` (a crash inside multi-unit creation), route it to `status:needs-human` with a comment instead — re-running would duplicate sub-issues.
15. Cancellation: if an issue being ideated or awaiting answers is closed, or its `AI Ready` label is removed, otto removes its `status:*` labels and abandons the parked session — the operator withdrew the work.
16. Every cycle appends structured lines to stdout: issue number, pass, outcome — launchd routes stdout to a log file.
17. Nothing otto writes to GitHub or Slack contains AI attribution — enforced by the message and body templates in `otto.py` containing no attribution text.

## Files
- `otto/otto.py` — Create. The polling loop, ideation eligibility and claiming, the headless ideate invocation and sentinel parsing, Slack question relay and resume, spec-into-issue writing, sub-issue creation, failure handling, and startup reconciliation.
- `otto/config.toml` — Modify. Add `clone_path = "/Users/mikaelweiss/code/strive"`, `default_branch = "main"`, `poll_seconds = 60`, `step_timeout_s = 3600`, `claude_bin = "/Users/mikaelweiss/.local/bin/claude"`.

## Test expectations
- An `AI Ready` issue whose body already answers everything → spec section appended, `status:spec-ready`, zero Slack messages.
- An `AI Ready` issue with a genuine product ambiguity → numbered questions arrive in a new Slack thread, issue parked `status:awaiting-answers`; a thread reply → session resumed → spec appended → `status:spec-ready` → one closing thread message.
- A decomposition into three units where unit 2 depends on unit 1 → three sub-issues with spec bodies, a blocked-by relation from 2 to 1, parent overview appended, parent `status:spec-ready`.
- An ideation exceeding `step_timeout_s` → `status:needs-human`, a failure comment, one Slack line.
- Process killed mid-ideation → on restart the issue is re-ideated from scratch.
- Process killed after sub-issue creation but before `status:spec-ready` → parent routed to `status:needs-human`.
- `AI Ready` removed while parked → status labels cleared, no further action.
- Two new `AI Ready` issues in one cycle → only the lower-numbered one starts; the other starts next cycle.

## Boundaries
- Does NOT modify the ideate skill — manual file-based ideation keeps working everywhere.
- Does NOT wait for operator approval of a finished spec — the PR is the review point.
- Does NOT implement, build, or open PRs.
- Does NOT ideate sub-issues or any issue already carrying a `status:*` label.
- Does NOT remove or add the `AI Ready` label — it is operator-owned.
- Does NOT use the Agent tool, sub-agents, or the Task system — the only model calls are subprocess invocations of `claude_bin`.
