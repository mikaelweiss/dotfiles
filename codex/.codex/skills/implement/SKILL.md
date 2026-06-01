---
name: implement
description: >
  Implement a single spec file from the plan skill. One spec per session.
  Takes a spec file path as an argument.
  Triggers: "implement", "implement this spec", "implement <path>".
user-invocable: true
---

# Implement

Implement exactly one spec. One spec, one session, one small reviewable change.

## Usage

The user invokes this skill with a path to a spec file:
```
/implement .specs/001-add-data-model.md
```

If no path is provided, look for a `.specs/` directory and list available specs. Help the user pick the next one based on numbering and dependency order.

## Process

### Step 1: Read the spec

Read the spec file completely. This is your single source of truth for what to build.

### Step 2: Read the context

Read every file mentioned in the spec's "Affected areas" and "Context" sections. Also read any prior specs referenced to understand what was already done.

Understand the codebase conventions by looking at neighboring files — match patterns, naming, style.

### Step 3: Implement

Write the code that satisfies every requirement in the spec. Follow these principles:

- **Match existing patterns.** Look at how similar things are done in the codebase and do the same.
- **Satisfy the spec, nothing more.** Don't add features, refactor surrounding code, or "improve" things outside the spec's scope. Respect the "Boundaries" section.
- **Write tests as specified.** Implement the test scenarios from "Test expectations." Match the project's existing test patterns and frameworks.
- **Keep the changeset small.** If you find yourself touching files not listed in the spec, stop and reconsider. The spec should have anticipated the affected files — if it didn't, mention it to the user rather than silently expanding scope.

### Step 4: Verify

- Run the project's existing test suite (or the relevant subset) to make sure nothing is broken.
- Run any linters or type checkers the project uses.
- Fix any issues that arise from YOUR changes. Do not fix pre-existing issues unless the spec says to.

### Step 5: Report

When done, print a short summary:
- What was implemented (one-line)
- Files created or modified (list)
- Tests added or updated (list)
- Any concerns or deviations from the spec
- Remind the user: "This spec is complete. Start a new session for the next spec."

## Rules

- **One spec per session.** Never read the next spec. Never start the next task. When this spec is done, stop.
- **Don't commit or branch.** The user manages git workflow themselves.
- **Don't create PRs.** The user handles that.
- **Spec is authoritative.** If the spec says to do X, do X. If you think the spec is wrong, flag it to the user — don't silently deviate.
- **No scope creep.** If you notice something outside the spec that should be fixed, mention it in the report. Don't fix it.
- If the spec references prior specs that haven't been implemented yet, warn the user — they may be out of order.
