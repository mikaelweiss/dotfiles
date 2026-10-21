---
name: review-pr
description: >
  Review a pull request the way penguin's review-pr workflow does: triage it first, review it in Jev's order, post the findings, approve when nothing blocks, and re-review every push until it merges or closes.
user-invocable: true
---

# Review a pull request

The user names a PR by number or URL. Run from the repository's checkout. Every file you write goes in the scratchpad, never in the worktree. `watch` is the script beside this file.

Never comment, review, or approve except where a step says to. Never sign a comment.

## Step 1 - Read the PR

```bash
gh pr view <pr> --json number,title,body,state,isDraft,baseRefName,url,comments
```

- No PR: say `<pr> names no pull request` and stop.
- Not `OPEN`: say `PR #<n> is <state>, nothing to review` and stop.

Use the url for every later call.

## Step 2 - Triage

```bash
gh pr view <url> --json title,body,comments --jq '{title, description: .body, comments: [.comments[] | {author: .author.login, body}]}' > <scratchpad>/pr.json
gh pr diff <url> | jev-map triage <scratchpad>/pr.json
```

- `review ...`: go on to Step 3.
- `eyeball <reason>`: ask `PR #<n> is small enough to read yourself: <reason>`, then the url, then `review runs the full review, mine leaves it to you.`
  - `mine`: say `PR #<n> is yours to read` and stop.
  - `review`: the answer can come hours later, so repeat Step 1's checks before going on.
- The command fails: say `The Jev triage did not run, so the full review does: <error>` and go on.

## Step 3 - Sweep

A review stopped mid-run leaves its worktree behind. List `git worktree list --porcelain`. For every path named `review-pr-<number>` other than this PR's, read `gh pr view <number> --json state`. When the PR is not open or no longer reads, `git worktree remove --force <path>` and say `swept the worktree for PR #<number>: it is <state or gone>`. When the remove fails, say `the worktree for PR #<number> stayed: <error>`.

## Step 4 - The loop

Repeat until the PR closes:

1. `watch snap <url> > <scratchpad>/now.json`. A `state` other than `OPEN` ends the review: say `PR #<n> is <state>` and go to Step 9.
2. A round is owed when no round has run yet, or `headRefOid` is not the commit the last round read.
3. When a round is owed and the PR is neither `isDraft` nor `isInMergeQueue`, run Steps 5 to 8, then repeat.
4. Otherwise wait:
   - Remove the worktree (`git worktree remove --force <path>`). On failure say `the worktree stayed: <error>` and go on.
   - Say `waiting for changes on PR #<n>`.
   - Run `watch wait <url> <scratchpad>/now.json` with `run_in_background`. It exits on the first change and prints one line per change. Say what each one means: `draft` waits, `ready` resumes, `queued` says `PR #<n> is queued to merge, the review waits`, `dequeued` says `PR #<n> left the merge queue`, `commits` owes a round. Then repeat.

## Step 5 - The round

Say `review round <k>`.

**The tree.** The worktree is `~/worktrees/<repo>/review-pr-<n>`, where `<repo>` is the directory name of the main checkout from `git rev-parse --git-common-dir`. When none is open, `git fetch origin pull/<n>/head` and `git worktree add --detach <path> FETCH_HEAD`. When the path is already taken, ask: `use` works in it, `replace` removes it and cuts a fresh one, `exit` stops the review (go to Step 9).

**Sync.** The worktree only mirrors the PR head, so a force-push is a reset, not a merge:

```bash
git -C <wt> fetch origin <base>
git -C <wt> fetch origin pull/<n>/head
git -C <wt> reset --hard FETCH_HEAD
git -C <wt> rev-parse HEAD
watch snap <url> > <scratchpad>/round.json
```

When `round.json`'s `headRefOid` is not `HEAD`, sync again. `HEAD` is the commit this round reads. Read title, body, comments, and base again with `gh pr view`. A description or comment that lands mid-round is context: read it before Step 7.

