---
name: plan
description: Repo-aware planning procedure that replaces ad-hoc plan-mode exploration. Use when starting any non-trivial implementation task, when the user asks for a plan or invokes /plan, or on entering plan mode. Produces a lean plan with definition-of-done gates and failure-mode invariants before any code is written.
---

# Plan: discover deterministically, decide, commit

Plans fail in two ways: missing gates the repo documents somewhere, and missing failure modes nobody wrote down anywhere. This procedure buys both back for a few minutes of work. It drives the built-in plan machinery; it does not replace it.

## 1. Scope

Name the surfaces the task will touch: the apps/libs, the concrete files where known, the API boundaries crossed, and any state that persists beyond one request (database rows, stored blobs, caches, localStorage, feature flags).

## 2. Deterministic discovery (lookup, not wandering)

The goal is the documents that govern this change, found by lookup rather than archaeology. In order:

1. Run `python3 ~/.claude/hooks/rule-bridge.py --check <candidate paths>` from the repo root. Read every matched rule file in full.
2. If the repo has an instruction map or the root CLAUDE.md links binding standards docs for the touched surfaces, read the ones that apply.
3. Read the entry-point files that will change and their immediate callers.
4. Live-verify boundary facts instead of assuming them: what an endpoint actually returns (read the server code or call it), what a resource actually emits, what an existing helper actually does. A plan built on a wrong assumption fails at the cheapest possible point here and the most expensive point later.

Timebox this. When the matched docs and entry points are read, discovery is done; do not re-derive what the docs already state.

## 3. Definition of done

From the matched rules and docs, enumerate every gate that applies to the touched surfaces: lint, required test surfaces, contract/consumer-provider chains, QA or walkthrough docs, feature-flag lockstep files, manual checklists. Each becomes an acceptance criterion in the plan. Deliberately skipping a documented gate is a scope decision: write it as an explicit out-of-scope line for the user to see, never omit it silently.

## 4. Failure-mode pass

For every piece of persisted state, shared resource, or concurrent actor in the design, ask:

- What happens when the data is older than this code, newer than this code, partially corrupt, or absent?
- What happens when two actors (tabs, devices, users, requests) write at once?
- What happens when permissions, tenant, or selection context shift underneath a live view?
- What happens when the flow is interrupted halfway?

Write the chosen invariant for each as one sentence in the plan (for example: "a client that reads a document version it does not understand renders nothing and never writes"). Skipping a question because it genuinely cannot occur is fine; say so in a clause, not by silence.

## 5. Decisions

Genuine product or scope choices become `questions` in the brief: two to four short options, one recommended. Do not bury decisions inside the plan as assumptions, and do not ask them in chat.

## 6. The artifact: a brief

The plan is a brief, rendered as a page. Load the `brief` skill and follow its shape exactly.

1. Write `~/.claude/briefs/<repo>/<branch>/proposal.json`. One behavior line per behavior change, with the files it creates or edits. Gates from step 3 become the `test` on the line they pin. Invariants from step 4 go in that line's `detail`. Every file the plan will touch appears in `changed_files` and on a behavior line or a map node.
2. Render it and open it:

   ```bash
   node ~/.claude/skills/brief/render.mjs ~/.claude/briefs/<repo>/<branch>/proposal.json
   open ~/.claude/briefs/<repo>/<branch>/proposal.html
   ```

3. In chat, say only: the page is open, and the numbers of any lines that need a decision. Then stop.
4. The reply is the copied notes from the page. Anything not listed is approved. Apply the listed changes to the JSON, render again, and start on the work when nothing remains open.

If plan mode is on, the brief is the plan: call ExitPlanMode with the path and the open decisions, nothing more.
