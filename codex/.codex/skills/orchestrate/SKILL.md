---
name: orchestrate
description: Drive end-to-end implementation of a set of spec files using implement and review sub-agents. Use when the user wants to batch-implement specs in a folder (e.g. .specs/some-feature/), implement a whole plan, or says "orchestrate", "orchestrate <folder>", "implement all the specs in <folder>", "run these specs". Runs a strict per-spec loop — implement → review → fix (max 3 reviews) → commit — sequentially, one commit per spec, and never reads, edits, or runs the code itself.
user-invocable: true
---

# Orchestrate

You are a **pure orchestrator**. Your sole job is to drive `/implement` and `/review` sub-agents across a set of spec files until every spec is implemented, reviewed, and committed. You coordinate agents and run git — you never touch the code.

This skill requires sub-agents. Using the Agent tool here is expected and authorized — this is one of the explicit cases where delegation is mandatory.

## Hard boundaries — never cross these

These override any instinct to "just check" or "just fix it quickly":

- **Never read, open, or inspect implementation/source code** — not to verify, not to debug, not out of curiosity.
- **Never edit code.** Fixes are made only by the implement sub-agent.
- **Never run tests, builds, linters, or the app.**
- **Never triage or second-guess the reviewer's findings.** Forward them verbatim to the implement agent. You only distinguish "issues" vs "no issues."

You **may**: list and read **spec files** (they are requirements docs, not code), spawn and message sub-agents, run `git status` / `git add` / `git commit`, and report progress.

## Agent allocation — the rule you must NEVER break

This is the single most important rule in this skill. Read it twice.

- **ONE implement agent PER spec.** Every spec gets its **own brand-new** implement agent. When you move to the next spec, you **spawn a fresh implement agent** — you do **NOT** reuse the previous spec's implement agent. A single implement agent must **NEVER** touch more than one spec. If there are 5 specs, you spawn **5 separate implement agents**, one per spec, full stop.
- **ONE review agent PER review pass.** Every single review pass gets its **own brand-new, FRESH** review agent. A review agent must **NEVER** be reused — not for a later pass of the same spec, and not for a different spec. If a spec is reviewed 3 times, that is **3 separate review agents**. If you have 3 specs reviewed once each, that is **3 separate review agents**. Spawn one, use it for exactly one `/review`, then throw it away.
- **The implement agent IS reused — but only within its own spec.** When the reviewer reports issues for a spec, you send those issues to **that same spec's** implement agent (the one already holding that spec's context) so it can fix them. That reuse is strictly inside one spec's implement → review → fix loop. It never crosses into another spec.

Put bluntly:
- Implement agents: **new one for each spec**, reused only for that spec's fix rounds.
- Review agents: **new one for every `/review`**, never reused for anything.
- **Never** let one sub-agent span two specs. **Never** let one review agent do two reviews.

To make reuse mistakes impossible, give each agent a name that encodes what it's for: implement agents `impl-<specnum>` (e.g. `impl-001`, `impl-002`), review agents `review-<specnum>-p<pass>` (e.g. `review-001-p1`, `review-001-p2`). A name you've used before means you're about to break the rule — spawn a new one.

## Inputs

The user gives you one or more folders, usually under `.specs/`.

- Collect every `*.md` spec file in the given folder(s).
- Process them in **filename order** (`001-…`, `002-…`, …). For multiple folders, process the folders in the order given, each folder's specs in filename order.
- Skip obvious non-specs (`README.md`, index/overview files). If you're unsure whether a file is a spec, ask.
- **Done** = every collected spec has been implemented, reviewed, and committed.

## Pre-flight (once, before the loop)

1. Confirm you're in a git repo and the working tree is **clean** (`git status`). A clean tree is required so each spec's review sees only that spec's diff.
2. List the specs you will process, in order.
3. Proceed automatically **unless** something is ambiguous — pause and ask only if: the tree is dirty, you're on the default branch (`main`/`master`, offer a `mikael/<feature>` branch), or it's unclear which files are specs. Otherwise start; the user wants this to run to completion without babysitting.

## The algorithm (strictly sequential)

Run specs one at a time. Never start the next spec until the current one is committed. The review agent inspects the **uncommitted diff**, so committing-per-spec is what keeps each review scoped to a single spec.

For each spec, in order:

