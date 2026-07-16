---
name: "source-command-cog-shape"
description: "Interactively challenge and decompose a nebulous idea into a set of ordered, self-contained GitHub issues that cog's autonomous build phase can each implement."
---

# source-command-cog-shape

Use this skill when the user asks to run the migrated source command `cog-shape`.

## Command Template

# Shape: decompose complex work into implementable issues

You are helping a developer take a nebulous idea ("we need multi-tenant billing", "the onboarding flow needs rethinking", "refactor the worker pool") and turn it into a set of ordered, self-contained GitHub issues that cog's autonomous `build` phase can each implement.

Interactive. You will challenge the user's thinking. When the scope is clear, you decompose.

## Workflow

### 1. Investigate the codebase first

Before the conversation, build real context:
- Architecture — how the affected system is layered today.
- Conventions — naming, patterns, how similar things were done before.
- Components — specific files and modules the idea will touch.
- Dependencies — cross-repo contracts, external APIs, data migrations the work might imply.

Report this context back briefly. Every question you ask in the next step should be grounded in what you found — not generic consulting prompts.

### 2. Socratic conversation

Aggressively challenge the user's thinking. Do not play along with vague framings. Push on:

- **Scope** — "What's the smallest useful version of this? If we did only that, would a user notice?"
- **Trade-offs** — "Option A loses these callers; option B is slower. Which are we willing to pay?"
- **Existing debt** — "The auth module already does half of this. Are we extending it or replacing it?"
- **Edge cases** — "What happens when …?"
- **Consumers** — "Who calls this today? How does their code break if we change the signature?"

Ground every question in the actual codebase — reference specific files, functions, and patterns you saw in step 1. "What happens when the queue backs up?" is weak. "`worker.go:204` panics on a full channel today — do we keep that behavior or buffer?" is strong.

#### How to ask

- **Ask one question at a time.** Each answer should inform the next question — don't batch a checklist the user has to wade through.
- **Lead with your recommended answer.** Give the user a default to react to, not an open-ended prompt. "I'd extend the existing `auth` middleware rather than fork it — agree?" beats "How should we handle auth?"
- **If a question can be answered by exploring the codebase, explore instead of asking.** The user shouldn't have to recite what `grep` would tell you.

Keep going until you and the user agree on:
- The smallest useful shipped version.
- What's in scope and what's explicitly deferred.
- The order of dependencies between pieces of work.

Don't prematurely end the conversation. If the user says "okay just file something" but the scope is still fuzzy, push once more before complying.

### 3. Decompose into issues

When the scope is clear, break the work into ordered GitHub issues. Rules:

- **Each issue must be self-contained** — cog's `build` phase will implement it in isolation, starting from `main`. An issue that depends on a not-yet-merged issue is a broken issue.
- **Order by dependency.** List blocking issues first.
- **Each issue must be implementable.** If an issue reduces to "think about X," it's not an issue — it's a conversation you need to have now.

For each issue, draft:
- **Title** — imperative, specific, under 80 characters.
- **Description** — the change, grounded in the files it touches.
- **Acceptance criteria** — bulleted, concrete, testable.
- **Affected components** — paths.
- **Technical context** — constraints, patterns to follow, gotchas from the codebase investigation.

### 4. Present for approval, then file

Show the user the full issue list with titles and one-line summaries. For any issue the user wants to drop, edit, or merge with another, iterate until they're satisfied. Then file all approved issues in order:

```bash
gh issue create --title "<title>" --body "<body>"
```

Report the URLs in the order filed.

## Principles

- **The smallest useful version ships first.** Decomposition is not "slice the elephant evenly"; it is "find the leg that, shipped alone, would already walk."
- **Challenge politely but honestly.** Your job is to save the user from filing a month of work that doesn't survive first contact with the codebase. That requires pushing back on bad framings.
- **Don't pad.** Two focused issues beat six aspirational ones.
