---
name: "source-command-cog-capture"
description: "Interactively investigate a bug report, feature idea, or half-formed thought, then file a well-scoped GitHub issue that cog's autonomous build phase can implement without ambiguity."
---

# source-command-cog-capture

Use this skill when the user asks to run the migrated source command `cog-capture`.

## Command Template

# Capture: investigate and file a GitHub issue

You are helping a developer turn a bug report, feature idea, or half-formed thought into a well-scoped, technically grounded GitHub issue. Interactive — you will ask the user questions; they answer; you investigate; then you file.

Your job is not to write code. Your job is to produce an issue that cog's autonomous `build` phase can implement without ambiguity.

## Workflow

### 1. Clarify the ask

Ask the user short, focused questions to understand what they're reporting. Don't interview — ask the minimum needed. Different angles for bugs vs. features:

**Bug:**
- What behavior did you see?
- What did you expect?
- How do you reproduce it?
- Where in the app (URL, command, file)?
- Any error message or stack trace?

**Feature:**
- What problem does this solve?
- Who is it for?
- Is there a sharpest-wedge version — the smallest change that would be useful?

If their first response is already specific enough, don't force more questions. Move on.

### 2. Investigate the codebase

Ground the issue in real files before writing it. Use the `Agent` / subagent tool if available to:
- Find the components involved.
- Identify data flows and API calls the change touches.
- Spot existing tests that will need to be updated.
- Check related repositories if the change crosses boundaries.

Report what you found back to the user briefly. If investigation changed your understanding of the scope ("this touches three services, not one"), surface that now — not after the issue is filed.

### 3. Present a summary for approval

Before filing, show the user a summary using this skeleton. Sections marked `(bugs)` apply only when Step 1 classified the report as a bug; sections marked `(features)` apply only when it classified as a feature. Drop sections that don't apply rather than leaving them blank.

```markdown
## Issue Summary

**Title:** [Concise, descriptive title]

**Description:**
[Clear description of the problem or feature]

**Steps to Reproduce:** (bugs)
1. ...
2. ...

**Motivation:** (features)
[Why this matters; sharpest-wedge version]

**Expected Behavior:** (bugs)
[What should happen]

**Actual Behavior:** (bugs)
[What actually happens]

**Affected Components:**
- [File paths and module names identified during investigation]

**Technical Context:**
- [Relevant code paths, data flow, constraints]
- [Related issues or cross-repo touchpoints]

**Additional Context:**
- [Error messages, stack traces, etc.]
```

Ask the user to approve, edit, or abandon. Wait for a response. Do not proceed without one.

### 4. Check for duplicates

Before creating the issue, search existing issues:

```bash
gh issue list --state all --search "<keywords from title and body>"
```

If you find a likely duplicate, surface it to the user and offer to comment on the existing issue with the new context instead of creating a new one. Do not silently skip the creation — ask.

### 5. File it

If the user approved a new issue, build the body from this skeleton (parallel to the Step 3 summary, but with `##` H2 headings instead of bold labels — that's the shape GitHub renders best inside an issue body). Drop sections that don't apply to this report's type.

```markdown
## Description
[Description from approved summary]

## Steps to Reproduce  (bugs)
1. ...

## Motivation  (features)
[Motivation from approved summary]

## Expected Behavior  (bugs)
## Actual Behavior  (bugs)

## Affected Components
- [Component list with paths]

## Technical Context
[Technical details, code paths, potential root cause]

## Additional Context
[Error messages, screenshots if provided, etc.]
```

Then file it:

```bash
gh issue create --title "<title>" --body "<body>"
```

If they chose to comment on a duplicate, build the comment body from this skeleton — it's narrower because the original issue already carries the title, description, and reproduction shape:

```markdown
## Additional Context

[New information discovered during this investigation]

### Technical Details
- [Any new technical context]
- [Additional affected components]
```

Then post it:

```bash
gh issue comment <number> --body "<added context>"
```

Report the resulting URL.

If either command fails, report the error verbatim to the user. The two common causes are not authenticated (`gh auth login`) and the account lacking write permission on the repo.

## Principles

- **Specificity beats length.** A two-line title plus five-line body that names files is more useful than a paragraph of context without any.
- **Don't invent scope.** If the user said "fix the login bug," don't file "redesign auth" because you found related issues. Stay in the lane they pointed at.
- **Be honest about uncertainty.** If you couldn't find the affected code, say so in the issue body. A human reviewer will appreciate it more than a confident misdirection.
