---
name: create-pr
description: Open a pull request for the current branch with the branch's brief as the body, then hand over the brief image to drag in. Use when the user says "open a PR", "create the PR", or invokes /create-pr.
user-invocable: true
---

# Create a pull request

The branch's brief is the pull request. This skill pushes the branch, opens the PR with the brief's markdown as the body, and ends with the PNG path so the user drags the picture in.

GitHub has no API that uploads an image into a PR body. Only a browser drag does it. Never claim the image is in the PR; hand over the path and say what to do with it.

## Step 1 - The brief

Look in `~/.claude/briefs/<repo>/<branch>/`, where `<repo>` is the checkout's directory name and `<branch>` is `git rev-parse --abbrev-ref HEAD`.

- `review.json` is the body. It describes what the branch did, with proof.
- Only `proposal.json` there means the branch was planned but never reviewed. Say so and ask whether to open the PR from the proposal or write the review first.
- Neither means there is no brief. Load the `review` skill to produce one. Do not open a PR without a brief.

Render it, and fix every problem the renderer names before going on:

```bash
node ~/.claude/skills/brief/render.mjs ~/.claude/briefs/<repo>/<branch>/review.json
```

The renderer prints the `.html`, `.md`, and `.png` paths. `no png` means playwright-core was not found, and the PR gets the markdown alone.

## Step 2 - Gates

This is the one moment the repo's gates run. Find them where the repo names them: its own instruction file, `package.json` scripts, the CI workflow. Run lint and tests on the branch head.

A failing gate stops the skill. Show the output and ask. Never open a PR over a red gate without the user saying so.

## Step 3 - Push and open

```bash
git push -u origin <branch>
gh pr create --base <base> --title "<title>" --body-file ~/.claude/briefs/<repo>/<branch>/review.md
```

The title is one line under 70 characters, conventional prefix, imperative, no period, in the style of `gh pr list --state merged --limit 20 --json title`. An issue id in those titles belongs to other work. Never copy one.

An open PR for the branch already exists when `gh pr list --head <branch> --state open` returns one. Update its body with `gh pr edit --body-file` instead of opening a second.

No attribution anywhere in the title or body: no `Co-Authored-By`, no generated-with footer, no session URL. A hook rejects the command when one slips through.

### When the branch is in a stack

Both commands above are wrong there. `gh stack push` sends the chain, then `gh stack submit` opens or updates every PR in it, including this branch's.

## Step 4 - The image

End with the PR url and the PNG path, and one line saying to drag the PNG into the top of the body. Nothing else.
