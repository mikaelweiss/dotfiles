---
name: brief
description: Render a change brief: one page that lists every behavior change with its files, risk, test, flows, and boundary map. Used by /plan before code and by /review and /review-pr after. Load when a skill says to write a brief, or when the user asks for one.
---

# Brief

One JSON file in, one page out. The page is the deliverable; chat carries only the path and what the user must decide.

```bash
node ~/.claude/skills/brief/render.mjs <dir>/<name>.json
open <dir>/<name>.html
```

Output lands next to the JSON: `<name>.html` (interactive), `<name>.png` (one image for a PR body or comment), `<name>.md` (text for a PR comment). The renderer looks for `playwright-core` in this folder, then the current repo, then `~/code/surestake`. Without it the HTML and markdown still render and the command prints `no png`.

Briefs live at `~/.claude/briefs/<repo>/<branch>/`. A proposal is `proposal.json`. A review is `review.json`. Never inside a repo, never in git.

## The shape

Copy `example.json` in this folder and fill it. Every field below; nothing else.

| Field | What it holds |
|---|---|
| `title` | The task, as a short noun phrase |
| `mode` | `proposal` or `review` |
| `branch` | `<repo> / <branch>` |
| `user` | One or two sentences: what a user can do after this that they could not before, or what changes for them |
| `behaviors` | One entry per behavior change, in reading order. See below |
| `flows` | One entry per user flow touched. `name`, `items` (behavior numbers), and either `steps` (how to reach it in the UI, one action per step) or `effect` (what the user gains or loses when there is nothing to click) |
| `touched` | One entry per area of the codebase changed: `name` as `<project> / <area>`, `files` count |
| `changed_files` | Every file the change creates or edits: `[kind, path]`, kind is `create` or `edit`. In a review this is `git diff --name-status` |
| `map` | `layers` (column titles, left to right), `nodes` (`id`, `name`, `layer`, `changed`: `create`, `edit`, or null, `files`), `edges` (`from`, `to`, `kind`: `new`, `existing`, `removed`, `label` of one to three words) |
| `questions` | Proposal only. Each: `q`, `options` (short, two to four), `recommend` (one of the options, verbatim), `detail` |
| `findings` | Review only: `blockers` and `nonBlockers`, one specific actionable line each |
| `delta` | Review only, when `proposal.json` exists for the branch: `kind` is `added`, `dropped`, or `changed`, `text` names the behavior |

A behavior entry:

| Field | What it holds |
|---|---|
| `before` | Eight words or fewer. What happens today |
| `after` | Eight words or fewer. What happens after |
| `risk` | `low`, `med`, `high` |
| `files` | The files this behavior creates or edits, `[kind, path]`. Every file in `changed_files` must appear on some behavior or map node, or the page flags it |
| `test` | Proposal: the test that will pin it, or `null`. Review: not used |
| `verified` | Review only: the test name, walkthrough step, or command that proves it. Absent means not verified and the page says so |
| `detail` | Two or three sentences the reader sees when they open the row. The reasoning, the trade-off, the gotcha |

## Rules

- The list is as long as the number of behavior changes. Never cap it, never merge lines to shorten it.
- `before` and `after` are the whole row. Put everything else in `detail`.
- A file no line explains is a finding, not a footnote. Explain it or list it under a behavior.
- Risk is about the blast radius if the line is wrong, not about how hard it was to write.
- Every number on the page is the reply key. Do not renumber between renders of the same brief.

## Reading the reply

The user pastes what the page copied:

```
---
## Notes from "<title>"
3. a
5. use the existing helper instead
Other: ...
---
```

A number with `ok` or nothing is approved. A number with a letter is the option picked. A number with text is a change to make before starting. Anything not listed is approved. `Other` applies to the whole brief.
