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
spawn implement agent (stable name, e.g. "impl") → run /implement <spec>, leave changes uncommitted
await completion

reviewCount = 0
loop:
    spawn a FRESH review agent → run /review <spec>; it reports a VERDICT + issue list
    reviewCount += 1

    if VERDICT == CLEAN:
        break                      # ready to commit

    # issues found → hand them to the SAME implement agent
    SendMessage(impl, "<reviewer's issues, verbatim> — fix these, leave uncommitted")
    await fix

    if reviewCount == 3:
        break                      # cap reached: issues are now fixed, commit WITHOUT a 4th review

commit (see Commit section)
→ next spec
```

**Cap behavior, stated plainly:** at most **3 review passes** per spec. If the 3rd review still returns issues, the implement agent fixes them and you commit anyway — you do **not** run a 4th review. A review that comes back `CLEAN` at any pass means commit immediately.

## The sub-agents

### Implement agent — reused for the whole spec
- Spawn **once per spec** with a stable `name` so you can continue it via `SendMessage` (load the tool first with ToolSearch: `select:SendMessage`). Reusing the same agent preserves its full implementation context across fixes.
- `subagent_type: general-purpose`.
- Initial prompt: invoke `/implement <spec path>`, implement the spec fully, and **do not commit** — leave all changes uncommitted.
- For each fix round: `SendMessage` the reviewer's issue list **verbatim** with the instruction "fix these issues, leave changes uncommitted." Do not paraphrase or filter the issues.

### Review agent — fresh every pass
- Spawn a **new** agent for **every** review pass. Never reuse a review agent.
- `subagent_type: general-purpose`.
- Prompt: invoke `/review <spec path>` against the current uncommitted changes; **do not edit or commit anything**; finish the reply with exactly one line — `VERDICT: CLEAN` or `VERDICT: ISSUES` — and when `ISSUES`, put a numbered list of the issues immediately above that line.
- You read **only** the verdict line to decide the branch. You forward the issue list to the implement agent without interpreting it.

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
