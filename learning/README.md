# AI Leverage Mastery

**Goal:** Scale to 10 autonomous agents with minimal intervention.

**Philosophy:** Complexity kills. Always ask: "What's the simplest thing that could possibly work?"

## Daily 30-Minute Routine

### Minutes 0-5: Prompt Kata

```bash
cd challenges/electron-app && bun install  # first time only
```

Run the kata:
```
/kata
```

This will:
1. Give you a random Electron challenge
2. You write ONE prompt
3. A sub-agent attempts it with your exact prompt
4. You get graded on clarity, simplicity, autonomy, correctness
5. Results logged to `challenges/log.md`

### Minutes 5-25: Build the System

Rotate through these workstreams:

| Day | Focus | Work In |
|-----|-------|---------|
| Mon | Constrained Architecture | `electron-system/` |
| Tue | Parallel Exploration | `electron-system/` |
| Wed | AI as Parallel Self | `.claude/` configs |
| Thu | Verification Layer | `electron-system/` |
| Fri | Free exploration | Wherever needed |

**Constrained Architecture:** Build Electron patterns where the wrong thing is hard to do.

**Parallel Exploration:** Build tooling to try multiple approaches and compare.

**AI as Parallel Self:** Encode your philosophy so AI thinks like you.

**Verification Layer:** Tests and checks so you can trust without reviewing every line.

### Minutes 25-30: Reflect

Run the reflect skill:
```
/reflect
```

This will:
1. Ask what you worked on
2. Identify patterns and friction
3. Log to `journal.md`
4. Show your progress over time

## Structure

```
learning/
├── README.md               # You are here
├── journal.md              # Daily reflections
├── challenges/
│   ├── electron-app/       # Minimal app for prompt kata
│   └── log.md              # Graded prompt history
├── electron-system/        # The scalable system you're building
├── prompts/
│   └── tested/             # Battle-tested prompts
└── .claude/
    └── skills/
        ├── kata/           # /kata command
        └── reflect/        # /reflect command
```

## Progress Tracking

### Prompt Skill (from challenge log)
- [ ] Complete 10 katas
- [ ] Average score above 30/40
- [ ] Get an A grade

### System Building
- [ ] Electron architecture has typed IPC contracts
- [ ] Verification layer catches errors automatically
- [ ] Can run 2 agents in parallel on same codebase
- [ ] AI follows your philosophy without reminding

### Ultimate Goal
- [ ] Run 10 agents all day with minimal intervention

## Quick Reference

| Command | When |
|---------|------|
| `/kata` | Start of session (5 min) |
| `/reflect` | End of session (5 min) |

## First Time Setup

```bash
# Install challenge app dependencies
cd challenges/electron-app && bun install

# Install system app dependencies
cd ../electron-system && bun install

# Initialize git for challenge tracking
cd ../challenges/electron-app && git init && git add . && git commit -m "baseline"
```
