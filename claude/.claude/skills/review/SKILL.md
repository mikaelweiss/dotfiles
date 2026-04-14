---
name: review
description: Code review a branch or PR. Finds CLAUDE.md files, reads the diff, launches parallel agents to audit for CLAUDE.md compliance and bugs, validates issues, then posts inline comments. Use when the user says "review", "review this", "review my changes", or invokes /review.
user-invocable: true
argument-hint: [branch or PR number]
---

# Code Review

Review the current branch (or PR) for CLAUDE.md/AGENTS.md compliance and bugs. Uses parallel sub-agents for independent review axes, then validates and posts inline comments.

## Input

$ARGUMENTS

## Critical Rules

- **Do not use AskUserQuestion.** Complete the entire review without user intervention.
- **Do not use plan mode.** Do not use EnterPlanMode or ExitPlanMode.
- Use `gh` CLI for all GitHub interaction. Do not use web fetch.
- Only the main agent posts comments. Sub-agents must never post comments themselves.
- Only flag **high signal** issues. False positives erode trust.

---

## Step 1: Gather CLAUDE.md / AGENTS.md Files

Launch a **haiku** agent to return a list of file paths (not contents) for all relevant CLAUDE.md and AGENTS.md files:

- The root CLAUDE.md / AGENTS.md, if they exist
- Any CLAUDE.md / AGENTS.md files in directories containing files modified by the diff

To find modified files, use:

```bash
MERGE_BASE=$(git merge-base origin/main HEAD)
git diff --name-only $MERGE_BASE HEAD
git diff --name-only HEAD
```

Then check each modified file's directory (and parents) for CLAUDE.md or AGENTS.md files.

---

## Step 2: Get PR Context (if applicable)

Check if the current branch has an associated PR:

```bash
gh pr view --json title,body
```

If a PR exists, capture the **title** and **description** (not the changes). This provides intent context for reviewers.

---

## Step 3: Summarize Changes (parallel with Step 2)

Launch a **sonnet** agent to view the full diff and return a summary of the changes.

The agent should run:

```bash
MERGE_BASE=$(git merge-base origin/main HEAD)
git diff $MERGE_BASE HEAD
git diff HEAD
```

And return a concise summary of what changed and why (inferred from the diff).

---

## Step 4: Parallel Review (4 agents)

Launch 4 agents in parallel. Each receives:
- The PR title and description (from Step 2)
- The list of CLAUDE.md / AGENTS.md file paths (from Step 1)
- Instructions to read the diff themselves using the git commands above
- **Explicit instruction: do NOT post comments. Return a list of issues only.**

Each issue must include: a description, the file and line(s), and the reason it was flagged.

### Agent 1: CLAUDE.md / AGENTS.md Compliance (sonnet)

Audit changes for CLAUDE.md / AGENTS.md compliance. Read the relevant CLAUDE.md / AGENTS.md files and check all changed code against them. Only consider CLAUDE.md / AGENTS.md files that share a file path with the changed file or its parents.

### Agent 2: CLAUDE.md / AGENTS.md Compliance (sonnet)

Same as Agent 1 — independent parallel pass for coverage.

### Agent 3: Bug Scan — Diff Only (opus)

Scan for obvious bugs. Focus only on the diff itself without reading extra context. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that cannot be validated without looking at context outside the diff.

### Agent 4: Introduced Problems (opus)

Look for problems in the introduced code: security issues, incorrect logic, etc. Only flag issues within the changed code.

### What to flag (ALL agents)

- Objective bugs that will cause incorrect behavior at runtime
- Clear, unambiguous CLAUDE.md / AGENTS.md violations where you can quote the exact rule being broken

### What NOT to flag (ALL agents)

- Pre-existing issues not introduced by this diff
- Subjective concerns or "suggestions"
- Style preferences not explicitly required by CLAUDE.md / AGENTS.md
- Potential issues that "might" be problems
- Anything requiring interpretation or judgment calls
- Pedantic nitpicks a senior engineer would not flag
- Issues a linter would catch
- General code quality concerns unless explicitly required by CLAUDE.md / AGENTS.md
- Issues mentioned in CLAUDE.md / AGENTS.md but explicitly silenced in code (e.g., lint ignore comments)
- Something that appears to be a bug but is actually correct

**If you are not certain an issue is real, do not flag it.**

---

## Step 5: Validate Issues (parallel agents)

For each issue found in Step 4, launch a parallel sub-agent to validate it:

- **Opus** agents for bugs and logic issues
- **Sonnet** agents for CLAUDE.md / AGENTS.md violations

Each validation agent receives:
- The PR title and description
- The issue description, file, and line(s)
- Instructions to read the relevant code and confirm the issue is real with high confidence

For example:
- "Variable is not defined" — verify it truly isn't defined in scope
- "CLAUDE.md violation" — verify the rule is scoped to this file and is actually violated
- Check that the issue isn't pre-existing, isn't a false positive, and is genuinely high signal

---

## Step 6: Filter

Remove any issues that were not validated in Step 5. The remaining issues are the final review findings.

---

## Step 7: Post Inline Comments

For each validated issue, post an inline PR comment using `gh`:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="<comment>" \
  -f commit_id="<sha>" \
  -f path="<file>" \
  -F line=<line> \
  -f side="RIGHT"
```

To get the required values:
- `{owner}/{repo}`: from `gh repo view --json nameWithOwner`
- `{pr_number}`: from `gh pr view --json number`
- `commit_id`: use `git rev-parse HEAD`
- `path`: relative file path from the issue
- `line`: line number in the new file

**Post only ONE comment per unique issue.**

If there is no associated PR, skip posting comments and just report the issues.

When citing a CLAUDE.md or AGENTS.md rule in a comment, include a link to the file (e.g., a GitHub permalink).

---

## Step 8: Report

Write out the final list of issues. Format:

### **#1 [Issue title]**

[Description of the issue and why it matters]

File: [path/to/file]

### **#2 [Issue title]**

[Description]

File: [path/to/file]

If no issues were found, say so.

---

## Fallback: No Sub-agents

If sub-agents are unavailable, perform all steps yourself sequentially. Do each review axis (CLAUDE.md compliance, bug scan, introduced problems) yourself, and validate each issue yourself.
