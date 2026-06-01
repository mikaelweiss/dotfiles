---
name: ideate
description: >
  Decompose a large change into small, independently-implementable spec files.
  Use when starting new features, refactors, migrations, or any multi-step work.
  Triggers: "plan", "break this down", "decompose this", "spec this out",
  "what are the steps", "how should I approach this".
user-invocable: true
---

# Plan

Decompose a change into an ordered sequence of small, independently-implementable specs. Each spec becomes one session, one PR, one reviewable unit.

## Philosophy

Planning is valuable. Giant PRs are not. This skill converts thorough understanding into a sequence of small, precise specs that any agent — even a weak one — can implement without ambiguity.

**No code in specs.** If you're writing code, you're implementing, not planning. Specs describe *what* and *why* in natural language only.

## Process

### Step 1: Understand the full picture

Before asking the user anything:
- Read the relevant code. Explore the codebase thoroughly — files, structure, patterns, conventions.
- Search the web or library docs (Context7, WebSearch, WebFetch) for anything you need to understand.
- Build a mental model of the current state and what needs to change.

**Do your homework first.** Exhaust what you can learn on your own before involving the user.

### Step 2: Ask only what you can't figure out

Ask the user questions, but ONLY questions that require human judgment. Batch them as a numbered list.

Questions you must NEVER ask (figure these out yourself):
- Anything about how the current code works (read it)
- Anything about library APIs or framework behavior (search docs/web)
- Anything about project structure or conventions (look at the codebase)
- Anything about what files exist or what they contain (read them)
- Anything about the tech stack (inspect package files, build configs, etc.)
- "Should I read the code?" or "Should I look at X?" — just do it

Questions you SHOULD ask:
- Ambiguous product/UX decisions the code can't answer
- Priority tradeoffs ("should we optimize for speed or correctness here?")
- Scope boundaries ("does this include X or is that a separate effort?")
- Constraints you couldn't discover ("is there a deadline?", "does this need to be backwards-compatible with X?")
- Architectural preferences when multiple valid approaches exist and the codebase doesn't establish a precedent

If you have zero questions, skip straight to decomposition. Don't ask questions just to seem thorough.

### Step 3: Iterate until alignment

After the user answers, repeat steps 1-2 if needed. You may need multiple rounds. Each round should go deeper — never re-ask something already answered or discoverable.

### Step 4: Decompose into specs

Break the work into the smallest independently-mergeable units. Each spec should:
- Be implementable in a single session
- Touch a small number of files (aim for <10, ideally <5)
- Be testable on its own
- Build on prior specs but be mergeable independently (no half-finished states)

Present the decomposition as a numbered list of spec titles with one-line descriptions. Ask the user to confirm, reorder, merge, or split before writing the files.

### Step 5: Write spec files

After the user approves the decomposition, write each spec to disk.

**Location:**
- Small tasks (≤5 specs): `.specs/001-short-description.md`, `.specs/002-short-description.md`, etc.
- Larger tasks (>5 specs or logically distinct feature): `.specs/<feature-name>/001-short-description.md`, etc.

**Spec file format:**

```markdown
# [NNN] Title

## Objective
One paragraph. What this spec accomplishes and why it matters in the broader plan.

## Context
What currently exists that this spec builds on. Reference specific files, modules, or patterns by name. Mention which prior specs (if any) must be completed first.

## Requirements
Numbered list of concrete, testable requirements. Each one is a clear statement of behavior or structure — not a vague goal.

1. ...
2. ...
3. ...

## Affected areas
List of files or modules that will likely need changes, and what kind of change (create, modify, extend). Be specific about *what* changes in each file, described in natural language.

- `path/to/file.ts` — Add X, modify Y
- `path/to/other.ts` — Extend Z to support W

## Test expectations
What tests should be written or updated. Describe the scenarios, not the test code.

- Verify that ...
- Ensure that ... when ...
- Edge case: ...

## Boundaries
What this spec explicitly does NOT cover. Prevents scope creep during implementation.

- Does NOT include ...
- ... will be handled in spec NNN
```

### Step 6: Summarize

After writing specs, print a short summary:
- Total number of specs
- The path where they live
- Suggested order (if non-linear dependencies exist)
- Remind the user: "Start a new session and run `/implement <spec-path>` to begin the first task."

## Rules

- Never write code in spec files. Not even pseudocode. Describe behavior in natural language.
- Never create a spec that requires more than ~400 lines of changes. If it's bigger, split it.
- Number specs with zero-padded three-digit prefixes (001, 002, ...) for sort order.
- Use kebab-case for file and folder names.
- If the user provides a GitHub issue or PR, read it to extract context before starting.
- Specs should be detailed enough that someone with no prior context (or a weak model like Haiku) can implement them correctly by reading only the spec and the referenced files.
