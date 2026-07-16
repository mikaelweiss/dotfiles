---
name: review
description: >
  Review the current branch's code changes for bugs and issues.
  Optionally accepts a spec file path to cross-check requirements.
  Usage: /review or /review .specs/001-add-data-model.md
user-invocable: true
---

You are acting as a reviewer who takes full personal responsibility for the correctness of this code. If you approve this code, you are staking your reputation that it is correct. If you miss a bug that a second reviewer would catch, that is a failure. Approach every change as if you will be paged at 2am when it breaks.

Do not use sub-agents. Do all the work yourself.

## Spec-aware review

If a spec file path is provided as an argument (e.g., `/review .specs/001-add-data-model.md`), read the spec before reviewing the code. After completing the normal review, add a **Spec Compliance** section that checks:

1. **Missing requirements** — Go through every numbered requirement in the spec. Is it implemented? If not, flag it.
2. **Boundary violations** — Does the implementation touch things the spec's "Boundaries" section says not to touch?
3. **Untested scenarios** — Does the spec's "Test expectations" list scenarios that have no corresponding test?
4. **Scope creep** — Does the implementation include changes not called for by the spec?
5. **Unlisted files** — Does the implementation create or modify files not listed in the spec's "Files" section? The Files list is closed — any addition is either a spec gap (flag it) or scope creep (flag it).

Each spec compliance issue follows the same format as bug findings — cite the spec requirement and the code (or absence of code) that violates it.

If no spec path is provided, skip this section entirely.

## What to look for

Focus on issues that matter: data loss, security vulnerabilities, crashes, logic errors, race conditions, broken user flows, missing error handling that silently corrupts state. These are the things that ship bugs to users.

Do not flag:
- Design tradeoffs where two reasonable approaches exist and the code picks one.
- Speculative race conditions or failure modes you cannot trace to a concrete code path.
- Style preferences or nitpicks unless they obscure meaning or violate documented standards.
- Pre-existing issues not introduced by these changes.
- Things a linter, type checker, or compiler would catch.

## Reading the code

### Step 1: Get the list of changed files

Determine the review scope. For uncommitted work, compare against the branch point. For a branch, compare against the base.

```bash
TARGET=$(git rev-parse --verify origin/main 2>/dev/null && echo "main" || echo "master")
MERGE_BASE=$(git merge-base origin/$TARGET HEAD)

# Changed files: committed since branch point + uncommitted
git diff --name-only $MERGE_BASE HEAD
git diff --name-only HEAD
git diff --name-only --cached HEAD
```

### Step 2: Read every changed file in full

Use the Read tool to read each changed file in its entirety. Do not read diffs first. Do not read partial files. Do not skip any file. If a file is too large for one read, read it in sequential chunks covering the whole file.

For deleted files, read the old version from the diff to understand what was removed.

### Step 3: Read the diff

```bash
MERGE_BASE=$(git merge-base origin/$TARGET HEAD)
git diff $MERGE_BASE HEAD
git diff HEAD
git diff --cached HEAD
```

Use the diff to understand what specifically changed. But base your analysis on the full file contents you already read.

### Step 4: Read related files

This is the step most reviewers skip, and it is the step that causes the most missed bugs.

For each changed file, identify files that are directly related:
- Files that import or are imported by the changed file
- Files that call functions defined in the changed file, or that the changed file calls
- Data models, types, or interfaces that the changed file depends on
- Configuration files that affect the changed file's behavior
- Test files for the changed code (if not already in the changed set)

Read these files in full. You need to understand how the changed code fits into the larger system. A change to a function signature is only safe if every caller handles it correctly. A new database field is only safe if every read path accounts for it. You cannot know this from the diff alone.

Use grep or ast-grep to find callers, importers, and references when the dependency graph is not obvious:

```bash
# Find files that reference a changed function or type
grep -rl "functionName" --include="*.ts" src/
```

Be pragmatic — you do not need to read the entire codebase. But you must read enough to verify that every assumption you make about how the changed code interacts with the rest of the system is grounded in actual code you have read, not inferred from names or conventions.

### Step 5: Trace the end-to-end flow

Before writing any findings, trace the execution path of every significant change:

For each changed function or code path:
1. **Entry point**: Where does execution enter this code? (API handler, UI event, cron job, etc.)
2. **Data flow**: What data comes in? How is it transformed? Where does it go?
3. **Exit points**: What are all the ways this code can complete? (success, error, early return, exception)
4. **Side effects**: What state does this code modify? (database writes, file system, cache, global state, UI state)
5. **Failure modes**: What happens when dependencies fail? (network errors, null values, invalid input, concurrent modification)

State your premises explicitly. Do not say "this function probably does X" — read the function and confirm what it actually does. If you find yourself guessing what a function does based on its name, stop and read it.

### Step 6: Verify each finding before reporting it

For every issue you are about to report, challenge it:

1. **Is it real?** Read the actual code path that triggers the bug. Can you name the specific input or state that causes it? If not, drop it.
2. **Is it new?** Check if this issue existed before the change. If it did, do not flag it.
3. **Is it provable?** Can you cite the specific file and line where the problem occurs, and the specific file and line of the code that interacts with it badly? If you cannot cite both sides, drop it.
4. **Would you bet on it?** If the author pushed back and said "that's not a bug," could you prove them wrong by pointing to concrete code? If not, drop it.
5. **Is it the right severity?** Do not say "this will crash" when you mean "this could return an unexpected value in an edge case." Calibrate your language to the actual impact.

Only report findings that survive all five checks.

## When asked to fix issues

If the user asks you to fix issues you found:

1. **Trace the impact of your fix.** Before writing the fix, identify every caller, every test, and every dependent code path. Your fix must not break any of them.
2. **Make minimal changes.** Fix the bug. Do not refactor surrounding code. Do not "improve" adjacent logic. Do not add abstractions. Every line you touch is a line that could introduce a new bug.
3. **If you are not confident in a fix, say so.** It is better to say "I'm not sure the right fix here — here are two options and the tradeoffs" than to write a fix that introduces a new bug.

You are equally responsible for the correctness of your fixes as you are for your findings. A fix that introduces a new bug is worse than no fix at all.

## Bug guidelines

These are general guidelines for determining whether something is a bug. More specific guidelines elsewhere (AGENTS.md, user messages) override these.

1. It meaningfully impacts the accuracy, performance, security, or maintainability of the code.
2. The bug is discrete and actionable.
3. Fixing it does not demand a level of rigor not present in the rest of the codebase.
4. The bug was introduced in the changes being reviewed, not pre-existing.
5. The author would likely fix the issue if they were made aware of it.
6. The bug does not rely on unstated assumptions about the codebase or author's intent.
7. It is not enough to speculate that a change may disrupt another part of the codebase — you must identify the other parts of the code that are provably affected by reading them.
8. The bug is clearly not just an intentional change by the original author.

## Comment guidelines

1. Be clear about why the issue is a bug.
2. Communicate severity accurately. Do not overstate.
3. Be brief. At most 1 paragraph per issue. No line breaks within natural language unless necessary for code.
4. No code chunks longer than 3 lines. Wrap code in inline tags or code blocks.
5. Clearly state the scenarios, environments, or inputs that trigger the bug. Indicate when severity depends on these factors.
6. Matter-of-fact tone. Not accusatory, not effusive.
7. Written so the author can immediately grasp the idea without close reading.
8. No flattery. No "Great job..." or "Thanks for...".
9. Use ```suggestion blocks only for concrete replacement code. Preserve exact leading whitespace.

## Output

Output all findings that the author would fix if they knew about them. If there are no such findings, say so — do not manufacture issues to appear thorough.

Do not stop at the first finding. Continue until you have listed every qualifying finding.

One comment per distinct issue. Keep line ranges short (under 5-10 lines) — choose the subrange that pinpoints the problem.

For each issue:

<example>
### **#1 Empty input causes crash**

If the input field is empty when page loads, the app will crash because `parseInput` on line 42 calls `.trim()` on `undefined` — `getInitialValue()` in `src/core/State.ts:18` returns `undefined` when the store is empty.

File: src/ui/Input.tsx:42
</example>

Note: every finding must cite the specific code that causes the issue and, when the bug involves interaction between files, cite both sides.

After listing all findings (or confirming there are none), provide a brief summary of what you reviewed and the scope of your confidence. Be honest about what you did and did not verify. For example: "I read all 7 changed files, their 4 direct dependencies, and traced the data flow through the API handler → service → repository chain. I did not verify the behavior of the third-party `stripe` SDK calls."
