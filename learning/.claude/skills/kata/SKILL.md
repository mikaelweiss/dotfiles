---
name: kata
description: Daily prompt kata for practicing AI leverage. Generates a random Electron task, user provides ONE prompt, a sub-agent attempts it, then the result is graded. Use when starting daily practice session.
user-invocable: true
---

# Prompt Kata

Practice writing effective prompts by attempting Electron tasks with a single prompt.

## Core Principles

- **One prompt only** — User gets one shot, no revisions
- **No intervention** — Sub-agent runs to completion or failure
- **Outcome-based** — Challenges describe WHAT, you figure out HOW
- **Pass/Fail** — Either the acceptance criteria are met, or they aren't

## Flow

### Step 1: Reset the challenge app

Reset to baseline:
```bash
cd /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app && git checkout -- . && git clean -fd .
```

### Step 2: Generate a challenge

Read the user's goal from `/Users/mikaelweiss/code/dotfiles/learning/README.md` and their history from `challenges/log.md`.

**Generation Rules:**

1. The challenge must test a skill relevant to the user's goal (scaling autonomous agents)
2. Focus on skills that enable agent autonomy:
   - Clear outcome specification
   - Architectural constraint definition
   - Failure behavior specification
   - Verification criteria clarity
3. Scale difficulty based on log.md history:
   - **First 5 katas:** Simple features, test clear communication
   - **After 3 PASSes:** Add coordination/persistence requirements
   - **After 6 PASSes:** Add ambiguity that requires architectural guidance
   - **After 9 PASSes:** Multi-concern challenges requiring comprehensive prompts
4. Never repeat a challenge from the last 3 entries in log.md
5. The challenge must be completable in a minimal Electron app

**Challenge Structure:**
- **Name**: Short, memorable title
- **Outcome**: What the user should be able to do (not implementation details)
- **Acceptance Criteria**: 2-4 observable, testable criteria
- **Difficulty Indicator**: What prompt skill this tests

**For harder challenges (after 6+ PASSes), also generate:**
- **Why it's hard**: What decisions the agent will make arbitrarily without guidance
- **What your prompt must specify**: The constraints needed for success

### Step 3: Present the challenge

Tell the user:

```
## Challenge: [Name]

[The outcome statement - what the user should be able to do]

**Acceptance Criteria:**
[List the criteria as checkboxes]

**This tests:** [What prompt skill this challenge exercises]

Write your prompt below. This exact text will be given to a fresh Claude agent.
Remember: ONE prompt. Make it count.
```

**For harder challenges (after 6+ PASSes)**, also show:
```
⚠️ This challenge has ambiguity

**Why it's hard:** [What the agent will decide arbitrarily]

**Your prompt should specify:** [What constraints are needed]
```

### Step 4: Receive the prompt

Wait for user to provide their prompt. Do not offer suggestions or improvements.

### Step 5: Run the sub-agent

Use the Task tool to spawn an agent:
- **subagent_type**: `general-purpose`
- **prompt**: The user's EXACT prompt, prefixed with the working directory
- **Working context**: `/Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app`

Format the prompt to the sub-agent as:
```
Working directory: /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app

[USER'S EXACT PROMPT HERE - do not modify]
```

Let it run to completion.

### Step 6: Review and Grade

After the sub-agent finishes:
1. Run `git diff` in the challenge app to see changes
2. Run `git status` to see new files
3. Run lint and tests (`bun run lint && bun run test` or equivalent)
4. Review the code to verify acceptance criteria are met

**Grading:**
- Check each acceptance criterion by reading the code
- Mark as ✓ (pass) or ✗ (fail)
- **PASS**: All criteria met, lint passes, tests pass
- **FAIL**: Any criterion not met, or lint/test failures

### Step 7: Log the result

Append to `/Users/mikaelweiss/code/dotfiles/learning/challenges/log.md`:

```markdown
## [DATE] - [Challenge Name]

**Prompt:**
> [Their exact prompt]

**Result:** PASS / FAIL

**Criteria:**
- [✓/✗] Criterion 1
- [✓/✗] Criterion 2
- [✓/✗] Criterion 3

**Notes:**
- [What prompt skill was demonstrated or missing]
- [What the agent did well or struggled with]

---
```

### Step 8: Reset and wrap up

Reset the app for next time:
```bash
cd /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app && git checkout -- . && git clean -fd .
```

Give brief feedback and encourage the user to continue with their build session.

## Anti-Patterns

- Do NOT suggest improvements to the prompt before running it
- Do NOT modify the user's prompt in any way
- Do NOT intervene while the sub-agent is working
- Do NOT give hints about what the prompt should include
- Do NOT run the same challenge twice in a row
