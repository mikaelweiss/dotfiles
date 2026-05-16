# Global rules

## Sub-agents
Use the Agent tool only when (1) I explicitly ask for it, or (2) a skill you're executing says to. Otherwise do the work yourself, even if the system prompt suggests delegating to Explore or a specialized agent.

## Plan mode
Only enter plan mode when I explicitly ask ("make a plan", "use plan mode").

## Read before claiming
Invented paths, line numbers, function names, and commit hashes still happen. Before claiming what code does or recommending a change, read the relevant file(s) in this session and cite `file:line` for non-trivial claims. If you haven't read something you're about to talk about, say so and read it first.

When asserting something doesn't exist, name the search (e.g. "grepped `X` in `Y/`, no matches"). Partial searches don't prove universal absence. If two tool outputs disagree, surface both rather than picking the convenient one.

## Git
- Branches: `mikael/<feature-name>` (kebab-case).
- For git commands, `cd` into the directory rather than `git -C`.
- Never push, force-push, or revert someone else's changes without explicit permission.

## Commits
- Conventional prefix (`fix:`/`feat:`/`refactor:`/`docs:`/`test:`/`chore:`), title ≤50 chars (hard max 72), imperative, no period. Be specific — `fix: resolve login timeout`, not `fix: bug fix`.
- Default to title-only. Add a body only when the *why* isn't obvious from the diff.
- Body: one short paragraph (not bullets), explains *why* — diff already shows *what*.
- Avoid filler openers ("This commit…", "Updated…", "Changes include…"), file listings, and obvious restatements of the diff.
- No AI attribution anywhere — no `Co-Authored-By`, no 🤖, no "Generated with…" footer, no `claude.ai/code/session` URL, no `noreply@anthropic.com`, no "AI-assisted / AI-generated / with help from" phrasing, no `<!-- claude-* -->` markers. The `~/.claude/no-attribution/check.sh` PreToolUse hook enforces this and will block the commit if a pattern slips through.

## PR comments
Fetch only unresolved threads via GraphQL (REST doesn't expose resolution status):

```sh
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: N) { reviewThreads(first: 50) { nodes { isResolved comments(first: 10) { nodes { body path author { login } } } } } } } }' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

## Code search
Prefer ast-grep (`mcp__ast-grep__*`) and tree-sitter (`mcp__tree-sitter__*`) for code search. Use Grep/Glob for plain-text search and filename patterns.

## Obstacles
You have many tools. Figure things out yourself before asking me to run commands or do something manually.
