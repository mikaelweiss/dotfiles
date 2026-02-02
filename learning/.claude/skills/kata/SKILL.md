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
cd /Users/mikaelweiss/code/dotfiles/learning/challenges/electron-app && git checkout -- . && git clean -fd
```

### Step 2: Pick a challenge

Select ONE challenge the user hasn't done recently (check challenges/log.md).

**Beginner:**

1. **Time Check**
   > The user can discover the current time from within the app
   - ✓ Current time is visible or accessible
   - ✓ Time is accurate (within 1 minute)

2. **Version Info**
   > The user can verify which Electron version the app is running
   - ✓ Electron version is discoverable in the UI
   - ✓ Version number is accurate

3. **Quick Exit**
   > The user can close the application using the UI
   - ✓ A UI element exists that closes the app
   - ✓ Clicking/activating it terminates the process

4. **Click Counter**
   > The user can track how many times they've performed an action
   - ✓ A count is displayed
   - ✓ Count increments on user interaction
   - ✓ Count starts at 0

5. **Window Identity**
   > The user can see today's date in the window chrome
   - ✓ Date appears in the window title
   - ✓ Date is accurate

**Intermediate:**

6. **Menu Navigation**
   > The user can exit the app using the system menu bar
   - ✓ Menu bar exists with appropriate structure
   - ✓ An exit option exists and works

7. **Remembered Layout**
   > The app remembers where the user left it
   - ✓ Window position persists across restarts
   - ✓ Window size persists across restarts

8. **Theme Preference**
   > The user can switch between light and dark appearance
   - ✓ Toggle mechanism exists
   - ✓ Visual change is apparent
   - ✓ Preference persists across restarts

9. **Multi-Window**
   > The user can spawn additional windows
   - ✓ Action to create new window exists
   - ✓ New window actually appears
   - ✓ Multiple windows can coexist

10. **Keyboard Power User**
    > The user can quit the app without touching the mouse
    - ✓ Keyboard shortcut exists
    - ✓ Shortcut uses platform conventions (Cmd on Mac, Ctrl on Windows)
    - ✓ App terminates when triggered

**Advanced:**

11. **Background Presence**
    > The app can live in the system tray
    - ✓ Tray icon appears
    - ✓ Right-click shows context menu
    - ✓ At least one menu action works

12. **Clipboard Memory**
    > The user can review their recent clipboard history
    - ✓ Shows last 5 copied items
    - ✓ Updates when new items are copied
    - ✓ Items are clickable/selectable

13. **Update Awareness**
    > The app checks for updates on launch
    - ✓ Update check occurs automatically
    - ✓ User is informed of result (even if mocked)
    - ✓ Works without crashing on network failure

14. **Live Data Stream**
    > The renderer receives continuous updates from the main process
    - ✓ IPC channel established
    - ✓ Data flows from main to renderer
    - ✓ Updates are visible in real-time

15. **File Export**
    > The user can save content to their filesystem
    - ✓ Native save dialog appears
    - ✓ User can choose location
    - ✓ File is actually written

### Step 3: Present the challenge

Tell the user:

```
## Challenge: [Name]

[The outcome statement - what the user should be able to do]

**Acceptance Criteria:**
[List the criteria as checkboxes]

Write your prompt below. This exact text will be given to a fresh Claude agent.
Remember: ONE prompt. Make it count.
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
3. Run `bun start` to test the acceptance criteria

**Grading:**
- Check each acceptance criterion
- Mark as ✓ (pass) or ✗ (fail)
- **PASS**: All criteria met
- **FAIL**: Any criterion not met

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
- [Brief observation about what worked or didn't]

---
```

### Step 8: Reset and wrap up

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
