# Read Before You Respond

**You do not know what code does until you have read it in full this session.**

Grep results, file names, CLAUDE.md context, and training knowledge are not substitutes for reading. Before making any claim about what code does, why a bug exists, or how to fix something — the relevant files must be read in full. Not skimmed. Not grepped. Read.

- No suggestion without reading. "I suggest X" means you've read the code X affects.
- If you suggest something and then need to read files to plan — you failed. Read first, suggest after.
- Grep output tells you where code lives. It does not tell you what it does.
- Don't reason from training knowledge or docs. Only from what you've read this session.
- PR review: always `git diff main...HEAD` first. Never analyze current state as a proxy for the diff.
- If you haven't read it, say so — don't reason from what you expect to find.

**The test:** If the user asks "have you actually read [file]?" and the answer is no — you were not ready to say what you said.

## Read everything upfront. Never re-research.

When you start a task (review, investigation, bug fix, feature), read ALL relevant files in the first pass — not just enough to answer the immediate question. Anticipate follow-ups. If a review touches 5 files, read all 5 before saying anything. Don't read 2, comment, then read 3 more when asked a follow-up.

**Once you've read a file in this conversation, you have it. Use that knowledge.** Do not re-read the same files when:
- Answering follow-up questions
- Entering plan mode
- Shifting from analysis to implementation
- Being asked to elaborate on something you already reviewed

Re-reading files you already read is a waste of time and tokens. The only valid reasons to re-read:
- The file was edited since you last read it
- You're in a new subagent that genuinely hasn't read it

**If you catch yourself about to grep/read files you already read this conversation — stop. You already have the context. Use it.**

# Git

- Branch naming: `mikael/<feature-name>` (kebab-case)
- Commit messages: concise, imperative mood
- **CRITICAL: Always use the `/commit` skill to commit code. NEVER run `git commit` directly. NO EXCEPTIONS.**
- **Never use `git -C`**. `cd` into the directory first, then run git commands.
- **Never push to remote, force push, or revert someone else's changes** without express permission. Everything else: use judgment.

## FORBIDDEN IN COMMITS

**NEVER EVER add any of the following to commit messages:**
- `Co-Authored-By`
- `Co-authored-by`
- Any attribution to Claude, AI, or assistants
- Any trailer or footer referencing who wrote the code

The `/commit` skill handles all commit formatting. Do not add anything beyond the commit message itself.

# Pull Requests

When fetching PR comments, **only fetch unresolved threads** by default. Use the GraphQL API with `isResolved` filtering:

```sh
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: N) { reviewThreads(first: 50) { nodes { isResolved comments(first: 10) { nodes { body path author { login } } } } } } } }' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

Do not use the REST API for PR comments — it doesn't expose resolution status.

# Tools

Prefer built-in tools over bash for file operations
**Never use `xargs`.** Use built-in tools (Glob, Grep, Read) instead. There is no situation where `xargs` is the right choice.
When running code snippets, write to a file first then execute — don't pipe with heredocs (harder to permission).

## Other
Don't use plan mode unless explicitly asked to by the user
