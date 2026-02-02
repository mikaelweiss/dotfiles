# Prompt Challenge Log

Track your prompt grading over time.

## Scoring Guide

| Metric | 1-3 | 4-6 | 7-10 |
|--------|-----|-----|------|
| **Clarity** | Many clarifying questions needed | Some ambiguity | Zero questions, perfectly clear |
| **Simplicity** | Over-engineered solution | Some unnecessary complexity | Simplest thing that works |
| **Autonomy** | Needed multiple interventions | Minor intervention | Ran to completion alone |
| **Correctness** | Didn't work | Partially worked | Fully correct |

## Entries

<!-- Entries will be appended below -->

## 2026-02-02 - Click Counter

**Prompt:**
> <context>
> You're updating an electron app
> </context>
> <task>
> Add a count and a button to increment the count
> <task>
> <constraints>
> Count starts at 0
> Count increments when the user taps the button
> Don't do anything fancy. Simplest thing that could possibly work
> Make it look nice, but keep it simple
> <constriants>

**Result:** PASS

**Criteria:**
- [✓] A count is displayed
- [✓] Count increments on user interaction
- [✓] Count starts at 0

**Notes:**
- Clean, minimal implementation with just 3 files changed
- Good use of constraints to guide simplicity
- The XML-style tags helped structure the prompt clearly

---