**The map.** Write the title and description to `<scratchpad>/about.md`, then:

```bash
bun --cwd <wt> "$(command -v jev-map)" --about <scratchpad>/about.md origin/<base>...HEAD
```

It prints the reading order, the files to read whole, and the diff cut by tier. Say `Jev screened <files> files: <deep> to read closely`, the file count from its stderr and the deep count from its reading order. When it fails, say `The Jev pass did not run: <error>` and read the whole diff from `gh pr diff <url>` instead.

**Earlier findings.** From the second round on, the tree holds new code. Read it again rather than trusting what an earlier round read. Check each finding from the last round against it: keep the ones that still hold, drop the ones the new code fixes, and return the full updated findings.

Then review, with the steps below.

### Read in batches

Every tool call sends the whole conversation to the model again, so ten small reads cost ten times what one read of the same files costs. When you know the next several files or searches you need, run them in one command. One call per question, not one per file.

Do not run `git diff` or `git log` to rebuild what the map already holds.

### Read in order

Take the reading order. Read the files given whole, in that order, with the suspected lines first. Read the rest of the deep files from the diff and open one only when the diff does not settle what it does. Skim the skim files for anything that might cause trouble. Leave the ignore files to the build.

Change the order only when the code shows the ranking is wrong.

A suspected line is a place to look, not a finding. Confirm or dismiss it from the code.

### Follow the connections

Bugs live in the connections. For every file that matters, read what it calls, what calls it, what tests it, the counterpart it was copied from, and the docs that describe it. Gather them in one batch per file, not one call each.

Imports do not show everything. Also look for:

- Code wired together without an import: a route, a string key, dependency injection, dynamic dispatch, a config value.
- Configuration that alters the changed code's behavior.

State your premises explicitly. Never write "this function probably does X". Read the function and record what it does. If you find yourself guessing from a name, stop and read it.

### Trace the flows

Trace the execution path of every significant change:

1. **Entry**: where execution enters it. An API handler, a UI event, a cron job.
2. **Steps**: what data comes in, how it is transformed, where it goes.
3. **Exits**: every way it can complete. Success, error, early return, exception.
4. **Effects**: what state it modifies. Database writes, the file system, cache, global state, UI state.
5. **Failure**: what happens when a dependency fails. Network errors, null values, invalid input, a second writer.

### Walk the state

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

### Correctness and conventions

Judge the code for correctness, and for the codebase's own conventions: its architecture, its UI patterns, its code quality. Following the patterns already in the codebase matters most.

### Challenge every finding

For every issue you are about to report, challenge it:

1. **Is it real?** Name the code path that triggers it, and the specific input or state that reaches it.
2. **Is it new?** If the problem stood before this change, do not flag it.
3. **Is it provable?** Cite the file and line where the problem is, and the file and line of the code that interacts with it badly.
4. **Would you bet on it?** If the author said "that's not a bug", could you prove them wrong from the code?
5. **Is it fix-ready?** Sketch the fix and name every file it touches. Read each one. Many candidate issues die here, when the fix reveals code that already handles the case. Report only findings whose fix you could start immediately.
6. **Is it the right severity?** Do not say "this will crash" when you mean "this could return an unexpected value in an edge case". Calibrate the language to the actual impact.

When a snippet, a scratch script, or a quick run would prove or kill a finding, write it in the scratchpad, run it, and go by what it says.

### Check the conversation

Read the PR description and comments to verify each finding is new. Drop a finding the conversation already covers.

### The findings

Write for the person who reads the comment, not for the agent that wrote the code. They will not open the code.