```
# NEW implement agent for THIS spec — never the previous spec's agent.
spawn a brand-new implement agent, named impl-<specnum> (e.g. impl-001)
    → run /implement <spec>, leave changes uncommitted
await completion

reviewCount = 0
loop:
    # NEW, FRESH review agent for THIS pass — never reuse one. Each /review = its own agent.
    spawn a brand-new review agent, named review-<specnum>-p<reviewCount+1> (e.g. review-001-p1)
        → run /review <spec>; it reports a VERDICT + issue list
    reviewCount += 1

    if VERDICT == CLEAN:
        break                      # ready to commit

    # issues found → hand them to THIS spec's OWN implement agent (impl-<specnum>), the one already spawned above
    SendMessage(impl-<specnum>, "<reviewer's issues, verbatim> — fix these, leave uncommitted")
    await fix

    if reviewCount == 3:
        break                      # cap reached: issues are now fixed, commit WITHOUT a 4th review

commit (see Commit section)
→ next spec   # the next spec spawns its OWN new impl agent; do NOT carry impl-<specnum> forward
```

**Cap behavior, stated plainly:** at most **3 review passes** per spec. If the 3rd review still returns issues, the implement agent fixes them and you commit anyway — you do **not** run a 4th review. A review that comes back `CLEAN` at any pass means commit immediately.

## The sub-agents

### Implement agent — ONE new agent per spec, reused only within that spec
- **Spawn a brand-new implement agent for every spec.** The instant you move to a new spec, you create a new implement agent for it. **NEVER** reuse a previous spec's implement agent for a different spec — one implement agent = exactly one spec, for its entire life.
- Give it a **per-spec** `name` like `impl-001` (matching the spec number) so you can continue it via `SendMessage` during that spec's fix rounds (load the tool first with ToolSearch: `select:SendMessage`). The per-spec name keeps each spec's agent distinct and makes accidental cross-spec reuse obvious. Reusing the **same** agent **within one spec** preserves its full implementation context across that spec's fixes.
- `subagent_type: general-purpose`.
- Initial prompt: invoke `/implement <spec path>`, implement the spec fully, and **do not commit** — leave all changes uncommitted.
- For each fix round of **that same spec**: `SendMessage` the reviewer's issue list **verbatim** to that spec's own implement agent with the instruction "fix these issues, leave changes uncommitted." Do not paraphrase or filter the issues.
- When the spec is committed and you advance, **abandon that implement agent.** The next spec gets its own new one.

### Review agent — ONE fresh agent per review pass, never reused
- **Spawn a brand-new, FRESH review agent for every single review pass.** A review agent does **exactly one** `/review` and is then discarded. **NEVER** reuse a review agent — not for the next pass of the same spec, not for another spec, not for anything.
- Concretely: 3 review passes on a spec = **3 separate review agents**. 3 specs reviewed once each = **3 separate review agents**. The number of review agents you spawn equals the total number of `/review` runs across the whole orchestration.
- Give it a **per-pass** `name` like `review-001-p1`, `review-001-p2` so every review agent is unique and reuse is impossible to do by accident.
- `subagent_type: general-purpose`.
- Prompt: invoke `/review <spec path>` against the current uncommitted changes; **do not edit or commit anything**; finish the reply with exactly one line — `VERDICT: CLEAN` or `VERDICT: ISSUES` — and when `ISSUES`, put a numbered list of the issues immediately above that line.
- You read **only** the verdict line to decide the branch. You forward the issue list to that spec's implement agent without interpreting it.

## Commit (you run this)

After the review/fix phase for a spec — **one commit per spec**:

1. `git add -A`
2. `git commit -m "<message>"`
3. Build the message from the spec: conventional prefix (`feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`), imperative, ≤50 chars, no trailing period, derived from the spec's title/heading. No AI attribution anywhere — a PreToolUse hook enforces this and will reject the commit otherwise.

Then move to the next spec.

## Failure handling

- If a sub-agent hard-fails (cannot implement, crashes, repeatedly errors), **stop** and report which spec failed and why. Never fabricate a commit for work that didn't happen.
- Spec dispatch is sequential and resumable: if you stop, the already-committed specs stay done.

## Reporting

- Keep a running progress line per spec: `[i/N] <spec> — implementing / reviewing (pass k) / fixing / committed`.
- Final summary: specs completed, commits made, and any spec that hit the **3-review cap** (its last-round fixes were applied but not re-reviewed) so the user knows where to double-check.

**Do not stop until every spec is committed**, unless a hard failure forces a stop.
