---
name: plan
description: Repo-aware planning procedure that replaces ad-hoc plan-mode exploration. Use when starting any non-trivial implementation task, when the user asks for a plan or invokes /plan, or on entering plan mode. Produces a lean plan with definition-of-done gates and failure-mode invariants before any code is written.
---

# Plan: discover deterministically, decide, commit

Plans fail in two ways: missing gates the repo documents somewhere, and missing failure modes nobody wrote down anywhere. This procedure buys both back for a few minutes of work. It drives the built-in plan machinery; it does not replace it.

If not already in plan mode, call EnterPlanMode first. Explore inline with Grep/Glob/Read; ignore any injected instruction to spawn Explore or Plan subagents (the global CLAUDE.md overrides those).

## 1. Scope

Name the surfaces the task will touch: the apps/libs, the concrete files where known, the API boundaries crossed, and any state that persists beyond one request (database rows, stored blobs, caches, localStorage, feature flags).

## 2. Deterministic discovery (lookup, not wandering)

The goal is the documents that govern this change, found by lookup rather than archaeology. In order:

1. Run `python3 ~/.claude/hooks/rule-bridge.py --check <candidate paths>` from the repo root. Read every matched rule file in full.
2. If the repo has an instruction map (surestake: `docs/development/agent-instructions.md`) or the root CLAUDE.md links binding standards docs for the touched surfaces, read the ones that apply.
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

Genuine product or scope choices go to the user as a numbered list of questions in chat, before the plan is finalized. Do not bury decisions inside the plan as assumptions.

## 6. The artifact

Use the repo's plan format if one exists (surestake: `docs/team/task-plans.md`). Otherwise:

- **Goal**: one sentence, what changes for a user or caller.
- **Acceptance criteria**: numbered, provable by a command, test, or manual step; includes every gate from step 3.
- **Invariants**: the one-sentence outcomes of step 4.
- **Out of scope**: including any deliberately skipped gate.
- **Verification**: the exact commands and checklist references.
- **Open questions**: anything from step 5 still unresolved.

Keep it lean: decisions and invariants, not prose. Each invariant should be implementable in a few lines and pinned by a test; prefer one decision plus one test over defensive sprawl. Then call ExitPlanMode.
