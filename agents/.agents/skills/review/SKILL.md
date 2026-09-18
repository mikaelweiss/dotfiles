---
name: review
description: >
  Review a set of code for issues
user-invocable: true
---

# Review a set of code

The user will either ask you to review a branch, a PR, or a certain diff like the uncommited code

## Safety guarantee

This review is read-only and non-destructive:
- Never commit code under any circumstance, not even temporarily for verification
- Never modify files in the working tree
- Always restore the working state exactly as it was when review started
- Any temporary verification (scratch scripts, test outputs, etc.) runs in the scratchpad directory only
- Clean up all temporary files before the review ends

## Step 1 - Organize

Run `jev-map` with the same revision arguments as the diff under review: no arguments for uncommitted work, `main...HEAD` for a branch, `origin/<base>...origin/<head>` after a fetch for a PR. It prints the map: the reading order with the deep files by rank and the lines Jev suspects, the text of the files to read whole, and the diff with deep files whole, skim and test files cut short, and ignore files named only. Open a file for what is cut.

Take the tiers and the order as given. Change a row only when the code shows the ranking is wrong, and say why on that row. State the resulting reading order in one compact grouped list before reading further, so the allocation is visible and deliberate.

1. Ignore/tool-verify - these are files that don't really matter to review and were most likely set up right, or things that a command checks better than reading.
2. Skim - these are files that don't have high impact if incorrect in some way, but it'd be good to look at just in case
3. Deep - these are files that are high impact and should be carefully reviewed, in rank order: the top third whole, the rest from the diff, opened only when the diff and its callers do not settle what it does.

The rank is where to look, not what is wrong. Confirm or dismiss from the code.

Run basic repo commands to verify that the code is in a good state, or if it isn't, you now have the baseline for as you review

## Step 2 - Skim

Skim the type 2 files found in `Step 1` for anything that might cause issues

## Step 3 - Deep

Follow these steps for each of the high impact files:

### Read in batches

Every tool call sends the whole conversation to the model again, so ten small reads cost ten times what one read of the same files costs. When you know the next several files or searches you need, run them in one command. One call per question, not one per file.

### Read related code to answer named questions

Bugs live in the connections, so follow the connections of what changed, not the neighborhood around it:

- Callers of every new or changed exported symbol. Find them with grep or ast-grep, then read the enclosing function at each call site.
- Functions the changed code calls, when their behavior matters to the change.
- Types, schemas, and contracts the changed code implements or consumes.
- Configuration that alters the changed code's behavior.
- The counterpart implementation, when the change claims parity with existing code.
- The walkthroughs under `docs/` that name the labels and controls the change touches.

### Trace the end-to-end flow

Trace the execution path of every significant change:

1. **Entry point**: where does execution enter this code? (API handler, UI event, cron job, etc.)
2. **Data flow**: what data comes in? How is it transformed? Where does it go?
3. **Exit points**: what are all the ways this code can complete? (success, error, early return, exception)
4. **Side effects**: what state does this code modify? (database writes, file system, cache, global state, UI state)
5. **Failure modes**: what happens when dependencies fail? (network errors, null values, invalid input, concurrent modification)

State your premises explicitly. Do not say "this function probably does X". Read the function and confirm what it actually does. If you find yourself guessing what a function does based on its name, stop and read it.

### Enumerate scenarios for stateful mechanisms

Most missed bugs are an untraced scenario, not an unread file.

For each piece of state the diff introduces or touches (component state, refs, effect dependency arrays, caches, query keys, pending flags, persisted rows), list every writer and every reader. Then check the mechanism against each of these scenarios:

1. Initial mount or first load.
2. The state changes while its target is rendered or visible.
3. The state changes while its target is not rendered (virtualized away, unmounted, detached).
4. An external actor mutates the surroundings: scroll, resize, navigation, refetch, a second writer.
5. The data is empty, or becomes empty after it was populated.
6. The flow is interrupted halfway.

And the shapes reviews keep finding:

- A write whose success path refreshes fewer places than show the data it changed.
- A failed request rendered as an empty, default, or loading state.
- A control that renders enabled and does nothing, or a prop accepted and never used.
- State set on one transition and never reset on the way back.
- A route, control, or behavior reachable outside the flag or check that gates its neighbours.
- A walkthrough under `docs/` that describes a label, order, color, or behavior the code no longer has.
- A copy that diverges from the file it was ported from on a path that matters.

## Step 4 - Correctness

Review the code for correctness. Things like code base conventions and things like that. Make sure that good architectural patterns are followed, good UI patterns, good code quality, et cetera. It's especially important to follow the code base architecture and patterns. You're specifically looking for issues where the new code deviates from well established patters.

## Step 5 - Verify

For every issue you are about to report, challenge it:

1. **Is it real?** Read the actual code path that triggers the bug. Can you name the specific input or state that causes it?
2. **Is it new?** Check if this issue existed before the change. If it did, do not flag it.
3. **Is it provable?** Can you cite the specific file and line where the problem occurs, and the specific file and line of the code that interacts with it badly?
4. **Would you bet on it?** If the author pushed back and said "that's not a bug", could you prove them wrong by pointing to concrete code?
5. **Is it fix-ready?** Sketch the fix. Name every file the fix would touch and confirm you have read each one. If the sketch needs a file you have not read, read it now, then re-test the finding against what you learned. Many candidate issues die here, when the fix attempt reveals code that already handles the case. Report only findings whose fix you could start immediately.
6. **Is it the right severity?** Do not say "this will crash" when you mean "this could return an unexpected value in an edge case". Calibrate your language to the actual impact.

## Step 6 - Prove every behavior

Every behavior change the diff makes gets a proof before it is reported: a command you ran, a test you ran, or a scratch reproduction you built, each with its result. A finding needs the same.

Do NOT modify the working tree. Use the scratchpad directory only:
- Run tests with `npm test` or similar (against committed/staged code as-is, no temp commits)
- Extract reproduction scripts to the scratchpad and run them there
- Use `git diff` or `git show` to analyze the actual code paths without modifying anything

Proof is out of reach only when it needs something you cannot have: production data, a paid external service, a physical device. Then say what you needed in one sentence and report it as a human check.

## Step 7 - Report

The review is a chat report. Write no files and render nothing. Write for the person who reads it, not for the agent that wrote the code.

1. **What changes**: a table with a Before and an After column, one row per behavior change the diff makes, in reading order, then the files behind it and the proof from Step 6. Each cell eight words or fewer, saying what happens to the user, not what the code does. Never cap the list or merge rows to shorten it.
2. **How to test**: one bold line per user flow the change touches, then numbered steps: how to reach it in the product and what should happen, one action per step.
3. **Blockers**: what will cause problems. One line each: the claim, then the one `file:line` it rests on, the evidence, and the fix. Before reporting, write every blocker and non-blocker as JSON to the scratchpad, `[{"claim": "...", "where": "path:line"}]`, and run `jev-check <that file>`. A finding whose line comes back `weak` is not carried by the code it cites: a blocker is reported as a non-blocker with a note saying so, and a non-blocker is left out.
4. **Non-blockers**: the correctness items from Step 4 and anything that needs a human eye, in the same shape.
5. **Human checks**: anything Step 6 could not prove, each naming what you needed.

Leave out a section that is empty. Nothing else goes in the report: no diff summary, no praise, no next steps.

## Step 8 - Cleanup

Before finishing:
- Verify the working tree is exactly as it was at the start with `git status`
- Delete any temporary files created in the scratchpad during verification
- Confirm no uncommitted changes were introduced to the repo
