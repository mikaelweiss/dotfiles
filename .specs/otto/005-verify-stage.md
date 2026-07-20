# [005] Verify stage: build, test, screenshot, report

## Objective
Before any otto pull request opens, `otto/otto.py` builds and tests the branch, captures a screenshot of the app launching, uploads it, and posts a verification report — so the operator's review window is spent verifying, not discovering breakage.

## Context
- **The goal is converting scarce human review time from fixing to verifying.** A per-PR report (build and test results, screenshot, an explicit "needs your eyes" list) is the mechanism.
- **Build and test failures are real defects** and route back into the implement→review fix loop exactly like review findings. A simulator, launch, or capture failure is environmental (boot flake, busy device) and is retried, never blamed on the code — the distinction prevents false bounce-backs.
- **GitHub offers no headless way to attach media to PRs** (web drag-drop needs a browser cookie). Screenshots upload as assets on a dedicated prerelease via `gh release upload` and are linked by URL — the supported headless path that keeps binaries out of the default branch's history.
- **Capture is the app's launch state only** — targeted per-screen capture needs navigation hooks the app doesn't expose; visual correctness judgment stays with the operator.
- Strive's build and test commands require `set -o pipefail` and `xcbeautify` or `xcodebuild` hangs on output buffering (`/Users/mikaelweiss/code/strive/CLAUDE.md:96-115`); the commands come from config because other repos differ. `xcbeautify` is provisioned on the Mac Mini at `/run/current-system/sw/bin/xcbeautify`.
- Applies to every otto PR — leaf or feature — since both end in the same pre-PR step in `otto/otto.py`.

## Requirements
1. `otto/config.toml` gains `build_cmd`, `test_cmd`, `sim_name`, `artifacts_release_tag` — repo-specific commands stay out of the code.
2. After the last commit and before the PR opens, otto runs `build_cmd` in the worktree; a non-zero exit routes the work back into the implement→review fix loop with the build output as the finding, up to `max_fix_rounds` total across the pre-PR gate.
3. Otto then runs `test_cmd`; failures route back identically — a failing test is a defect, not an environment problem.
4. Otto boots the simulator named `sim_name`, launches the app, and captures a screenshot via `xcrun simctl`; an error anywhere in boot/launch/capture is retried once, and a second failure is recorded as "screenshot unavailable" without routing back or blocking the PR.
5. Captured screenshots upload as assets on the `artifacts_release_tag` prerelease (created if absent) and their URLs go in the report.
6. Otto posts the verification report as the PR body and as a comment on the issue that owns the branch: build result, test result, screenshot link or "unavailable", and a "Needs your eyes" line naming the human-only checks — the report is what the operator reviews first.
7. The PR opens only after build and test pass, or after fix rounds are exhausted, in which case the report states the unresolved failures — the operator is told exactly what is unverified.

## Files
- `otto/otto.py` — Modify. Insert the build/test gate with bounce-back, simulator capture with environmental retry, release-asset upload, and report generation into the pre-PR step.
- `otto/config.toml` — Modify. Add `build_cmd`, `test_cmd`, `sim_name`, `artifacts_release_tag`, with values from Strive's CLAUDE.md commands.

## Test expectations
- A branch that builds and passes tests → PR body and issue comment contain build ✓, test ✓, and a screenshot link.
- A build that fails once then passes after a fix round → the fix loop runs, then the PR opens.
- Tests failing past the fix-round budget → the PR opens with a report stating the unresolved failures.
- A simulator that fails to boot twice → "screenshot unavailable" in the report, PR opens, no fix round triggered.

## Boundaries
- Does NOT capture beyond the launch state.
- Does NOT judge visual correctness — that is the operator's review.
- Does NOT record video.
- Does NOT commit screenshots to the repository — they live on the prerelease.
- Does NOT merge the PR.
