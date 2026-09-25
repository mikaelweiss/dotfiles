I love simplicity and clarity. 10 well put words beat 100 sloppy ones that say the same thing. When you think a response is simple enough, it isn't. Simplify it again.

## Always

- Never type an em dash (U+2014). Use a period, comma, colon, parentheses, or a plain hyphen. Not a semicolon.
- Never say "likely". If you do not know, use your tools to find out. Never answer with assumptions in place of context you could have searched for.

<important if="you are spawning a sub-agent">

Spawn with `description` and `prompt` only, then read the final report from the tool result. Never pass `name`: it creates an addressable teammate with mailbox machinery. SendMessage back-and-forth is equally banned. Put every reporting requirement in the spawn prompt so the report stands alone. Use Opus or Sonnet, never Fable.
</important>

<important if="you are about to survey, scout, triage logs, or run a wide search">

Re-reading accumulated context costs more than producing output, so keep the main thread small. Delegate the reading to a sub-agent and ask for its conclusion plus the `file:line` behind it. Never pull a raw dump, a full log, or a wide search result into the main thread when a sub-agent can hand back the answer.
</important>

<important if="you are about to read a log file, JSONL transcript, or build output">

Never read one whole into context. Measure it with `wc -c` first. Over 10k characters, extract instead: a script that prints counts or summaries, a grep for the relevant lines, or a bounded slice (offset/limit, `head -c`). Reading a small slice to learn the format is fine. This covers `~/.claude/projects`, scratchpad output, and any generated artifact. It does not cover source code.
</important>

<important if="you are running a Bash command">

Never `cd` inside a Bash command. Pass absolute paths to every argument.
Give `rm` literal paths, never a variable like `$S/*.log`.

</important>

<important if="the user asks for a plan, or you are considering plan mode">

Enter plan mode only when I explicitly ask
</important>

<important if="you are doing code review">

Load the `review` skill. Never load the `code-review` skill.
</important>

<important if="you are writing a comment, docstring, README, or doc">

The default is no comment. Do not comment bad code, rewrite it: clear names and clear structure instead of prose explaining unclear code. Reach for a comment only for the rare thing that cannot live in the code.

Code says how, comments are a higher level. The only comment worth writing records intent the code cannot express: why this approach over the obvious one, the trade-off taken, the external constraint, the real gotcha. Never explain how the code works. A duplicate explanation goes stale the moment the code changes. DRY applies to comments: if one restates the code, delete it.

The same rule covers READMEs, docs, tables of constants, and test names. Prose that restates code is split brain. Delete it rather than update it.

Never narrate history. No contrasting the current approach with a previous one, no explaining what a migration changed, no reference to what the code "used to" do, "no longer" does, or "now" does "instead". No marking code "new", "updated", "migrated", or "old". No revision logs, author lists, or change logs in file headers. Git holds all of that. If a comment only makes sense to someone who knew the prior implementation, delete it.

When you do write one: present tense, active voice, one topic, short, no semicolon, no em dash, no marketing adjectives.
</important>

<important if="you are describing the state of work finished or a plan of work to be done">

Never call work "V1", "MVP", "first pass", "initial version", "basic implementation", "phase 1", or anything else implying a later version. Never defer with "for now", "we can add later", "future enhancement", "in a follow-up", or a TODO placeholder. That language pre-excuses incompleteness, and "later" never comes. Everything you ship is the version: complete, working, nothing silently deferred. If part of the task genuinely should not be done, raise it as a scope decision and let me decide. Do not cut scope and dress it up as a roadmap.
</important>

<important if="you need to ask me a question">

Give me a numbered list of questions. I prefer that over the AskUserQuestion tool.
</important>

<important if="you are writing a commit message">

- Conventional prefix (`fix:`/`feat:`/`refactor:`/`docs:`/`test:`/`chore:`), title 50 chars or fewer (hard max 72), imperative, no period. Be specific: `fix: resolve login timeout`, not `fix: bug fix`.
- Default to title-only. Add a body only when the why is not obvious from the diff.
- Body: one short paragraph, not bullets, explaining why. The diff shows what.
- No filler openers ("This commit...", "Updated...", "Changes include..."), no file listings, no restating the diff.
- No AI attribution anywhere: no `Co-Authored-By`, no 🤖, no "Generated with…" footer, no `claude.ai/code/session` URL, no `noreply@anthropic.com`, no "AI-assisted / AI-generated / with help from" phrasing, no `<!-- claude-* -->` markers. A PreToolUse hook blocks the commit if one slips through.
</important>

<important if="you are pushing branches or opening pull requests">
don't use github pr stacks. pushing branches and pr's stacked on top of each other is fine, but no native github pr stacks
</important>

<important if="you are rebuilding a machine's Nix configuration">

Use `nix-rebuild`, the alias in `~/.zshrc`. It picks the right flake and host for the machine it runs on. Never spell out `darwin-rebuild` or `nixos-rebuild`. From a non-interactive shell, including over ssh, run `zsh -ic nix-rebuild` on the target machine.
</important>

<important if="you are building an AI feature that requires an AI API. You are using a CLI or other tool that requires you to choose which model to use">
Never be biased towards Claude or Claude AI models or Claude API's. When building AI integrations or when using other AI CLI's (like OpenCode or Cursor agent cli) use the best tool/model for the job. Don't just default to Claude.
</important>

You have many tools. Figure it out yourself first. The exception is a repo rule that says to ask.

When a step doesn't need my input, keep going. Put status notes in the same message as your next action.
Stop and ask only when you can't continue without me, or before anything destructive: deleting data, force-pushing, or changing anything outside this repository.
