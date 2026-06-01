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

Before asking any question, write down (silently) the answer you'd give if forced to choose right now. If your answer is ≥70% confident from code or docs, **don't ask** — proceed and note the decision in the spec's Context. Only ask when the answer genuinely requires human judgment:

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

Then decompose the work into the smallest independently-mergeable units. Each spec:
- Implements one cohesive behavior
- Is testable on its own
- Ships without depending on a yet-to-be-written spec
- Implies roughly ≤400 LOC of resulting code (split if bigger)

Sequence them: each spec only depends on prior specs. Forward dependencies are not allowed.

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
Only what the implementer needs that isn't already in the code or in the requirements. Cite specific files and line numbers. No paragraphs of restatement.

## Requirements
Numbered list of definite, testable behaviors. Each one is a clear statement — never "may", "might", "possibly", "TBD", "verify whether", "check first", or "pick one". If you find yourself writing those, go research first.

1. ...
2. ...

## Files
Definitive list of every file that will be created or modified. No hedges. Each entry:

- `path/to/file.ext` — Create / Modify / Delete. One-line description of what changes.

The implement agent is forbidden from creating files not in this list. If implementation needs a file not listed, the spec was wrong — surface it.

## Test expectations
Bulleted behavioral test scenarios. Not test code.

## Boundaries
"Does NOT" lines that describe behavior outside this spec. Each is a concrete, self-contained statement. Never reference other specs by number.

- "Does NOT support search" — good
- "Does NOT support search (that's spec 005)" — wrong, drop the parenthetical
```

## What NOT to put in specs

- **No internal architecture.** Don't decompose into sub-modules, helper files, or layer splits unless those modules are referenced from outside the spec. Name public entry points and behaviors; let the implementer choose internal structure. (This is the #1 cause of architectural rewrites after implementation.)
- **No code.** Not in Requirements, not in Context. Pseudocode for non-trivial algorithms is fine; production code shapes are not.
- **Default to bullets, tables, and concrete examples (JSON / pseudocode / tables).** They scan far faster than prose. Drop to a sentence or two only when a *why* genuinely needs it — never a paragraph where a bullet would do.
- **No spec numbers anywhere.** Not in Context, not in Boundaries, not in Files. Every spec stands on its own.
- **No "out of scope because spec N covers it."** Just "Does NOT do X." The implementer doesn't need to know who else is doing what.

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
