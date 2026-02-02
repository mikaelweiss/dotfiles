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

Select ONE challenge based on user's history in challenges/log.md.

**Selection Rules:**
1. Check log.md for completed challenges and pass/fail rate
2. **First 5 katas:** Stay in Beginner tier
3. **After 3 Beginner PASSes:** Introduce Intermediate
4. **After 3 Intermediate PASSes:** Introduce Advanced
5. **After 3 Advanced PASSes:** Introduce Expert
6. **On FAIL:** Stay at current tier until a PASS
7. Never repeat the same challenge twice in a row

**Expert tier warning:** Before presenting an Expert challenge, tell the user: "This is an Expert challenge. The agent WILL fail without architectural guidance in your prompt."

---

**BEGINNER** — Tests: Can you describe what you want clearly?

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

---

**INTERMEDIATE** — Tests: Can you specify persistence and coordination?

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

---

**ADVANCED** — Tests: Can you handle IPC and system integration?

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

---

**EXPERT** — Tests: Can you prevent wrong paths, handle ambiguity, and define verification?

These challenges have multiple valid approaches. Your prompt must constrain the solution space, anticipate failure modes, and define what "done" means. The agent WILL go wrong without guidance.

16. **Persistent Notes**
    > The user can write notes that survive app restarts
    - ✓ Text input exists
    - ✓ Content persists after quit and relaunch
    - ✓ No data loss on crash (force quit)

    *Why it's hard:* Multiple storage options (file, electron-store, SQLite). Where does the file go? What format? How does crash safety work? Your prompt must constrain these or the agent will pick arbitrarily.

17. **Synchronized State**
    > Multiple windows show the same counter, always in sync
    - ✓ Counter visible in at least 2 windows
    - ✓ Incrementing in one updates the other immediately
    - ✓ New windows start with current count, not zero

    *Why it's hard:* State ownership is ambiguous. Main process as source of truth? Renderer-to-renderer? IPC broadcast? Race conditions? Your prompt must establish the architecture.

18. **Graceful Degradation**
    > The app displays data from an API, but works offline too
    - ✓ Shows live data when network available
    - ✓ Shows cached data when offline
    - ✓ Clear indication of stale vs fresh data
    - ✓ No crashes or hangs on network failure

    *Why it's hard:* Error handling is invisible until it fails. Cache invalidation strategy? Timeout handling? UI feedback during loading? Your prompt must specify the failure behaviors, not just the happy path.

19. **Secure Configuration**
    > The app stores a user-provided API key safely
    - ✓ User can input and save a key
    - ✓ Key is not stored in plain text
    - ✓ Key is not logged or exposed in devtools
    - ✓ Key survives app restart

    *Why it's hard:* "Secure" is ambiguous. Encrypted file? OS keychain? What encryption? Your prompt must define the threat model and acceptable solutions, or the agent will either over-engineer or under-secure.

20. **Undo/Redo**
    > Any user action can be reversed and re-applied
    - ✓ At least 3 different actions are undoable
    - ✓ Undo reverses the most recent action
    - ✓ Redo re-applies an undone action
    - ✓ Keyboard shortcuts (Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z)

    *Why it's hard:* State management architecture choice. Command pattern? State snapshots? What counts as an "action"? Memory limits on history? Your prompt must define the scope and strategy.

21. **Plugin Architecture**
    > Third-party code can extend the app's functionality
    - ✓ A plugin can be loaded from a file/folder
    - ✓ Plugin can add UI elements
    - ✓ Plugin can access limited app APIs
    - ✓ Bad plugin cannot crash the main app

    *Why it's hard:* Security vs capability tradeoff. Sandboxing? IPC boundaries? Plugin manifest format? Your prompt must balance power with safety and specify the extension points.

22. **Cross-Window Drag**
    > The user can drag an item from one window to another
    - ✓ Item can be picked up in window A
    - ✓ Item can be dropped in window B
    - ✓ Data transfers correctly
    - ✓ Visual feedback during drag

    *Why it's hard:* Native drag-drop across Electron windows is non-trivial. Custom IPC? HTML5 drag API? Window detection? Your prompt must specify the interaction model.

23. **Startup Performance**
    > The app launches and is interactive in under 2 seconds
    - ✓ Window visible in < 1 second
    - ✓ UI interactive in < 2 seconds
    - ✓ No blocking operations on main thread
    - ✓ Deferred loading for non-critical features

    *Why it's hard:* "Fast" requires measurement and specific techniques. Lazy loading? Preload scripts? Splash screen? Your prompt must define what to defer and how to verify.

24. **Conflict Resolution**
    > Two windows editing the same data don't lose changes
    - ✓ Both windows can edit simultaneously
    - ✓ No silent data loss
    - ✓ User is informed of conflicts
    - ✓ User can choose which version to keep

    *Why it's hard:* Distributed systems problem. Last-write-wins? Merge? Lock? Your prompt must define the conflict strategy and UI for resolution.

25. **Migration Path**
    > Old data format is automatically upgraded on launch
    - ✓ App writes data in "v2" format
    - ✓ App can read "v1" format and migrate it
    - ✓ Migration is non-destructive (backup created)
    - ✓ User is informed of migration

    *Why it's hard:* Requires defining both formats, migration logic, and rollback strategy. Your prompt must specify the schema change and safety requirements.

### Step 3: Present the challenge

Tell the user:

```
## Challenge: [Name] ([Tier])

[The outcome statement - what the user should be able to do]

**Acceptance Criteria:**
[List the criteria as checkboxes]

Write your prompt below. This exact text will be given to a fresh Claude agent.
Remember: ONE prompt. Make it count.
```

**For Expert challenges only**, also show:
```
⚠️ Expert Challenge

This has multiple valid approaches. Your prompt must:
- Constrain the architecture (what approach to use)
- Define failure behavior (what happens when things go wrong)
- Specify verification (how do we know it works)

[Include the "Why it's hard" note from the challenge]
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
## [DATE] - [Challenge Name] ([TIER])

**Prompt:**
> [Their exact prompt]

**Result:** PASS / FAIL

**Criteria:**
- [✓/✗] Criterion 1
- [✓/✗] Criterion 2
- [✓/✗] Criterion 3

**Notes:**
- [Brief observation about what worked or didn't]

**For Expert challenges, also note:**
- What architectural decision was specified (or missing)
- What failure mode was anticipated (or missed)
- What verification approach was defined (or unclear)

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
