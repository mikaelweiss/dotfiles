# Behavioral Rules — HIGHEST PRIORITY

## Skills are instructions, not suggestions

**Skills are specific instructions. Follow them EXACTLY as written — every step, in order.**
- If a skill step says "launch an agent" or "launch a **haiku** agent" — you MUST use the Agent tool. Do NOT do that step yourself. Do NOT skip it. Do NOT do part of it yourself and delegate the rest.
- If a skill step specifies a model (haiku, sonnet, opus) — use that model.
- A skill is not a suggestion. It is a procedure. Execute it mechanically.

## Sub-agents

**NEVER use the Agent tool unless:**
1. The user explicitly asks for sub-agents (e.g., "use an agent", "spawn an agent", "run agents in parallel"), OR
2. A skill you are executing says to use sub-agents

That's it. No other reason. Every other task — web search, code search, file reading, exploration — do it yourself directly.

## Plan mode

ONLY enter plan mode when I explicitly ask for it (e.g., "make a plan", "use plan mode"). If you are about to enter plan mode and I did not ask for one, STOP and skip it.

---

# Read Before You Respond

**You do not know what code does until you have read it in full this session.**

Grep results, file names, CLAUDE.md context, and training knowledge are not substitutes for reading. Before making any claim about what code does, why a bug exists, or how to fix something — the relevant files must be read in full. Not skimmed. Not grepped. Read.

- No suggestion without reading. "I suggest X" means you've read the code X affects.
- If you suggest something and then need to read files to plan — you failed. Read first, suggest after.
- Grep output tells you where code lives. It does not tell you what it does.
- Don't reason from training knowledge or docs. Only from what you've read this session.
- PR review: always `git diff main...HEAD` first. Never analyze current state as a proxy for the diff.
- Code review (uncommitted or PR): run the diff first to see what changed, then read the full content of every modified file. The diff shows what changed — the full file shows the context. Both are required. New files in a diff are complete; modified files are not.
- If you haven't read it, say so — don't reason from what you expect to find.

**The test:** If the user asks "have you actually read [file]?" and the answer is no — you were not ready to say what you said.

## Never re-read files

Once you've read a file in this conversation, you have it. Do not re-read the same files when answering follow-ups, entering plan mode, shifting to implementation, or elaborating. The only valid reasons to re-read:
- The file was edited since you last read it
- You're in a new subagent that genuinely hasn't read it

---

# Git

- Branch naming: `mikael/<feature-name>` (kebab-case)
- Commit messages: concise, imperative mood
- **CRITICAL: Always use the `/commit` skill to commit code. NEVER run `git commit` directly. NO EXCEPTIONS.**
- **Never use `git -C`**. `cd` into the directory first, then run git commands.
- **Never push to remote, force push, or revert someone else's changes** without express permission.

## FORBIDDEN IN COMMITS

**NEVER EVER add any of the following to commit messages:**
- `Co-Authored-By` / `Co-authored-by`
- Any attribution to Claude, AI, or assistants
- Any trailer or footer referencing who wrote the code

The `/commit` skill handles all commit formatting.

# Pull Requests

When fetching PR comments, **only fetch unresolved threads** by default. Use the GraphQL API with `isResolved` filtering:

```sh
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: N) { reviewThreads(first: 50) { nodes { isResolved comments(first: 10) { nodes { body path author { login } } } } } } } }' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

Do not use the REST API for PR comments — it doesn't expose resolution status.

# Branch Ownership

YOU are responsible for this branch. NEVER say things like "this is pre-existing, not my issue." If it is on this branch, it IS your issue. You are responsible for the quality of all committed and uncommitted code.

# Code Search Tools

Use ast-grep (`mcp__ast-grep__*`) and tree-sitter (`mcp__tree-sitter__*`) MCP tools as the PRIMARY code search tools. Only fall back to Grep/Glob when ast-grep or tree-sitter cannot do the job (e.g., plain text search, non-code files, simple string matching).

**ast-grep** — Use for: finding code patterns, import analysis, lint scanning, structural find/replace.

**tree-sitter** — Use for: symbol extraction (`get_symbols`), usage tracing (`find_usage`), AST inspection (`get_ast`), complexity analysis, project-wide analysis.

**Grep/Glob** — Use only for: plain string search, non-code files, finding files by name pattern.
