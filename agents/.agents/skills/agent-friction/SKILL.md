---
name: agent-friction
description: >-
  Find friction in agent sessions and instruction surfaces — turn waste, skill/rule bloat,
  always-on tax, exposure-aware skill usage, config epochs (did an intervention
  help?). Measure first; change behavior or the codebase only on repeated evidence.
  Use after painful sessions, weekly review, before adding/removing skills or
  alwaysApply rules, or when judging whether a recent agent intervention worked.
---

# Agent Friction

Install: `npm install agent-friction` then `npx agent-friction init`.

`init` installs the skill under `.agents/skills/agent-friction` (symlinked into
`.cursor` / `.claude` / `.codex`), and merges hook commands into
`.cursor/hooks.json`, `.claude/settings.json`, and `.codex/hooks.json`.

The **npm package** measures. This **skill** tells you how to act on the numbers.

**Philosophy:** measure → diagnose patterns → change skills/rules/code **only**
when evidence keeps pointing at the same friction.

## Commands (consumer repo root)

| Need | Command |
| ---- | ------- |
| Last turn | `npx agent-friction latest` |
| Live dashboard | `npx agent-friction watch` · `--browser` |
| Instruction tax + epochs | `npx agent-friction surface --days=30` |
| Baseline trend | `npx agent-friction compare --days=30` |
| Cross-session rediscovery | `npx agent-friction rediscovery --min-sessions=5` |
| One session | `npx agent-friction task <uuid>` |

Add `--json` for machine-readable output. **Do not** read `latest.txt` every turn — hooks never inject; use after substantial work or weekly review.

## When you MUST run it

1. After a **substantial / painful** task
2. **Before** proposing a new skill or alwaysApply rule — run `surface`
3. **Before** archiving a skill — check **SKILL USAGE** maturity (not dead if too new)
4. **After** landing an agent intervention — re-check via **CONFIG EPOCHS** later
5. Weekly: `aggregate --days=7`, `compare --days=30`, `surface --days=30`

## Reading `surface` (critical)

### Skill usage — exposure-aware

Usage only counts sessions **after** the skill existed.

| Eligible sessions | Verdict |
| ----------------- | ------- |
| `< 10` | Too new — no archive/delete |
| `10–29` | Early signal — watch only |
| `≥ 30` | Established — hard verdicts OK |

### Config epochs — did it help?

Before/after medians at introduce-or-change boundary. Needs ≥5 before + ≥10 after sessions. Mixed signal = inconclusive.

## Playbooks

**Add skill/rule:** run `surface` → confirm repeated pain → prefer scoped/on-demand → judge later via epochs.

**Dead skill?** Only if **Established** and 0/N eligible — never from pre-existence history.

**Painful session:** `latest` → fix behavior recs → agent-friction-findings if rediscovery repeats.

## Persistent knowledge

Record stable shortcuts in the consumer repo's `docs/agents/agent-friction-findings.md`.

## Out of scope

Auto-editing docs from recommendations; declaring success without eligible-session maturity.
