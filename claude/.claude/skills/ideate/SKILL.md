---
name: ideate
description: >
  Decompose a change into small, independently-implementable spec files.
  Use when starting new features, refactors, migrations, or any multi-step work.
  Triggers: "plan", "break this down", "decompose this", "spec this out",
  "what are the steps", "how should I approach this".
user-invocable: true
---

# Ideate

Decompose a change into an ordered sequence of small, independently-implementable specs. Each spec becomes one session, one PR, one reviewable unit.

**The only thing you write is spec files in `.specs/`.** No application code, no scaffolding, no build commands, no edits to existing files outside `.specs/`. Every decision about behavior and scope must be settled in the spec before it's written — the implementer chooses only internal structure (private helpers, naming, file organization within the listed files).

## Process

### 1. Read first, ask second

Before talking to the user, exhaust your tools:
- Read the relevant code — files, structure, patterns, conventions, neighbors.
- Run grep / find to confirm what exists vs what doesn't.
- Fetch docs (Context7, WebFetch, WebSearch) for any library or framework involved.

You have full read access. Use it. If you're about to ask "does X exist?", "how is Y handled?", "what's the convention?" — go read instead.

### 2. Ask only what you can't figure out

Before asking any question, write down (silently) the answer you'd give if forced to choose right now. If your answer is ≥70% confident from code or docs, **don't ask** — proceed and note the decision, and the reasoning behind it, in the spec's Context. When the user does answer a question, record *why* they chose it, not just what — that reasoning is exactly what a future reader can't reconstruct from the code. Only ask when the answer genuinely requires human judgment:

- Product / UX preferences
- Scope tradeoffs ("does this include X?")
- Constraints you can't discover (deadlines, compatibility targets, performance targets)
- Architectural preferences when multiple valid approaches exist and the codebase has no precedent

Questions you must NEVER ask:
- Anything about how the current code works → read it
- Anything about library / framework behavior → fetch docs
- Anything about project structure, conventions, file existence → grep
- Anything about the tech stack → inspect package files / build configs
- "Should I read X?" / "Should I look at Y?" — just do it

Batch questions as a numbered list. If you have zero real questions, skip to step 4.

### 3. Iterate until alignment

After the user answers, repeat 1–2 if needed. Each round goes deeper — never re-ask something already answered or discoverable.

### 4. Walk the concerns checklist, then decompose

Before decomposing, mentally walk through the standard concerns. For each, decide: **addressed in spec N, or explicitly out of scope and why.** This is the step that catches missed-entirely failures.

- Authentication / unauthenticated state / sign-out
- Timezone / locale / date handling
- Error handling / partial failure / retries
- Sync / cross-device / stale data
- Soft-delete / cascade / deleted-records tracking
- Undo / reversal
- Empty state / first-run
- Accessibility
- Color / theming / dark mode
- Offline behavior
- Existing tests / test conventions

Don't write the checklist into the spec. Use it to make sure nothing important is silently skipped.

Then decompose the work into **right-sized** units — the *largest* slice that still forms one cohesive, independently-reviewable change, not the smallest possible diff. Aim for fewer, well-scoped specs; a spec per nitpick is a failure mode, not the goal. Each spec:
- Implements one cohesive change (which may bundle several small, related edits)
- Is testable on its own
- Ships without depending on a yet-to-be-written spec
- Implies roughly 50–400 LOC of resulting code

**Split** when a unit exceeds ~400 LOC or mixes unrelated concerns.

**Merge** candidate specs into one when either holds:
- **Coupled:** they touch the same files/functions, must ship together, or one is meaningless without the other.
- **Small + local:** they're individually trivial (nitpicks, minor tweaks, small fixes) and share an area or context. A pile of small tweaks becomes one chore/polish spec (see below), not one spec each.

When torn between one medium spec and two tiny ones, prefer the one — unless the two are genuinely unrelated and each stands alone.

Sequence them: each spec only depends on prior specs. Forward dependencies are not allowed.

**Right-size pass.** Before presenting, challenge your list for over-decomposition. For each spec ask: would one implement agent naturally handle this together with its neighbor in a single session, without exceeding ~400 LOC or mixing unrelated concerns? If yes, merge them — collapse tightly-coupled specs, and gather clusters of trivial nitpicks into a single chore/polish spec. If you merged anything, say so with the before/after count.

Present the decomposition to the user as a numbered list of spec titles with one-line descriptions. Confirm before writing files.

### 5. Write spec files

**Location:**
- ≤5 specs: `.specs/001-short-description.md`, `.specs/002-short-description.md`, etc.
- >5 specs or distinct feature: `.specs/<feature-name>/001-short-description.md`, etc.

Three-digit zero-padded prefixes. Kebab-case names.

### 6. Self-audit, then summarize

Before announcing completion, scan every spec for these phrases:

- "Possibly", "Possibly modify", "may need", "might need"
- "TBD", "to be determined", "check first", "verify whether"
- "Choose one", "pick one", "either approach"
- The literal string "spec " followed by a number, anywhere in Boundaries

Every match is research debt or sloppy wording. Resolve each — by reading code, running grep, fetching docs, or asking the user — and rewrite the spec. Do not stop at the first pass; re-scan after fixes.

