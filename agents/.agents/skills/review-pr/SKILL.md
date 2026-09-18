---
name: review-pr
description: >
  Review a pull request: one reviewer reads the code in Jev's order, the result posts once as a comment with what changes, how to test it, blockers, and non-blockers, and the PR is approved when nothing blocks.
user-invocable: true
---

# Review a pull request

The user names a PR by number or URL. Read it with `gh pr view`, fetch its head, and check it out in a worktree of its own. Never comment, review, or approve until the last step, and never more than once per round.

You review, nobody else. No sub-agent gathers and no separate judge rules: the hand-off between them costs more than it saves, and a judge that cannot read the tree guesses.

## Step 1 - Take Jev's map

Write the PR title and description to a file in the scratchpad, then run `jev-map --about <that file> origin/<base>...origin/<head>` in the worktree. It prints the map, and the map is where reading starts:

- **Reading order**: the deep files by rank, the first of them marked to read whole, each with the lines Jev suspects and why. Then the files to skim, and the files to leave to the build.
- **Files**: the text of the files marked to read whole.
- **Diff**: deep files whole, skim and test files cut short, ignore files named only. Open a file for what is cut.

Take the order as given. Change it only when the code shows the ranking is wrong, and say why. State the resulting reading order in one compact list before reading further, so the allocation is visible and deliberate.

A suspected line is a place to look, not a finding. Confirm or dismiss from the code.

## Step 2 - Read in batches

Every tool call sends the whole conversation to the model again, so ten small reads cost ten times what one read of the same files costs. When you know the next several files or searches you need, run them in one command. One call per question, not one per file.

Bugs live in the connections. For every file that matters, read what it calls, what calls it, what tests it, the counterpart it was copied from, and the docs that describe it. Gather them in one batch per file, not one call each.

Imports do not show everything. Also look for:

- Code wired together without an import: a route, a string key, dependency injection, dynamic dispatch, a config value.
- Configuration that alters the changed code's behavior.

State your premises explicitly. Never write "this function probably does X". Read the function and record what it does. If you find yourself guessing from a name, stop and read it.

## Step 3 - Trace the flows

Trace the execution path of every significant change:

1. **Entry**: where execution enters it. An API handler, a UI event, a cron job.
2. **Steps**: what data comes in, how it is transformed, where it goes.
3. **Exits**: every way it can complete. Success, error, early return, exception.
4. **Effects**: what state it modifies. Database writes, the file system, cache, global state, UI state.
5. **Failure**: what happens when a dependency fails. Network errors, null values, invalid input, a second writer.

## Step 4 - Walk the state

Most missed bugs are an untraced scenario, not an unread file.

For each piece of state the diff introduces or touches (component state, refs, effect dependency arrays, caches, query keys, pending flags, persisted rows), list every writer and every reader. Then hold the mechanism against each of these:

1. Initial mount or first load.
2. The state changes while its target is rendered or visible.
3. The state changes while its target is not rendered, virtualized away, unmounted, or detached.
4. An external actor mutates the surroundings: scroll, resize, navigation, refetch, a second writer.
5. The data is empty, or becomes empty after it was populated.
6. The flow is interrupted halfway.

And the shapes reviews keep finding:

- A write whose success path refreshes fewer places than show the data it changed.
- A failed request rendered as an empty, default, or loading state.
- A control that renders enabled and does nothing, or a prop accepted and never used.
- State set on one transition and never reset on the way back.
- A route, control, or behavior reachable outside the flag or check the PR says gates it.
- A walkthrough under `docs/` that describes a label, order, color, or behavior the code no longer has.
- A copy that diverges from the file it was ported from on a path that matters.

## Step 5 - Correctness and conventions

Judge the code for correctness, and for the codebase's own conventions: its architecture, its UI patterns, its code quality. Following the patterns already in the codebase matters most. Look for where the new code deviates from a well established pattern.

## Step 6 - Challenge every finding

For every issue you are about to report, challenge it:

1. **Is it real?** Name the code path that triggers it, and the specific input or state that reaches it.
2. **Is it new?** If the problem stood before this change, do not flag it.
3. **Is it provable?** Cite the file and line where the problem is, and the file and line of the code that interacts with it badly.
4. **Would you bet on it?** If the author said "that's not a bug", could you prove them wrong from the code?
5. **Is it fix-ready?** Sketch the fix and name every file it touches. Read each one. Many candidate issues die here, when the fix reveals code that already handles the case. Report only findings whose fix you could start immediately.
6. **Is it the right severity?** Do not say "this will crash" when you mean "this could return an unexpected value in an edge case". Calibrate the language to the actual impact.

When a snippet, a scratch script, or a quick run would prove or kill a finding, write it in the scratchpad, run it, and go by what it says. Never modify the worktree.

Read the PR description and comments last. Drop any finding the conversation already covers.

## Step 7 - The comment

Write the comment body as markdown to a file in the scratchpad directory. Nothing else is written anywhere. Write for the person who reads it, not for the agent that wrote the code. They will not open the code.

- **What changes**: a table with a Before and an After column, one row per behavior this change adds, removes, or alters, in reading order. Each cell eight words or fewer, saying what happens to the user, not what the code does: "A new version opens with nothing ticked", not "state is keyed by version". Built from the code and never from the PR description. Never cap the list or merge rows to shorten it.
- **How to test**: one bold line per user flow the change touches, then numbered steps: how to reach it in the product and what should happen, one action per step, each a sentence a tester can follow.
- **Blockers**: the issues that must change before an approve. One line each: the claim, then the one `path:line` it rests on in backticks, the line the problem is at and not the line that reveals it.
- **Non-blockers**: the improvements the author may take or leave, in the same shape.

No field names, file names, or placeholder shapes inside a table cell or a step. A path belongs on a finding.

Leave out a section that is empty.

## Step 8 - Post

First write every blocker and non-blocker as JSON to the scratchpad, `[{"claim": "...", "where": "path:line"}]`, and run `jev-check <that file>`. A finding whose line comes back `weak` is not carried by the code it cites: a blocker moves to the non-blockers with a note saying so, and a non-blocker is dropped. Tell the user what moved or dropped.

With blockers: show the blockers in chat and ask before anything posts. The user says post, or answers the findings. An answer re-enters Step 6 with the user's words: read whatever code it turns on, adjust where they are right, keep what you can still prove, and ask again.

Without blockers, or when the user says post:

```bash
gh pr comment <number> --body-file <scratchpad>/review.md
```

When nothing blocks and the user is a requested reviewer, `gh pr review <number> --approve`. Your own PR refuses an approve; say so and move on.

Remove the worktree. End with the comment url and the blocker count, and nothing else.
