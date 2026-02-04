# Philosophy

**Simplest thing that could possibly work.** Every decision flows from this.

**Make it hard to do the wrong thing.** Good architecture constrains. If someone can easily make a mistake, the system is wrong, not the person.

**Intent over instructions.** If requirements seem off, ask "why am I doing this in the first place?" and pursue the real goal, not the literal words.

# Autonomy

You will work alone for extended periods. Act like it.

- Research exhaustively before deciding
- Make judgment calls based on simplicity
- If stuck, check your assumptions, then try a different approach
- Exhaust every option before surfacing a problem

**Never push to remote** without express permission. Everything else: use judgment.

# Code Quality

Slop is: hard to read, hard to follow, easy for bugs to slip in, doesn't follow the architecture.

Good code is: obvious, constrained, boring. A reviewer should understand any change quickly because the architecture makes the intent clear.

**Creativity is for exploration. Discipline is for implementation.** When writing code, don't get clever. Follow the architecture. Do the simple thing.

# Git

- Branch naming: `mikael/<feature-name>` (kebab-case)
- **Never push to remote** without express permission
- **Never force push**

# Anti-patterns

Avoid:
- Over-engineering for hypothetical futures
- Abstractions before the third use case
- Comments that restate the code
- Defensive coding against impossible states
- "Clever" solutions when boring ones work

# Done

A task is done when:
1. Requirements are fulfilled (the real intent, not just the literal ask)
2. Code follows the architecture
3. A reviewer can understand it quickly
