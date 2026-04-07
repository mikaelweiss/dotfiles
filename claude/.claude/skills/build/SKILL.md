---
name: build
description: Ideate and implement a feature or fix in one flow. Self-answers design questions from codebase context, presents reasoning for confirmation, then implements. Use when the user says "build", "build this", "build issue #N", or invokes /build.
user-invocable: true
argument-hint: [issue-number or description]
---

# Build

Ideate and implement in one pass. Research the codebase, ask yourself design questions, answer them from what you find, get user confirmation, then implement.

## Input

$ARGUMENTS

## Critical Rules

- **No sub-agents.** Do all reading, searching, and research yourself. Never use the Agent tool.
- **No plan mode.** Do not use EnterPlanMode or ExitPlanMode.
- **Read before you speak.** Never suggest, claim, or spec anything you haven't read the source for.

---

## Phase 1: Understand the Input and Find GitHub Issue

**If the input is a GitHub issue number:**
- Fetch with `gh issue view <number>` and `gh issue view <number> --comments`
- Use the issue title, body, and comments as the starting point

**If the input is plain text:**
- Use the description as the starting point
- Search GitHub for an existing issue that matches: `gh issue list --search "relevant keywords"`
- If a matching issue exists, confirm with the user: "Found #N: [title]. Is this the right issue?"
- If no match exists, note that a new issue will be created when the spec is ready

Track the issue number throughout. Every build ends with a spec on a GitHub issue.

---

## Phase 2: Codebase Skim

Before any design thinking, explore the relevant area of the codebase:
- Identify files, types, functions, and patterns related to the task
- Understand conventions the project uses
- Note dependencies and relationships

Go wide enough that you won't be surprised later. This prevents asking questions you should already know the answer to.

---

## Phase 3: Self-Brainstorm (Iterative)

Ask yourself design questions in rounds of 3-5. Answer each one from what you found in the codebase. After each round, assess: did any answer raise new questions? If yes, do another round. Keep going until you have no unanswered questions remaining.

**What to probe:**
- **Core behavior** — What exactly should happen? What triggers it?
- **Edge cases** — Errors? Empty states? Boundary conditions?
- **Scope boundaries** — What is explicitly NOT part of this?
- **User experience** — How will someone actually use this?
- **Dependencies** — What does this interact with? What needs to exist first?
- **Constraints** — Performance? Platform limitations? Compatibility?
- **Existing patterns** — How does the codebase already handle similar things?

**Each round:**
1. Ask 3-5 questions
2. Read any additional code needed to answer them
3. Search the web and context7 for any needed information
4. Answer each with evidence from the codebase
5. Check: did any answer reveal something that needs further clarification?
6. If yes — start the next round with those new questions
7. If no — you're done, move to Phase 4

For each question, provide:
1. The question
2. Your answer
3. Why — what in the code or docs led you to that answer

---

## Phase 4: Present and Confirm

Present the Q&A list to the user in this format:

```
Here's what I've determined from the codebase:

1. **[Question]**
   Answer: [your answer]
   Why: [evidence from code/docs]

2. **[Question]**
   Answer: [your answer]
   Why: [evidence from code/docs]

[... etc]

Does this look right? Correct anything you disagree with, or say "go" to proceed.
```

**If the user corrects an answer:** Accept the correction and move on. Do not re-research.

**If the user confirms:** Proceed to Phase 5.

---

## Phase 5: Deep Research and Spec

Now go deep. For every change needed:
- Find exact files and line numbers
- Read the full context around each location
- Identify types, function signatures, and patterns to follow
- Look up any external API docs needed (web search, library docs)

Produce an internal spec with:

- **Summary** — 1-2 sentences
- **Behaviors** — One bullet per requirement, edge cases inline
- **Out of Scope** — Things explicitly excluded
- **Changes Required** — Each change with file path, line number, and description
- **Implementation Order** — Dependency-aware sequence

Present the spec to the user. Once confirmed, post it to GitHub before implementing.

### Post Spec to GitHub

**If an existing issue was identified in Phase 1:** Add the spec as a comment:
```bash
gh issue comment <number> --body "<!-- SPEC -->
[spec content]"
```

**If no existing issue:** Create a new issue with the spec as the body:
```bash
gh issue create --title "[title]" --body "<!-- SPEC -->
[spec content]"
```

---

## Phase 6: Implement

Follow the spec's Implementation Order exactly.

- Go directly to the file and line specified
- Make the change described
- Follow existing patterns in the codebase
- Do not add features or "improvements" beyond the spec

---

## Phase 7: Verify

Run the project's standard checks. Determine what's appropriate by looking at:
- The project's package manager and build tools
- Existing scripts in `package.json`, `Makefile`, `Cargo.toml`, etc.
- CI configuration if present

Common checks to look for and run:
- Type checking / compilation
- Linting and formatting
- Tests
- Build

Review your changes against the Behaviors section in the spec. Every behavior should be addressed.

---

## Phase 8: Wrap Up

After verification passes:

1. Run `/commit` to commit the changes

---

## Anti-Patterns

- Spawning sub-agents for research or implementation
- Asking the user questions you could answer from the code
- Implementing without user confirmation of the design
- Adding scope beyond what was confirmed
- Skipping verification
- Skipping the GitHub spec posting
