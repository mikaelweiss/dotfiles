# [005] ideate writes specs to GitHub; retire orchestrate

## Objective
Change the ideate skill to write each spec as a GitHub issue (parent + sub-issues, with blocking relations and labels) instead of `.specs/` files, and remove the orchestrate skill.

## Context
- **Specs become GitHub issues** so the backlog, priorities, and the human-in-the-loop conversation live in one place across all repos; the issue body is the spec (single source of truth) and otto.py consumes it.
- **ideate is stow-shared across all machines and repos** (`~/.claude/skills` → `claude/.claude/skills`), so this changes ideation everywhere — which matches the goal of putting all work on GitHub.
- **The existing gh-issue skill** (`claude/.claude/skills/gh-issue/SKILL.md`) already establishes the `gh` patterns to mirror: duplicate search (`gh issue list --search`), label discovery (`gh label list`), creation (`gh issue create`).
- **Decomposition logic is unchanged** (right-sizing, sequencing, the concerns checklist, the self-audit); only the output target changes from files to issues.
- A decomposition with one unit becomes a single leaf issue; one with several becomes a parent issue plus one sub-issue per unit, ordered by blocking relations — matching otto.py's leaf-vs-feature handling.
- **The orchestrate skill is removed** because otto.py performs orchestration deterministically in code and the skill's sub-agent approach has been unreliable; its history remains in git.
- **implement and review are intentionally unchanged** — otto.py adapts to them via the issue→file bridge and a verdict-line prompt, so they keep working for manual use.

## Requirements
1. The ideate skill writes its output as GitHub issues via `gh`, not `.specs/*.md` files. The spec content occupies the issue body using the existing sections (Objective, Context, Requirements, Files, Test expectations, Boundaries) — the issue body is the spec.
2. A decomposition with a single unit becomes one issue; a decomposition with multiple units becomes one parent issue (feature overview in its body) plus one sub-issue per unit (each unit's full spec in its body), created as sub-issues of the parent via `gh`.
3. ideate sets order with blocking relations between sub-issues (`gh` `--blocked-by` / `--blocking`) matching the implementation sequence, instead of numeric filename prefixes — order travels in GitHub, not filenames.
4. ideate applies labels on creation: `status:spec-ready` on each implementable issue/sub-issue once its spec is complete, a `priority:N` label for its assessed priority, and an `area:<name>` label. It discovers labels with `gh label list` and creates any missing required `status:`/`priority:` label with `gh label create` before applying it — labels are how otto.py finds and orders work, so a missing label must be created, not skipped.
5. ideate keeps its existing process: read-first, ask-only-genuine-questions, the concerns checklist, the right-size pass, and the pre-write self-audit for hedge words and what-without-why — the quality bar is unchanged.
6. ideate presents the planned issues to the user and confirms before creating them — the same confirm gate as before, now for issues.
7. The orchestrate skill is deleted.

## Files
- `claude/.claude/skills/ideate/SKILL.md` — Modify. Replace `.specs/` file output with GitHub issue/sub-issue creation (labels, blocking relations, spec-in-body), keeping the decomposition and self-audit process.
- `claude/.claude/skills/orchestrate/SKILL.md` — Delete. Orchestration moves to otto.py.

## Test expectations
- ideate on a single-unit change → one issue labeled `status:spec-ready` + `priority:N` + `area:*`, full spec in its body, and no `.specs/` files written.
- ideate on a multi-unit change → one parent issue and N sub-issues with blocking relations matching the sequence, each labeled and specced in its body.
- ideate run where the `status:spec-ready` label is missing → it creates the label before applying it.
- The orchestrate skill no longer exists.

## Boundaries
- Does NOT change the implement or review skills — they are reused as-is.
- Does NOT write `.specs/` files.
- Does NOT implement any issue it creates — creation and implementation are separate.
- Does NOT set `status:in-progress`, `status:in-review`, or `status:needs-human` — those transitions belong to the orchestrator.
