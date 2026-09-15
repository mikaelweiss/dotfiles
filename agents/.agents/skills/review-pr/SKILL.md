---
name: review-pr
description: >
  Review a pull request: a reader gathers the facts, the judge rules from the diff and the dossier, the result posts once as a brief with blockers and non-blockers, and the PR is approved when nothing blocks.
user-invocable: true
---

# Review a pull request

The user names a PR by number or URL. Read it with `gh pr view` and `gh pr diff`. Never comment, review, or approve until the last step, and never more than once per round.

## Step 1 - Gather

Spawn one sub-agent (`description` and `prompt` only, Opus 5) with the PR title, description, comments, base branch, changed files, and the diff. Its job is the `review-gather` procedure, and its report is the dossier:

- Every changed file with a tier (`ignore`, `skim`, `deep`), what the diff does to it, and what it read about it: callers of every new or changed exported symbol, functions the changed code calls, contracts it implements, config that alters it, the counterpart when parity is claimed. Each entry is one line with `file:line`.
- Every significant flow: entry, steps, exits, effects, each with `file:line`.
- Every piece of state the diff touches, with every writer and every reader, each with `file:line`.
- Facts a reader of the diff alone would have to guess: repo conventions, what a called function really does, how the code behaved before.
- The repo's own gate commands run on the PR head, with their output.

Facts only, no verdicts. Tell it not to write to GitHub.

## Step 2 - Judge

Judge from the diff and the dossier alone. Do not open the tree yourself. Walk each state mechanism through: first load, change while visible, change while not rendered, an external actor mutating the surroundings, empty data, interruption halfway.

Challenge every finding before it stands: is it real, is it new, is it provable with `file:line` from the diff or dossier, would you bet on it, is the fix ready, is the severity right. A finding you cannot prove from what you hold is a question. Collect the questions and spawn one more gather sub-agent with them, at most twice. Then rule on what you have and drop what is still unproven.

Read the PR description and comments last. Drop any finding the conversation already covers.

## Step 3 - The brief

Load the `brief` skill. Write `~/.claude/briefs/<repo>/pr-<number>/review.json` with `mode: review`: one behavior line per behavior change the diff makes, built from the code and never from the PR description, each with its files and its `verified` proof. `findings.blockers` and `findings.nonBlockers` hold the surviving findings, one specific actionable line each. `changed_files` is the PR's file list. Render it:

```bash
node ~/.claude/skills/brief/render.mjs ~/.claude/briefs/<repo>/pr-<number>/review.json
```

## Step 4 - Post

With blockers: show the page path and the blockers in chat and ask before anything posts. The user says post, or answers the findings. An answer re-enters Step 2 with the user's words; adjust where they are right, keep what you can still prove, and ask again.

Without blockers, or when the user says post:

```bash
gh pr comment <number> --body-file ~/.claude/briefs/<repo>/pr-<number>/review.md
```

When nothing blocks and the user is a requested reviewer, `gh pr review <number> --approve`. Your own PR refuses an approve; say so and move on.

End with the PNG path. The user drags it into the comment.
