# [003] Verify stage: build, test, screenshot, report

## Objective
Before opening a feature's PR, otto.py builds and tests the change, captures a screenshot of the app running, uploads it, and posts a verification report — so the human review window is spent verifying, not discovering breakage.

## Context
- **The goal is to convert scarce human review time from fixing to verifying.** A per-PR verification report (build/test results + screenshot + an explicit "needs your eyes" list) is the mechanism.
- **Build and test failures are real defects and route back to implement**, exactly like review findings. A simulator/screenshot failure is environmental (boot failure, busy device) and is retried, not blamed on the code — distinguishing the two prevents false bounce-backs.
- **GitHub has no official API to attach media to issues/PRs** (the web drag-drop needs a browser cookie, unusable headless). Screenshots are uploaded as release assets via `gh release upload` to a dedicated prerelease and linked by URL — the headless-supported path that keeps binaries out of `main`'s history.
- **Targeted per-screen screenshots need navigation hooks the app does not expose**, so this layer captures the app's launch state as proof it boots; the visual correctness judgment stays with the human.
- Strive's build and test commands require `set -o pipefail` and `xcbeautify` or `xcodebuild` hangs (`Strive/CLAUDE.md`, Commands section); these come from config so other repos can differ.
- Builds on the feature/PR flow already in `otto/otto.py`.

## Requirements
1. config.toml gains `build_cmd`, `test_cmd`, `sim_name`, and `artifacts_release_tag` — repo-specific commands stay out of the code.
2. After a feature's sub-issues are committed and before the PR opens, otto.py runs `build_cmd` in the worktree; a non-zero build routes the feature back into the implement→review fix loop with the build output as the finding, up to `max_fix_rounds` — build failure is a real defect.
3. otto.py runs `test_cmd`; a test failure routes back to implement with the failing output, up to `max_fix_rounds` — same treatment as build.
4. otto.py boots a simulator named `sim_name`, launches the app, and captures a screenshot via `xcrun simctl`; a simulator/launch/capture error is retried once, and a second failure is recorded in the report as "screenshot unavailable" and does NOT route back to implement or block the PR — environmental failures are not code defects.
5. otto.py uploads captured screenshots as assets on the `artifacts_release_tag` release (creating the prerelease if absent) and obtains their URLs.
6. otto.py posts a verification report as the PR body and as a comment on the parent issue, containing: build result, test result, screenshot link (or "unavailable"), and a "Needs your eyes" line naming the human-only checks — the report is what the human reviews.
7. otto.py opens the PR only after build and test pass, or after `max_fix_rounds` is exhausted, in which case the report states the unresolved failures — the human is told what is unverified.

## Files
- `otto/otto.py` — Modify. Add the build/test gate (with bounce-back), simulator screenshot capture, release-asset upload, and report generation into the pre-PR step.
- `otto/config.toml` — Modify. Add `build_cmd`, `test_cmd`, `sim_name`, `artifacts_release_tag`.

## Test expectations
- A feature that builds and whose tests pass → PR body and a parent-issue comment contain build ✓, test ✓, and a screenshot link.
- A build that fails once then passes after a fix round → fix loop runs, then the PR opens.
- Tests that fail past `max_fix_rounds` → PR opens with a report stating the unresolved test failures.
- A simulator that fails to boot twice → report says "screenshot unavailable", PR still opens, no fix round triggered by the screenshot failure.

## Boundaries
- Does NOT capture screens beyond the app's launch state — targeted per-screen capture needs navigation the app does not expose.
- Does NOT make the visual correctness judgment — that is the human's review.
- Does NOT record video.
- Does NOT commit screenshots into the repository — they are uploaded as release assets.
- Does NOT merge the PR.
