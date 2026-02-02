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
- **Measure everything** — Grade on clarity, simplicity, autonomy, correctness
- **Simplicity wins** — "What's the simplest thing that could possibly work?"

## Flow

### Step 1: Reset the challenge app

Reset to baseline:
```bash
cd /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app && git checkout -- . && git clean -fd
```

### Step 2: Pick a challenge

Select ONE challenge the user hasn't done recently (check challenges/log.md).

**Beginner:**
- Add a button that shows the current time in an alert
- Change the window title to include the current date
- Add a "Quit" button that closes the app
- Display the Electron version number prominently in the UI
- Add a counter that increments when clicking a button

**Intermediate:**
- Add a menu bar with File > Exit option
- Persist window size and position between launches
- Add a dark/light mode toggle that persists across restarts
- Create a second window that opens from a button click
- Add keyboard shortcut (Cmd/Ctrl+Q) to quit the app

**Advanced:**
- Add a system tray icon with a context menu
- Implement a simple clipboard history showing last 5 copied items
- Add auto-update check on launch (mock the API response)
- Create an IPC channel that streams live data from main to renderer
- Add a native file dialog to save text content to disk

### Step 3: Present the challenge

Tell the user:

```
## Challenge: [Name]

[Clear description of what needs to be built]

Write your prompt below. This exact text will be given to a fresh Claude agent.
Remember: ONE prompt. Make it count.
```

### Step 4: Receive the prompt

Wait for user to provide their prompt. Do not offer suggestions or improvements.

### Step 5: Run the sub-agent

Use the Task tool to spawn an agent:
- **subagent_type**: `james` (implementation agent)
- **prompt**: The user's EXACT prompt, prefixed with the working directory
- **Working context**: `/Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app`

Format the prompt to the sub-agent as:
```
Working directory: /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app

[USER'S EXACT PROMPT HERE - do not modify]
```

Let it run to completion.

### Step 6: Review the result

After the sub-agent finishes:
1. Run `git diff` in the challenge app to see changes
2. Run `git status` to see new files
3. Optionally run `bun start` to test if it works

### Step 7: Grade the prompt

Score 1-10 on each criterion:

**Clarity**: Was the prompt unambiguous? Could it be misinterpreted?
- 1-3: Multiple interpretations possible, AI had to guess
- 4-6: Some ambiguity, but intent was mostly clear
- 7-10: Crystal clear, only one reasonable interpretation

**Simplicity**: Did the prompt encourage the simplest solution?
- 1-3: Led to over-engineered solution
- 4-6: Some unnecessary complexity
- 7-10: Resulted in the simplest thing that works

**Autonomy**: Did the agent complete without getting stuck?
- 1-3: Got stuck, made wrong assumptions, needed intervention
- 4-6: Minor issues but mostly completed
- 7-10: Ran to completion smoothly

**Correctness**: Does the code actually work?
- 1-3: Doesn't work or wrong behavior
- 4-6: Partially works
- 7-10: Fully correct

**Total**: X/40
- 36-40: A
- 32-35: B
- 28-31: C
- 24-27: D
- Below 24: F

### Step 8: Log the result

Append to `/Users/mikaelweiss/code/dotfiles/learning/challenges/log.md`:

```markdown
## [DATE] - [Challenge Name]

**Prompt:**
> [Their exact prompt]

**Scores:**
| Clarity | Simplicity | Autonomy | Correctness | Total |
|---------|------------|----------|-------------|-------|
| X/10    | X/10       | X/10     | X/10        | X/40 (Grade) |

**What worked:**
- [Observation]

**What could improve:**
- [Specific suggestion for next time]

---
```

### Step 9: Reset and wrap up

Reset the app for next time:
```bash
cd /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app && git checkout -- . && git clean -fd
```

Give brief feedback and encourage the user to continue with their build session.

## Anti-Patterns

- Do NOT suggest improvements to the prompt before running it
- Do NOT modify the user's prompt in any way
- Do NOT intervene while the sub-agent is working
- Do NOT give hints about what the prompt should include
- Do NOT run the same challenge twice in a row
