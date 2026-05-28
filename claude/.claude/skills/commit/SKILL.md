---
name: commit
description: Commit Staged Changes. Create a commit for currently staged changes with an auto-generated message. Use when the user says "commit", "make a commit", "commit my changes", or invokes /commit.
user-invocable: true
---

# Commit Staged Changes

Create a commit for the currently staged changes with an auto-generated message.

## Process

1. First, check git status to see what's staged:
   - Run `git status` to see staged changes
   - Run `git diff --cached` to see the actual staged diff
   - If nothing is staged, inform the user and stop

2. Analyze the staged changes to understand:
   - What files were modified, added, or deleted
   - The nature of the changes (bug fix, feature, refactor, docs, etc.)

3. Generate a commit message:
   - **Title only** for simple, self-explanatory changes
   - **Title + body** only when the "why" isn't obvious from the diff

4. Create the commit. For title-only:
   ```bash
   git commit -m "fix: resolve null pointer in auth handler"
   ```

   For title + body (use HEREDOC):
   ```bash
   git commit -m "$(cat <<'EOF'
   feat: add rate limiting to API endpoints

   Prevents abuse by limiting requests to 100/min per user.
   EOF
   )"
   ```

5. After committing, run `git status` to confirm success.

## Message Guidelines

### Title Rules
- Use conventional commit prefix: `fix:`, `feat:`, `refactor:`, `docs:`, `test:`, `chore:`
- Keep under 50 characters (hard max: 72)
- Imperative mood ("add" not "added")
- No period at end
- Be specific: "fix: resolve login timeout" not "fix: bug fix"

### Body Rules (only when needed)
- Explain **why**, not what (the diff shows what)
- One short paragraph max
- Skip if the title says it all

## Anti-Patterns

- Filler words: "This commit...", "Changes include...", "Updated..."
- Listing every file changed
- Obvious statements
- **NEVER add Co-Authored-By, Signed-off-by, or any other footers/signatures**

## Examples

**Good (title only):**
- `fix: handle empty user input in search`
- `feat: add dark mode toggle`
- `refactor: extract validation logic to helper`

**Good (with body):**
```
feat: add request caching layer

Reduces API load by 40% for repeated queries.
```

**Too verbose (avoid):**
```
fix: Fix bug in the authentication module

This commit fixes a bug that was occurring in the authentication
module where users were being logged out unexpectedly. The issue
was caused by a null pointer exception in the session handler.
Changes were made to auth.ts and session.ts files.
```

**Same change, concise:**
```
fix: prevent unexpected logout from null session
```
