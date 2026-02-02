---
name: reflect
description: End-of-session reflection for daily AI leverage practice. Guides through reviewing what worked, what didn't, and logs insights to journal. Use at the end of practice sessions.
user-invocable: true
---

# Session Reflection

Wrap up a practice session by identifying patterns and logging insights.

## Core Principles

- **Identify friction** — Where did AI need help?
- **Find patterns** — What's working, what isn't?
- **Keep it brief** — 5 minutes max
- **Track progress** — Show improvement over time

## Flow

### Step 1: Ask what happened

Ask the user:
1. "What did you work on during the build session?"
2. "Did you have to intervene at any point? What caused it?"

Keep it conversational. Don't overwhelm with questions.

### Step 2: Identify patterns

Based on their answers, reflect back:
- **Friction points**: Where did AI slow down or need help?
- **Wins**: What worked smoothly?
- **Architecture gaps**: Could better structure have prevented issues?

### Step 3: Quick reflection questions

Ask (user can answer briefly or skip):
1. "What's one thing that would have made today smoother?"
2. "Did complexity creep in anywhere?"
3. "What do you want to try tomorrow?"

### Step 4: Log to journal

Append to `/Users/mikaelweiss/code/dotfiles/learning/journal.md`:

```markdown
## [DATE]

### Focus
[What they worked on]

### Interventions
[Times they had to step in, or "None"]

### Friction
- [Issues encountered]

### Wins
- [What worked well]

### Tomorrow
- [What to try next]

---
```

### Step 5: Show progress

Read `/Users/mikaelweiss/code/dotfiles/learning/challenges/log.md` and summarize:
- Total challenges completed
- Average score (if enough data)
- Trend: improving, stable, or declining
- Strongest area (highest average)
- Area to focus on (lowest average)

If not enough data yet, just note how many challenges completed.

### Step 6: Close out

End with a brief encouragement to continue tomorrow. Keep it genuine, not sycophantic.

## Anti-Patterns

- Do NOT drag out the reflection beyond 5 minutes
- Do NOT ask too many questions at once
- Do NOT over-analyze — keep it practical
- Do NOT skip logging — the journal is how progress is tracked
