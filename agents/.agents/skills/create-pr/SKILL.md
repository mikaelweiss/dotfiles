---
name: create-pr
description: Open a pull request for the current branch. Use when the user says "open a PR", "create the PR", or invokes /create-pr.
user-invocable: true
---

# Create a pull request

## Create the PR

- Write the body to follow the repo's PR conventions. Find them in the PR template (`.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/`, `docs/`, or the repo root) and in any docs the template or `AGENTS.md`/`CLAUDE.md` cite for PR bodies.
- Fill every template section. Keep each one short and plain. Use the template's own "none" / "n/a" when a section does not apply. Drop the template's HTML comments.
- When the repo has no template, write a short body: what changed and why.
- Write the body to a file in the scratchpad and pass it with `--body-file`.
- push the code and create a PR
- Put Jira keys where the repo's conventions say. When they say nothing, start the title with the ticket number (ex: "SS-134 feat: ...").
- No attribution anywhere in the title or body: no `Co-Authored-By`, no generated-with footer, no session URL.

## Watch for reviews

Wait for the AI reviewer to automatically respond with a review
Fix any major and minor issues it brought up, and then commit, push, respond to, and resolve the conversation
Wait for the AI reviewer again 'till it comes back with no findings, or the minor findings aren't worth fixing in this PR.
IF
the minor review findings change the scope of the PR significantly or are pre-existing issues, ask the user if they'd like to fix these issues or ignore.
You'll almost always want to fix the major blocking findings from the AI review bot, but every once in a while, it will change the scope a lot or be pre-existing, or there will be some other reason to ignore it. Bring these cases up with the user and wait for their judgment call.
Specifically tell the user:

- what the issue that was brought up is (explained very simply)
- the impact, risks, or benefits of fixing it
- if you think it should be part of this PR or not

Again: 99% of the time, you can make the judgement call on your own. Only involve the user when it's clear you need their input.

Once: the review bot doesn't come back with any findings, or no major findings
request review from k8devtx and brytoncoopertech

Wait for review from them

Once they respond,
Fix any issues they bring up following the same rules as with AI review
Commit and push, and request re-review from whoever reviewed it.
Continue 'till you have the approval from either one of them and then add the PR to the PR queue
Watch 'till the PR is merged

Once you have an approval from a person, you can pretty much ignore the AI review bot unless it has blocking findings.

Notes:
ALWAYS git fetch and rebase on main before pushing (fix any rebase conflicts)
ALWAYS check the pr again before pushing to make sure no other reviews came in while you were fixing things. Because the AI review bot runs on every push, we don't want to trigger it unnecessarily.

## Done looks like:

The PR is merged