Then scan for **what-without-why**: any requirement, constraint, or boundary that encodes a non-obvious decision but states no reason. Add the one-line why, or leave it if the reason is genuinely self-evident. This is the gap that leaves implementers and reviewers unable to handle edge cases the spec didn't enumerate.

Then print:
- Total spec count
- Path
- Implementation order
- "Start a new session and run `/implement <spec-path>` to begin."

## Spec file format

```markdown
# [NNN] Title

## Objective
1–3 sentences. What this spec accomplishes.

## Context
What the implementer and reviewer need that they **cannot recover from the code** — including the *why* behind the requirements, not just the what. Bullets, not prose:
- **Decisions + rationale:** any deliberate choice, with the reason (and the rejected alternative if it's load-bearing). E.g., "Debounce at 300ms — upstream API rate-limits at 5 req/s."
- **External constraints** the code doesn't reveal: deadlines, compatibility targets, API limits, product/UX calls.
- **Pointers** to the files/lines to mirror.

Cite specific files and line numbers. No restatement of the requirements. One line of *why* per non-obvious decision — obvious things get none.

## Requirements
Numbered list of definite, testable behaviors. Each one is a clear statement — never "may", "might", "possibly", "TBD", "verify whether", "check first", or "pick one". If you find yourself writing those, go research first.

When a requirement encodes a non-obvious choice, append a short `— because …` clause so the *why* travels with the *what*. A clause, never a paragraph. Obvious requirements get no rationale.

1. ...
2. ...

## Files
Definitive list of every file that will be created or modified. No hedges. Each entry:

- `path/to/file.ext` — Create / Modify / Delete. One-line description of what changes.

The implement agent is forbidden from creating files not in this list. If implementation needs a file not listed, the spec was wrong — surface it.

## Test expectations
Bulleted behavioral test scenarios. Not test code.

## Boundaries
"Does NOT" lines that describe behavior outside this spec. Each is a concrete, self-contained statement. When a boundary isn't self-evidently out of scope, append a short why. Never reference other specs by number.

- "Does NOT support search" — good
- "Does NOT retry on failure — the caller already retries" — good, the why travels with the boundary
- "Does NOT support search (that's spec 005)" — wrong, drop the parenthetical
```

## Chore / polish specs

When a cluster of changes is individually trivial and low-risk — nitpicks, copy tweaks, small renames, one-line fixes — do **not** give each its own spec. Bundle them into one chore spec whose Requirements is a checklist, one line per change, each naming its file(s):

```markdown
## Requirements
1. `src/Button.tsx` — rename `onTap` prop to `onPress` to match the rest of the codebase.
2. `src/api.ts:42` — fix typo in error message ("recieved" → "received").
3. `README.md` — update the install command to pnpm.
```

The implementer does all items in one session; the reviewer reviews the combined diff once; one commit. The fixed cost of an implement→review→commit cycle gets paid once for the whole bundle instead of once per item. Bundle only genuinely small, independent changes — anything with real logic or a behavioral decision gets its own spec.

## What NOT to put in specs

- **No internal architecture.** Don't decompose into sub-modules, helper files, or layer splits unless those modules are referenced from outside the spec. Name public entry points and behaviors; let the implementer choose internal structure. (This is the #1 cause of architectural rewrites after implementation.)
- **No code.** Not in Requirements, not in Context. Pseudocode for non-trivial algorithms is fine; production code shapes are not.
- **Default to bullets, tables, and concrete examples (JSON / pseudocode / tables).** They scan far faster than prose. Drop to a sentence or two only when a *why* genuinely needs it — never a paragraph where a bullet would do.
- **No spec numbers anywhere.** Not in Context, not in Boundaries, not in Files. Every spec stands on its own.
- **No "out of scope because spec N covers it."** Just "Does NOT do X." The implementer doesn't need to know who else is doing what.
- **No version or phase framing.** The spec describes the complete, desired end state — not a "V1," "MVP," or first cut. Never write "for now," "initial version," or "deferred to v2," and never scope a requirement down to a version. A boundary states what's genuinely out of scope, never that something is "coming in a later version."

## Behavioral rules need enforcement plans

If a requirement says "X must always Y" — e.g., "the AI must query before mutating," "tokens must expire after 90 days," "uploads must reject non-image content" — the spec must also state **where Y is enforced**, in this spec:

- Prompt text? Quote the exact text.
- Tool / function input validation? Name the function and the check.
- Test that asserts it? Note the scenario.

A behavioral rule without an enforcement plan becomes one line of code that doesn't enforce. List enforcement points like requirements.

## Rules

- Never write application code, scaffold files, or run build commands. Only writes are `.specs/*.md` files.
- The implement agent makes no behavioral or scope decisions; every such choice must be definite in the spec. (Internal structure is theirs.)
- If a spec implies >400 LOC of resulting code, split it.
- Three-digit zero-padded prefixes (001, 002, ...). Kebab-case names.
- Specs must be readable by a weak model. If a junior reader couldn't implement it cleanly from the spec plus the cited files, the spec is wrong.