- **Behaviors**: every behavior this change adds, removes, or alters, one each, in reading order. `before` and `after` are eight words or fewer and say what happens to the user, not what the code does: "A new version opens with nothing ticked", not "state is keyed by version". Never cap the list or merge entries to shorten it.
- **Flows**: the user flows the change touches. A name for what the flow does, then the steps: how to reach it in the product and what should happen, one action per step, each a sentence a tester can follow.
- **Blockers**: the issues that must change before an approve. **Non-blockers**: the improvements the author may take or leave. Each is a `claim`, one clear, specific, actionable line, and a `where`, the one `path:line` the claim rests on, spelled as the diff spells the path. It is the line the problem is at, not the line that reveals it. Use the path alone only when no single line carries the claim.

No field names, file names, or placeholder shapes inside a behavior or a step. A path belongs in `where`.

## Step 6 - Fresh, then vetted

**Fresh.** Run `watch since <url> <scratchpad>/round.json` after the review and after every answer turn in Step 7. Each line it prints ends the round, with nothing posted:

- `closed <state>`: say `PR #<n> is <state>, the review stops` and go to Step 9.
- `approved`: say `PR #<n> is approved, this round has nothing left to say`. The round counts as read. Back to Step 4.
- `draft`: say `PR #<n> went to draft, the review waits`. Back to Step 4.
- `queued`: say `PR #<n> is queued to merge, the review waits`. Back to Step 4.
- `commits`: say `New code was pushed to PR #<n>, the round starts over on it`. Back to Step 4, where a round is owed.

**Vetted.** Write every blocker and non-blocker as `[{"claim": "...", "where": "path:line"}]` to `<scratchpad>/claims.json`, then:

```bash
bun --cwd <wt> "$(command -v jev-map)" check <scratchpad>/claims.json
```

A line marked `weak` is a claim the code at its own cited line does not carry.

- A weak blocker stops blocking: it moves to the non-blockers with `. The code at this line does not show this` appended to its claim. Say `<d> of <total> blockers are not carried by the code they cite, so they no longer block.`
- A weak non-blocker is noise and is dropped. Say `<d> of <total> non-blockers are not carried by the code they cite, so they are dropped:` and list them.
- The check fails: say `The evidence check did not run, so every claim stands: <error>`.

## Step 7 - The gate

**The comment.** It carries an overview (What changes, How to test) only when no comment on the PR yet holds `<!-- penguin:overview -->` and this review has not posted one. Otherwise it carries only Blockers and Non-blockers. An empty section says `none`.

```markdown
<!-- penguin:overview -->

### What changes

| Before | After |
| --- | --- |
| <before> | <after> |

### How to test

**<flow name>**

1. <step>

### Blockers

- <claim> (`<where>`)

### Non-blockers

- <claim> (`<where>`)
```

Escape `|` inside a table cell and fold its whitespace to single spaces.

**With blockers.** When the user asked to post without confirming, post at once (Step 8) and say `Posted <count> blockers on PR #<n> without approving`. Otherwise show the comment without the marker line, then ask `Post this without approving?`

- `send`: post (Step 8) and say `Posted feedback on PR #<n> without approving`.
- Anything else is the user's answer. Answer it, read whatever code it turns on, adjust the findings where the user is right, keep what you can still prove, then run Step 6 again and ask again.

**Without blockers.** Post (Step 8), then `gh pr review <url> --approve`. Say `Approved PR #<n>`, or `The approve failed: <error>` when it is refused, as your own PR is. The review still counts.

## Step 8 - Post

A gate the user answers late must not post a verdict on code the review never read. Before posting, run `watch since <url> <scratchpad>/round.json`:

- `commits` among its lines: post nothing. Say `New code landed on PR #<n>, so nothing was posted. The next round reviews it and carries these findings in.` Back to Step 4.
- The command fails: say `GitHub did not name the PR head, so this stands on the code the review read.` and post.

Write the comment to `<scratchpad>/review.md` and run `gh pr comment <url> --body-file <scratchpad>/review.md`. The round's `HEAD` is now the commit the last round read. Back to Step 4.

## Step 9 - Done

Remove the worktree when one is open. End with the rounds run and the comments posted, and nothing else.
