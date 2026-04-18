# Behavioral Rules — HIGHEST PRIORITY

## Skills are instructions, not suggestions

**Skills are specific instructions. Follow them EXACTLY as written — every step, in order.**
- When a skill step says "launch an agent" or "launch a **haiku** agent," use the Agent tool with that exact model. Delegate the whole step; do not split it or perform any portion yourself.
- When a skill step specifies a model (haiku, sonnet, opus), use that model.
- Execute skills mechanically, step by step.

## Sub-agents

**Use the Agent tool ONLY in these two cases:**
1. The user explicitly asks for sub-agents (e.g., "use an agent", "spawn an agent", "run agents in parallel").
2. A skill you are executing says to use sub-agents.

For every other task — web search, code search, file reading, exploration — work directly yourself.

## Plan mode

Enter plan mode ONLY when I explicitly ask for it (e.g., "make a plan", "use plan mode"). Otherwise, proceed directly.

## Instruction scope is literal

Treat instruction scope literally. If I say "fix the bug in function X," fix X — leave Y alone even if it looks similar. When scope is ambiguous, ask before proceeding.

---

# Read Before You Respond

<investigate_before_answering>
Never speculate about code you have not opened. If the user references a specific file, you MUST read the file before answering. Make sure to investigate and read relevant files BEFORE answering questions about the codebase. Never make any claims about code before investigating unless you are certain of the correct answer — give grounded and hallucination-free answers.
</investigate_before_answering>

**Read code in full this session before claiming to know what it does.**

Grep results, file names, CLAUDE.md context, and training knowledge are starting points, not substitutes for reading. Before making any claim about what code does, why a bug exists, or how to fix something, read the relevant files in full.

- Read before suggesting. "I suggest X" means you've read the code X affects.
- If you find yourself needing to read files after suggesting, you suggested too early. Read first, suggest after.
- Treat grep output as "where code lives," and read the file to learn what it does.
- Reason only from files read this session, not from training knowledge or docs.
- PR review: run `git diff main...HEAD` first, then read each changed file in full. The diff shows what changed; the full file shows context. Both required. New files in a diff are complete; modified files are not.
- Say "I haven't read [file]" when that's true, and read it before continuing. Reason from what you've read, not from what you expect to find.

**The test:** If I ask "have you actually read [file]?" and the answer is no — you were not ready to say what you said.

## Trust your session memory

Once you've read a file this conversation, you have it. Reuse that knowledge across follow-ups, plan mode, implementation, and elaboration. Re-read only when:
- The file was edited since you last read it, or
- You're in a new subagent that hasn't read it yet.

## Ground claims in quotes

When claiming what code does or what a file contains, cite the exact lines (file:line-range). A citation is evidence of reading. Claims without citations indicate pattern-matching from training, not grounded knowledge.

---

# Git

- Branch naming: `mikael/<feature-name>` (kebab-case)
- Commit messages: concise, imperative mood
- **CRITICAL: Always use the `/commit` skill to commit code. NEVER run `git commit` directly. NO EXCEPTIONS.**
- For git commands, `cd` into the directory first rather than using `git -C`.
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

Use the GraphQL API for PR comments; the REST API doesn't expose resolution status.

# Branch Ownership

You are responsible for this branch. Treat everything on it — committed or uncommitted, new or pre-existing — as your concern. If it is on this branch, it is yours to fix or escalate.

# Avoid Over-Engineering

Make only changes that are directly requested or clearly necessary. Keep solutions simple and focused:

- **Scope:** Limit changes to what was asked. Leave surrounding code alone on bug fixes. Keep simple features simple — no extra configurability.
- **Documentation:** Add comments, docstrings, or type annotations only to code you're changing, and only where logic isn't self-evident.
- **Defensive coding:** Validate at system boundaries (user input, external APIs); trust internal code within them.
- **Abstractions:** Create helpers and abstractions only when current code needs them. The right complexity is the minimum needed for the current task.

# Before declaring done

Verify completion against the original requirements:
- Restate the request in your own words.
- Map each requirement to evidence it's met (file:line, test output, command output).
- If evidence is missing, name what's still missing rather than claiming complete.
- Replace "should work" with "verified" (with evidence) or "not verified" (with plan to verify).

# Code Search Tools

Use ast-grep (`mcp__ast-grep__*`) and tree-sitter (`mcp__tree-sitter__*`) MCP tools as the PRIMARY code search tools. Fall back to Grep/Glob only when ast-grep or tree-sitter cannot do the job (e.g., plain text search, non-code files, finding files by name pattern).

**ast-grep** — Use for: finding code patterns, import analysis, lint scanning, structural find/replace.

**tree-sitter** — Use for: symbol extraction (`get_symbols`), usage tracing (`find_usage`), AST inspection (`get_ast`), complexity analysis, project-wide analysis.

**Grep/Glob** — Use for: plain string search, non-code files, finding files by name pattern.
