---
name: create-pr
description: Open a pull request for the current branch, with a body written from the branch's own diff. Use when the user says "open a PR", "create the PR", or invokes /create-pr.
user-invocable: true
---

# Create a pull request

This skill writes the pull request body from the branch's own diff, runs the repo's gates, pushes, and opens the PR.

## Step 1 - The body

Read `git log <base>..HEAD` and `git diff <base>...HEAD`. Write the body as markdown to a file in the scratchpad directory:

- **What changes**: one line per behavior change the branch makes, taken from the code and not from the commit subjects, each naming the files behind it.
- **Why**: one short paragraph, only where the diff does not already say it.
- **Verification**: the gate commands from Step 2 and their results.

Leave out a section that is empty. When the branch was reviewed this session, the review's behavior lines are the body's.

## Step 2 - Gates

This is the one moment the repo's gates run. Find them where the repo names them: its own instruction file, `package.json` scripts, the CI workflow. Run lint and tests on the branch head.

A failing gate stops the skill. Show the output and ask. Never open a PR over a red gate without the user saying so.

## Step 3 - Push and open

```bash
git push -u origin <branch>
gh pr create --base <base> --title "<title>" --body-file <scratchpad>/pr-body.md
```

The title is one line under 70 characters, conventional prefix, imperative, no period, in the style of `gh pr list --state merged --limit 20 --json title`. An issue id in those titles belongs to other work. Never copy one.

An open PR for the branch already exists when `gh pr list --head <branch> --state open` returns one. Update its body with `gh pr edit --body-file` instead of opening a second.

No attribution anywhere in the title or body: no `Co-Authored-By`, no generated-with footer, no session URL. A hook rejects the command when one slips through.

### When the branch is in a stack

Both commands above are wrong there. `gh stack push` sends the chain, then `gh stack submit` opens or updates every PR in it, including this branch's.

## Step 4 - Finish

End with the PR url and nothing else.
