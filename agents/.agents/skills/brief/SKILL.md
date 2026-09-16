---
name: brief
description: Render a change brief: one page that lists every behavior change with its files, risk, proof, flows, findings, changed files, and boundary map. A proposal before code, a review after. Load when a skill says to write a brief, or when the user asks for one.
---

# Brief

One JSON file in, one page out. The page is the deliverable; chat carries only the path and what the user must decide.

```bash
node ~/.claude/skills/brief/render.mjs <dir>/<name>.json --open
```

Output lands next to the JSON: `<name>.html` (interactive), `<name>.png` (one image for a PR body or comment), `<name>.md` (text for a PR comment). `--open` shows the page: when the browser already has it in a tab, that tab reloads and comes forward, otherwise it opens once. Leave the flag off when nobody needs to see the page, as for a PR comment. The renderer looks for `playwright-core` in this folder, then the current repo, then every repo under `~/code`. Without it the HTML and markdown still render and the command prints `no png`.

The renderer validates the JSON before writing anything. A bad brief renders nothing and prints one line per problem, naming the field. Fix every line and run it again.

Briefs live at `~/.claude/briefs/<repo>/<branch>/`. A proposal is `proposal.json`. A review is `review.json`. Never in the repo the brief is about, and never committed. The path resolves into the dotfiles tree, which mutagen syncs, so a brief rendered over ssh opens on any machine.

Every render that changes the brief saves a copy under `history/` as the next version: v1, v2, and so on. The page shows its version top right with a menu to switch. An earlier version opens read only, with the ticks and notes the user made on it. The newest version's page also lists, under History, each version's notes and what changed in it.

## The shape

Copy `example.json` (proposal) or `example-review.json` (review) in this folder and fill it. Every field below; nothing else.

| Field | What it holds |
|---|---|
| `title` | The task, as a short noun phrase |
| `mode` | `proposal` or `review` |
| `branch` | `<repo> / <branch>` |
| `user` | One or two sentences: what a user can do after this that they could not before, or what changes for them |
| `notes` | The notes the user pasted in chat, verbatim, when this render answers them. Leave it out on the first render. The page shows them under the version they produced |
| `behaviors` | One entry per behavior change, in reading order. See below |
| `flows` | One entry per user flow touched. `name`, `items` (behavior numbers), and either `steps` (how to reach it in the UI, one action per step) or `effect` (what the user gains or loses when there is nothing to click) |
| `touched` | One entry per area of the codebase changed: `name` as `<project> / <area>`, `files` count |
| `changed_files` | Every file the change creates, edits, or deletes: `[kind, path, note, why]`. `kind` is `create`, `edit`, or `delete`. `note` is one line on what changes in that file; required in a review. `why` is one line on why that file has to change, shown when the row opens; optional. In a review this list is `git diff --name-status` (A is create, M is edit, D is delete). The page groups the files under the behavior change that names them, first one wins, and each file carries the numbers of every behavior that lists it |
| `map` | `layers`: column titles left to right, for example `["Entry", "Logic", "Storage"]`. `nodes`: `id`, `name`, `layer` (one of the titles, verbatim), `changed` (`create`, `edit`, `delete`, or `null`), `files` (a list of paths, for example `["src/auth/reset-limiter.ts"]`). `edges`: `from` and `to` are node ids, `kind` is `new`, `existing`, or `removed`, `label` is one to three words |
| `questions` | Proposal only. Each: `q`, `options` (short, two to four), `recommend` (one of the options, verbatim), `detail` |
| `findings` | Review only: `blockers` and `nonBlockers`. See below |
| `delta` | Review only, when `proposal.json` exists for the branch: `kind` is `added`, `dropped`, or `changed`, `text` names the behavior |

A behavior entry:

| Field | What it holds |
|---|---|
| `before` | Eight words or fewer. What happens today |
| `after` | Eight words or fewer. What happens after |
| `risk` | `low`, `med`, `high` |
| `files` | The files this behavior creates, edits, or deletes, `[kind, path]`. Every file in `changed_files` must appear on some behavior or map node, or the page flags it |
| `test` | Proposal: the test that will pin it, or `null`. Review: not used |
| `verified` | Review: the command, test, or scratch reproduction that proves the behavior, with its result. Required unless `why` is present |
| `why` | Review: only when proof is out of reach (production data, a paid service, a physical device). One sentence saying what you needed and could not have. The page lists the line under Non-blockers as a human check |
| `detail` | Two or three sentences the reader sees when they open the row. The reasoning, the trade-off, the gotcha |

A finding entry (`blockers` and `nonBlockers` alike):

| Field | What it holds |
|---|---|
| `title` | One line naming the problem, as the reader sees it before opening the row |
| `where` | `path:line`, or the path when there is no single line |
| `items` | The behavior numbers this finding puts at risk. `[]` when it belongs to none |
| `detail` | The evidence and the fix: the input or state that triggers it, the code that interacts badly, what to change |

A blocker is what will cause problems if merged. A non-blocker is a correctness or convention item, or anything that needs a human eye.

## Rules

- The list is as long as the number of behavior changes. Never cap it, never merge lines to shorten it.
- `before` and `after` are the whole row. Put everything else in `detail`.
- A file no line explains is a finding, not a footnote. Explain it or list it under a behavior.
- `note` says what changes, `why` says why it has to. Neither restates the path.
- Risk is about the blast radius if the line is wrong, not about how hard it was to write.
- Every number on the page is the reply key. Keep lines in place between versions. A dropped line shows in History under its old number, and a moved line names both numbers.

## Writing

Write for the person who reads the page, not for the agent that implements it. They will never open the code.

- Say what happens to the reader, not what the code does. "A new version opens with nothing ticked", not "state is keyed by version".
- No field names, file names, or placeholder shapes inside a sentence. A path belongs on a file row, not in prose.
- A test line says what to do and what the reader should see, in one or two sentences.
- No labels such as "Invariant:". Write the fact as a plain sentence.
- Read every line as if aloud. If it needs the code to make sense, rewrite it.

## Reading the reply

A proposal page copies approvals and notes by number, with the version they were made on:

```
---
## Notes from "<title>" v1
- 3. a
- 5. use the existing helper instead
Other: ...
---
```

A number with `ok` or nothing is approved. A number with a letter is the option picked. A number with text is a change to make before starting. Anything not listed is approved. `Other` applies to the whole brief.

Put the whole reply into `notes` verbatim, make the changes, and render with `--open`. The next version shows the reply and what it changed. Replace `notes` with each new reply; never append.

The proposal page also copies a prompt, from Copy as prompt beside Copy notes. It is the implement command with the path of the proposal, then the same notes block. Paste it into a fresh session: the implement skill reads the proposal from the path, applies the notes, builds each line, and ends by comparing what it built to each line.

A review page copies a prompt for a fresh session. It carries the branch, then each finding the user ticked or annotated with its full text, each behavior or file the user annotated, and the closing notes. It is complete on its own: the agent that receives it does not need the page.
