#!/usr/bin/env python3
"""PreToolUse gate on ExitPlanMode: one enforced self-review per session.

A plan that only says what to build is half a plan. This hook bounces the
FIRST ExitPlanMode call of a session (exit 2 feeds the checklist back to the
model), forcing a review of definition-of-done gates and failure-mode
invariants before the plan reaches the user. The second call passes.

A plan that already carries the goods sails through without the bounce: if
the plan text contains both an invariants section and a verification or
acceptance-criteria section (the /plan skill's template produces both), the
gate passes on the first call.

Fails open on any error.
"""

import json
import os
import re
import sys
import tempfile

CHECKLIST = """PLAN GATE (fires once per session): before resubmitting, verify the plan and revise it where it falls short. Do not ask the user about this gate; just improve the plan and call ExitPlanMode again (it will pass).

1. Definition of done: does the plan name every gate the repo's docs impose on the surfaces it touches (lint, required test surfaces, contract chains, walkthrough/QA docs, feature-flag lockstep, manual checklists)? Each belongs in the plan as an acceptance criterion. Deliberately skipping one must appear as an explicit out-of-scope decision, never silence.

2. Failure modes: for every piece of persisted state, shared resource, or concurrent actor the design touches: what happens when the data is older, newer, corrupt, or written by two actors at once? When permissions or context shift underneath it? State the chosen invariant for each as one sentence in the plan.

3. Lean: the plan should carry decisions and invariants, not prose. Each invariant should be implementable in a few lines and pinned by a test."""


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    if payload.get("tool_name") != "ExitPlanMode":
        sys.exit(0)

    session = payload.get("session_id", "nosession")
    state_path = os.path.join(tempfile.gettempdir(), f"claude-plan-gate-{session}")

    if os.path.exists(state_path):
        sys.exit(0)

    try:
        with open(state_path, "w", encoding="utf-8") as fh:
            fh.write("bounced\n")
    except OSError:
        sys.exit(0)

    plan = (payload.get("tool_input") or {}).get("plan", "")
    has_invariants = re.search(r"invariant", plan, re.IGNORECASE)
    has_verification = re.search(
        r"verification|acceptance criteria", plan, re.IGNORECASE
    )
    if has_invariants and has_verification:
        sys.exit(0)

    print(CHECKLIST, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
