#!/usr/bin/env python3
"""Tailor the penguin engineering processes to SureStake.

Run after the shape-initiative, implement-issue, and address-pr-feedback
patterns are approved. Re-running rewrites the same steps to the same text.
"""

import json
import os
import subprocess
import sys
import tempfile

PENGUIN = os.path.expanduser("~/code/penguin-v2/bin/penguin")
ROOT_REPO = os.path.expanduser("~/code/surestake")
REPO = "sawtooth-technologies/surestake"
LINK_SCRIPT = os.path.expanduser("~/code/dotfiles/terminal/bin/surestake-worktree-link")
JIRA_SITE = "coopertechnology.atlassian.net"
JIRA_CLOUD_ID = "e1daae9f-c689-4864-9728-25468b9c08f0"
REVIEWERS = "k8devtx,brytoncoopertech"

JIRA = (
    f"Jira is the {JIRA_SITE} site (cloudId {JIRA_CLOUD_ID}). Reach it through your Atlassian tools, "
    "never through a guessed REST call."
)


def pg(*args, body=None):
    cmd = [PENGUIN, *args, "-o", "json", "--no-input"]
    path = None
    if body is not None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(body, f)
            path = f.name
        cmd += ["--from-file", path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if path:
        os.unlink(path)
    if result.returncode != 0:
        sys.exit(f"penguin {' '.join(args)} failed:\n{result.stdout}{result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def every_page(path):
    items, cursor = [], ""
    while True:
        page = pg(*path, "--limit", "200", *(["--cursor", cursor] if cursor else []))
        items += page["items"]
        cursor = page.get("next_cursor") or ""
        if not cursor:
            return items


def get(pid):
    return pg("process", "get", pid)


def root_named(*names):
    for p in every_page(("process", "list")):
        if p.get("parent_id") is None and p["name"] in names:
            return p
    sys.exit(f"no root process named any of {names}")


def child(parent, *names):
    for cid in parent["child_ids"]:
        c = get(cid)
        if c["name"] in names:
            return c
    sys.exit(f"{parent['name']} has no child named any of {names}")


def patch(node, **fields):
    return pg("process", "update", node["id"], body=fields)


def execution(node, **changes):
    exec_ = dict(node.get("execution") or {})
    exec_.update(changes)
    return {k: v for k, v in exec_.items() if v is not None}


def agent_id(stable):
    for a in every_page(("agent", "list")):
        if a.get("stable_id") == stable:
            return a["id"]
    sys.exit(f"no agent {stable}")


def owner_person():
    people = every_page(("person", "list"))
    return sorted(people, key=lambda p: p.get("created_at", ""))[0]["id"]


def items():
    return {i["canonical_ref"] or i["name"]: i for i in every_page(("item", "list"))}


def ensure_item(name, ref, description):
    for i in every_page(("item", "list")):
        if i.get("canonical_ref") == ref:
            if i["name"] != name or i.get("description") != description:
                pg("item", "update", i["id"], "--name", name, "--description", description)
            return i["id"]
    return pg("item", "create", "--name", name, "--type", "info", "--canonical-ref", ref, "--description", description)["id"]


def io(*item_ids, register=False):
    return [{"item_id": i, "register": register} for i in item_ids]


def main():
    diana, raj, kai = agent_id("staff_software_engineer"), agent_id("software_engineer"), agent_id("junior_software_engineer")
    me = owner_person()

    work_ticket = ensure_item("Work ticket", "i.github_issue", "A Jira sub-task snapshot, a ref of system jira_issue, waiting to be built.")
    scope = ensure_item("Ticket scope", "i.issue_intent", "The parent Jira ticket and the scope agreed for it.")
    plan_item = ensure_item("Sub-task plan", "i.issue_decomposition", "The ordered sub-tasks a ticket splits into, with what blocks what.")
    findings = ensure_item("Investigation findings", "i.investigation_findings", "What a run learned about the code it is about to change.")
    impl_plan = ensure_item("Implementation plan", "i.implementation_plan", "The concrete edits and tests a change will make.")
    diff = ensure_item("Code diff", "i.code_diff", "The change sitting in a run's worktree.")
    review_findings = ensure_item("Code review findings", "i.code_review_findings", "What the independent reviewer found in a change.")
    pull_request = ensure_item("Pull request", "i.pull_request", "A ref of system github_pr naming an open pull request.")
    attention = ensure_item("PR needing attention", "i.changes_requested", "A ref of system github_pr whose PR has unresolved threads, requested changes, or a failing check.")
    ensure_item("Review feedback", "i.review_feedback", "Every comment and failing check blocking a pull request.")
    categorized = ensure_item("Categorized feedback", "i.categorized_feedback", "Each piece of PR feedback sorted into fix, explain, or ask the founder.")
    ensure_item("Thread resolutions", "i.thread_resolutions", "What happened to each review thread in a round.")
    jira_snapshot = ensure_item("Jira snapshot", "i.surestake.jira_snapshot", "The sub-tasks of the tickets in progress, with their open blockers.")
    pr_states = ensure_item("PR states", "i.surestake.pr_states", "What the PR follow-through poll found and did.")
    poll_result = ensure_item("Poll result", "i.surestake.poll_result", "A one-line record of what a poll changed.")

    shape(diana, raj, kai, me, scope, plan_item, findings)
    implement(diana, raj, kai, work_ticket, impl_plan)
    prove()
    review(raj)
    address(diana, kai, me, attention, categorized)
    subtask_poll(kai, jira_snapshot, poll_result, work_ticket)
    pr_poll(kai, pr_states, poll_result)
    print("SureStake processes are set up.")


def shape(diana, raj, kai, me, scope, plan_item, findings):
    root = root_named('Shape "a Jira ticket" into ordered issues', "Shape a Jira ticket into sub-tasks")
    patch(root, name="Shape a Jira ticket into sub-tasks", owner=diana, outputs=io(plan_item),
          description="Ground a Jira ticket in the code, agree its scope with the founder in a discussion, split it into PR-sized sub-tasks with a dependency graph, and file them under the ticket once the founder approves.")

    investigate = child(root, "Investigate the codebase first")
    patch(investigate, owner=raj, execution=execution(investigate, instruction=(
        "The Ticket scope input names the parent Jira ticket. " + JIRA + " Read that ticket in full: its description, "
        "comments, links, attachments, and any Confluence pages it links. Then build real context in the repository in "
        "your working directory: how the affected system is layered today, the conventions and prior art for similar "
        "work (AGENTS.md, docs/architecture, and the .agents/rules files AGENTS.md points to for the paths involved), the "
        "specific files and modules the ticket will touch, and the API contracts, Pact boundaries, migrations, and feature "
        "flags it implies. Report this back briefly. It is the ground every later question stands on.")))

    challenge = child(root, "Challenge the framing", "Agree the scope with the founder")
    patch(challenge, name="Agree the scope with the founder", owner=me, execution=execution(
        challenge, kind="human", tier=None, tier_rationale=None, continue_session=None, required_tool_ids=None, instruction=(
            "Talk the ticket through with the team before anything is split. From your SureStake worktree run "
            f"`p discuss --with {diana} --with {raj} \"Shape <ticket>: <what you want>\"` and keep going until the scope is "
            "sharp: the smallest useful version, what is deferred, the trade-offs, and the order the pieces depend on. "
            "The agents read the code and Jira while you talk, but they only talk there: the sub-tasks are filed later in "
            "this run, after you approve them. When the scope is settled, run `p run step complete <run> --edit` and add "
            "\"discussion\": \"<disc id>\" next to the ticket, or just save it as is and the next step finds the "
            "discussion that mentions the ticket.")),
          outputs=io(scope))

    decompose = child(root, "Decompose into ordered issues", "Split the ticket into sub-tasks")
    patch(decompose, name="Split the ticket into sub-tasks", owner=diana, execution=execution(decompose, instruction=(
        "The Ticket scope input names the parent ticket, and usually the penguin discussion where the founder agreed "
        "the scope. Read that whole discussion first: `" + PENGUIN + " discussion message list <disc_id> --limit 200 -o "
        "json` (newest first). When the input names no discussion, list discussions with `" + PENGUIN + " discussion "
        "list -o json` and read the most recent one that mentions the ticket key. The decisions and answers in it are "
        "the scope; where the discussion left something open, say so rather than deciding it. "
        "With the scope agreed, split the parent ticket into Jira sub-tasks, one pull request "
        "each. Size each so a reviewer can read it in one sitting yet it ships something real on its own: a PR that is too "
        "small costs a full merge-queue cycle for nothing, and one that is too large cannot be reviewed well. Each "
        "sub-task must be buildable from main once the sub-tasks it depends on have merged, so name its blockers "
        "explicitly; sub-tasks with no blocker between them will be built in parallel. If one reduces to \"think about "
        "X\", it is a conversation to have now, not a sub-task. For each, write a specific imperative title, a "
        "description grounded in the files it touches, testable acceptance criteria, and the sub-tasks that block it. "
        "Your final message is exactly one JSON object and nothing else: "
        "{\"parent\":\"SS-...\",\"subtasks\":[{\"ref\":\"A\",\"title\":\"...\",\"description\":\"markdown with the "
        "acceptance criteria\",\"blocked_by\":[\"refs of earlier subtasks\"]}]}, in dependency order, blockers first.")),
          outputs=io(plan_item))

    review_step = child(root, "Review the decomposition")
    patch(review_step, owner=me, execution=execution(review_step, instruction=(
        "Review the sub-task plan (`p run step get <run> <step>` shows the claimed input). Drop, merge, reorder, or "
        "re-scope any sub-task and fix the blocked_by links. Confirm the first sub-task is one you would ship on its own. "
        "Nothing is filed until you complete this step: `p run step complete <run> --edit` opens the plan in your "
        "editor. Change what you want and save; saving it unchanged approves it as it is.")))

    file_step = child(root, "File every approved issue in order", "File the sub-tasks in Jira")
    patch(file_step, name="File the sub-tasks in Jira", owner=kai, execution=execution(file_step, instruction=(
        "File the approved Sub-task plan in Jira, in order. " + JIRA + " Create each entry as a Sub-task of the plan's "
        "parent ticket in the parent's project, with its title as the summary and its description as the description. "
        "Then, for every blocked_by entry, link the two new sub-tasks so the blocker \"blocks\" the dependent one. Do not "
        "assign or transition anything. If a create fails, report the error verbatim and carry on with the rest. Your "
        "final message lists each plan ref with the key it was filed as, and each blocks link you made.")),
          outputs=io(plan_item))


def implement(diana, raj, kai, work_ticket, impl_plan):
    root = root_named("Implement an assigned GitHub issue", "Implement a Jira sub-task")
    patch(root, name="Implement a Jira sub-task", inputs=io(work_ticket), cascade_enabled=True, max_concurrent=1,
          description="Carry one Jira sub-task from To Do to an open pull request: a worktree of its own, grounded, planned, built, proven green on the checks for the files it touched, reviewed by a second model, then pushed and opened as a PR titled with its key.")

    ground = child(root, "Ground the change")
    setup = child(ground, "Stop early when the issue is gone", "Set up the worktree")
    patch(setup, name="Set up the worktree", execution=execution(setup, sentinel_scope=None, command_timeout_seconds=600, instruction=(
        "Make this run's workspace a git worktree of the SureStake checkout on a new branch named for the sub-task, so "
        "the repo's hooks link node_modules and the worktree link script links vendor and apps/api/.env, the same setup "
        "a hand-made worktree gets. A workspace that is already a worktree is left as it is."),
        acceptance_criteria=["The workspace is a worktree on branch <KEY>/<slug> cut from origin/main",
                             ".sdlc/issue_key and .sdlc/branch hold the sub-task key and branch"],
        command="\n".join([
            "set -e",
            "TICKET=${PENGUIN_INPUT_WORK_TICKET:-}",
            "KEY=$(printf '%s' \"$TICKET\" | python3 -c 'import sys,json\ntry: print(json.load(sys.stdin).get(\"id\",\"\"))\nexcept Exception: print(\"\")')",
            "[ -n \"$KEY\" ] || { echo \"the work ticket carries no Jira key: $TICKET\" 1>&2; exit 1; }",
            "SLUG=$(printf '%s' \"$TICKET\" | python3 -c 'import sys,json,re\nt=json.load(sys.stdin).get(\"title\") or \"work\"\ns=re.sub(r\"[^a-z0-9]+\",\"-\",t.lower()).strip(\"-\")[:40].strip(\"-\")\nprint(s or \"work\")')",
            "BRANCH=\"$KEY/$SLUG\"",
            f"ROOT={ROOT_REPO}",
            "if [ ! -e .git ]; then",
            "  git -C \"$ROOT\" fetch -q origin main 1>&2",
            "  if git -C \"$ROOT\" show-ref --verify --quiet \"refs/heads/$BRANCH\"; then",
            "    git -C \"$ROOT\" worktree add \"$PWD\" \"$BRANCH\" 1>&2",
            "  else",
            "    git -C \"$ROOT\" worktree add -b \"$BRANCH\" \"$PWD\" origin/main 1>&2",
            "  fi",
            f"  [ -x {LINK_SCRIPT} ] && {LINK_SCRIPT} \"$PWD\" \"$ROOT\" 1>&2 || true",
            "fi",
            "EXCL=\"$(git rev-parse --git-common-dir)/info/exclude\"",
            "mkdir -p \"$(dirname \"$EXCL\")\" .sdlc",
            "grep -qxF '.sdlc/' \"$EXCL\" 2>/dev/null || printf '.sdlc/\\n' >> \"$EXCL\"",
            "printf '%s\\n' \"$KEY\" > .sdlc/issue_key",
            "printf '%s\\n' \"$BRANCH\" > .sdlc/branch",
            "printf '{\"worktree\":\"%s\",\"branch\":\"%s\",\"ticket\":\"%s\"}\\n' \"$PWD\" \"$BRANCH\" \"$KEY\"",
        ])))

    fetch = child(ground, "Fetch the issue and its linked threads", "Claim the sub-task and read it")
    patch(fetch, name="Claim the sub-task and read it", owner=diana, execution=execution(fetch, instruction=(
        "The sub-task key is in .sdlc/issue_key. " + JIRA + " Re-read the live sub-task first: its snapshot can be hours "
        "old. If its status is already done, or it is assigned to someone other than you, write `gone` to .sdlc/premise "
        "with a one-line reason and stop. Otherwise assign it to yourself if it is unassigned, move it to In Progress, and "
        "write `ok` to .sdlc/premise. Then read the sub-task and its parent ticket in full: descriptions, every comment, "
        "and everything they link (other issues, Confluence pages, files, error messages). Fetch what they reference "
        "rather than noting it. Produce the consolidated context the rest of the run works from, naming what done looks "
        "like in a sentence or two."),
        acceptance_criteria=[".sdlc/premise holds ok or gone, read from the live sub-task",
                             "On ok, the sub-task is assigned to you and In Progress",
                             "The sub-task, its parent, and every linked reference are read in full"]))

    gate = child(ground, "Furnish the workspace from the remote", "Stop early when the sub-task is taken")
    patch(gate, name="Stop early when the sub-task is taken", execution=execution(
        gate, sentinel_scope="run", command_timeout_seconds=30, instruction=(
            "Settle the run as a clean no-op when the claim step found the sub-task done or taken, before any build spend."),
        acceptance_criteria=["A premise of gone ends the run as a no-op, a premise of ok passes on"],
        command="\n".join([
            "PREMISE=$(tr -d ' \\n' < .sdlc/premise 2>/dev/null)",
            "[ \"$PREMISE\" = ok ] || { echo \"sub-task premise is ${PREMISE:-missing}\" 1>&2; exit 75; }",
            "printf '{\"premise\":\"verified\",\"ticket\":\"%s\"}\\n' \"$(cat .sdlc/issue_key)\"",
        ])))
    patch(ground, child_ids=[setup["id"], fetch["id"], gate["id"]] + [c for c in get(ground["id"])["child_ids"] if c not in (setup["id"], fetch["id"], gate["id"])])

    install = child(ground, "Install dependencies and prepare the workspace", "Check the worktree is runnable")
    patch(install, name="Check the worktree is runnable", execution=execution(install, instruction=(
        "This workspace is a git worktree of the SureStake checkout. The repo's post-checkout hook links node_modules from "
        "the primary checkout when package-lock.json matches, and the link script links apps/api/vendor and "
        "apps/api/.env. Confirm those links exist. Only when the lockfile differs from the primary checkout, follow "
        "AGENTS.md: run `npm run worktree:deps:local`, then `npm install` here. Never commit env files. Record the exact "
        "lint, test, and build commands AGENTS.md gives for the projects this change touches, without running them: the "
        "check gate runs them.")))

    conventions = child(ground, "Read the project conventions")
    patch(conventions, execution=execution(conventions, instruction=conventions["execution"]["instruction"] + (
        " In SureStake that means AGENTS.md, every .agents/rules file its situational table names for the paths and "
        "situations this change touches (financial freeze, feature flags, permissions, web-react routes, Laravel API, "
        "Pact, comments), and docs/team/README.md. Note especially: no `any` types, never add a *.spec.ts file, and code "
        "that handles money is frozen unless the ticket names the exact change.")))

    design = child(root, "Design the change")
    plan = child(design, "Write the implementation plan")
    patch(plan, execution=execution(plan, instruction=(
        "Plan how to resolve the sub-task, given everything you now know: the problem in one line, the root cause if it "
        "is a bug, the specific edits in order (file, function, what changes), and the test that proves each. Map every "
        "invariant in .sdlc/invariants.md to the edit and test that satisfies it: an invariant with no home means the plan "
        "is incomplete. If the sub-task is already satisfied and no code change is warranted, do not manufacture a plan to "
        "ship an empty diff: post a comment on the Jira sub-task with the concrete evidence and source citations that the "
        "behavior already exists and a recommendation to close it, then write that same comment to "
        ".sdlc/already_satisfied.md. Otherwise save the plan to .sdlc/plan.md. Do not write code yet. " + JIRA)))
    noop = child(design, "Complete as already satisfied no-op")
    patch(noop, execution=execution(noop, instruction=(
        "When the plan step proved the sub-task already satisfied, settle the run as a clean no-op. Otherwise pass the "
        "implementation plan on unchanged."),
        acceptance_criteria=["With .sdlc/already_satisfied.md present the run settles as a no-op",
                             "Otherwise the incoming implementation-plan payload is emitted unchanged"],
        command="\n".join([
            "set -e",
            "[ -f .sdlc/already_satisfied.md ] && { echo 'already satisfied: settling as a no-op' 1>&2; exit 75; }",
            "[ -n \"${PENGUIN_INPUT_IMPLEMENTATION_PLAN:-}\" ] || { echo 'no implementation plan input' 1>&2; exit 75; }",
            "printf '%s' \"$PENGUIN_INPUT_IMPLEMENTATION_PLAN\" | python3 -c 'import json,sys; json.dump({\"$payload_kind\":\"inline\",\"$payload\":json.load(sys.stdin)}, sys.stdout, separators=(\",\",\":\")); print()'",
        ])))

    build = child(root, "Build the change")
    impl = child(build, "Implement the plan")
    patch(impl, execution=execution(impl, instruction=impl["execution"]["instruction"] + (
        " Follow AGENTS.md and the rule files you read: no `any` or essentially-any types, no new *.spec.ts files, no "
        "comments that restate code, and no bundled cleanup of financial code. Scope lint with `npx nx lint <project>` for "
        "the projects you touched.")))

    publish = child(root, "Open the pull request")
    text = child(publish, "Write the commit message and PR text")
    patch(text, execution=execution(text, instruction=(
        "Read the change (`git diff HEAD`, the untracked files `git status --porcelain` lists, .sdlc/plan.md) and write two "
        "files that the next steps publish verbatim. .sdlc/commit_msg.txt: one conventional commit title line "
        "(feat:/fix:/refactor:/docs:/test:/chore:), imperative, 50 characters or fewer, no period, specific to the "
        "change. Add a one-paragraph body only when the why is not obvious from the diff. No AI attribution of any kind: "
        "no Co-Authored-By, no generated-with footer, no session URL. .sdlc/pr_title.txt: the sub-task key from "
        ".sdlc/issue_key, a space, then the commit title, for example `SS-201 feat: list submittals on a project`. Do not "
        "stage or commit anything yourself."),
        acceptance_criteria=[".sdlc/commit_msg.txt is a conventional title of 50 characters or fewer with no attribution",
                             ".sdlc/pr_title.txt starts with the sub-task key"]))
    push = child(publish, "Create the branch, commit, and push")
    patch(push, execution=execution(push, sentinel_scope=None, command_timeout_seconds=1800, instruction=(
        "Commit the change on the sub-task's branch, rebase it onto the latest main, and push it. The repo's pre-push hook "
        "runs the checks for the touched files again on the way out. Scratch files never ship."),
        acceptance_criteria=["The change is committed on the branch from .sdlc/branch, never on main",
                             "The branch is rebased onto origin/main and pushed",
                             "A rebase conflict fails the run instead of pushing"],
        command="\n".join([
            "set -e",
            "BRANCH=$(cat .sdlc/branch)",
            "[ \"$(git rev-parse --abbrev-ref HEAD)\" = \"$BRANCH\" ] || git checkout -q \"$BRANCH\" 1>&2",
            "git add -A 1>&2",
            "git reset -q -- .sdlc 2>/dev/null || true",
            "git diff --cached --quiet || git commit -q -F .sdlc/commit_msg.txt 1>&2",
            "git fetch -q origin main 1>&2",
            "git rebase origin/main 1>&2 || { git rebase --abort; echo 'rebase onto origin/main conflicts: resolve it by hand' 1>&2; exit 1; }",
            "[ \"$(git rev-list --count origin/main..HEAD)\" -gt 0 ] || { echo 'nothing to ship beyond origin/main' 1>&2; exit 1; }",
            "git push -u origin \"$BRANCH\" 1>&2",
            "git rev-parse HEAD",
        ])))
    pr = child(publish, "Create the pull request")
    patch(pr, execution=execution(pr, instruction=(
        "Open the pull request from the pushed branch against main with the saved title and an empty body, and leave it "
        "open. The PR follow-through poll takes it from here: review bot, reviewers, merge queue."),
        acceptance_criteria=["A real OPEN PR exists from the sub-task branch into main with the saved title and an empty body",
                             "The emitted item is a github_pr ref naming the PR"],
        command="\n".join([
            "set -e",
            "BRANCH=$(cat .sdlc/branch)",
            f"gh pr view \"$BRANCH\" -R {REPO} --json number >/dev/null 2>&1 || gh pr create -R {REPO} --base main --head \"$BRANCH\" --title \"$(cat .sdlc/pr_title.txt)\" --body '' 1>&2",
            f"NUM=$(gh pr view \"$BRANCH\" -R {REPO} --json number -q .number)",
            f"URL=$(gh pr view \"$NUM\" -R {REPO} --json url -q .url)",
            f"test \"$(gh pr view \"$NUM\" -R {REPO} --json state -q .state)\" = OPEN",
            f"printf '{{\"$payload_kind\":\"ref\",\"system\":\"github_pr\",\"id\":\"{REPO}#%s\",\"url\":\"%s\"}}\\n' \"$NUM\" \"$URL\"",
        ])))


def prove():
    root = root_named("Prove the checks green")
    patch(root, execution=execution(root, instruction=(
        "You are engaged on this step only because the gate already ran the checks for the files this change touches (the "
        "repo's own pre-push logic: lint and tests for each touched Nx project, Pint and the companion PHPUnit test for "
        "each touched PHP file) and they failed: the failing output is in this prompt. Fix the underlying source, never the "
        "test, and never by weakening, skipping, or rationalizing a check, then reply; the gate re-runs after each reply. "
        "If the failure is the environment rather than the code, such as Docker MySQL being down for a PHP test, say so "
        "plainly instead of editing code.")))


def review(raj):
    root = root_named("Independent review of the change in this run's worktree", "Independent review of the change")
    patch(root, name="Independent review of the change")
    fresh = child(root, "Review with fresh eyes")
    patch(fresh, owner=raj, execution=execution(fresh, required_skill_names=["surestake-review"], instruction=fresh["execution"]["instruction"] + (
        " Use the surestake-review skill's method, with the staged diff (`git diff --cached`) as the change under review. "
        "You are read-only: report findings, change nothing.")))


def address(diana, kai, me, attention, categorized):
    root = root_named("Address review feedback on an open PR", "Address what blocks an open PR")
    patch(root, name="Address what blocks an open PR", inputs=io(attention), cascade_enabled=True, max_concurrent=2,
          description="Take a PR the follow-through poll flagged, gather every review comment and failing check, fix what is in scope, ask the founder about anything out of scope, reply to and resolve each thread, and push.")

    furnish = child(root, "Furnish the workspace from the remote")
    patch(furnish, execution=execution(furnish, instruction=(
        "Make this run's workspace a detached git worktree of the SureStake checkout at the PR's head, so the round works "
        "on exactly what is pushed and pushes back with HEAD:<branch>."),
        acceptance_criteria=["The workspace is a worktree at the PR head", ".sdlc/pr_number holds the PR number"],
        command="\n".join([
            "set -e",
            "REF=$(printf '%s' \"${PENGUIN_INPUT_PR_NEEDING_ATTENTION:-}\" | python3 -c 'import sys,json\ntry: print(json.load(sys.stdin).get(\"id\",\"\"))\nexcept Exception: print(\"\")')",
            "N=${REF##*#}",
            "[ -n \"$N\" ] || { echo \"the input names no PR: $REF\" 1>&2; exit 1; }",
            f"ROOT={ROOT_REPO}",
            f"HEADREF=$(gh pr view \"$N\" -R {REPO} --json headRefName -q .headRefName)",
            "if [ ! -e .git ]; then",
            "  git -C \"$ROOT\" fetch -q origin \"+refs/heads/$HEADREF:refs/remotes/origin/$HEADREF\" 1>&2",
            "  git -C \"$ROOT\" worktree add --detach \"$PWD\" \"origin/$HEADREF\" 1>&2",
            f"  [ -x {LINK_SCRIPT} ] && {LINK_SCRIPT} \"$PWD\" \"$ROOT\" 1>&2 || true",
            "fi",
            "EXCL=\"$(git rev-parse --git-common-dir)/info/exclude\"",
            "mkdir -p \"$(dirname \"$EXCL\")\" .sdlc",
            "grep -qxF '.sdlc/' \"$EXCL\" 2>/dev/null || printf '.sdlc/\\n' >> \"$EXCL\"",
            "printf '%s\\n' \"$N\" > .sdlc/pr_number",
            "printf '{\"pr\":%s,\"head\":\"%s\",\"worktree\":\"%s\"}\\n' \"$N\" \"$HEADREF\" \"$PWD\"",
        ])))

    categorize = child(root, "Analyze and categorize each feedback item")
    patch(categorize, execution=execution(categorize, required_skill_names=["surestake-review"], instruction=categorize["execution"]["instruction"] + (
        " The founder's rule for this repo: fix the major and blocking findings yourself. A minor finding that changes "
        "the scope of the PR significantly, or that is pre-existing rather than introduced here, is not yours to decide: "
        "mark it needs-founder, with what it is (explained very simply), the impact, risks, or benefits of fixing it, and "
        "whether you think it belongs in this PR. Count only in-scope should-fix items in .sdlc/should_fix_count. Your "
        "final message is exactly one JSON object and nothing else: {\"needs_founder\":\"yes\" or \"no\",\"items\":[{"
        "\"target\":\"...\",\"category\":\"should-fix|needs-founder|already-addressed|intentional-design|won't-fix\","
        "\"reason\":\"...\"}]}.")))

    decide_name = "Ask the founder about out-of-scope findings"
    existing = [get(c) for c in get(root["id"])["child_ids"]]
    decide = next((c for c in existing if c["name"] == decide_name), None)
    decide_exec = {
        "kind": "human",
        "instruction": (
            "The categorizer marked findings it should not decide alone: minor ones that change the PR's scope or are "
            "pre-existing. Read them in the Categorized feedback input (`p run step get <run> <step>`). For each, decide "
            "fix in this PR, or leave it (say whether to track it elsewhere). Run `p run step complete <run> --edit`: it "
            "opens the categorized feedback in your editor. Change each needs-founder item's category to should-fix or "
            "won't-fix and save."),
        "acceptance_criteria": ["Every needs-founder item is decided fix or leave"],
        "verification": {"kind": "skip"},
    }
    guard = {"item_id": categorized, "json_path": "$.needs_founder", "equals": "yes"}
    if decide is None:
        decide = pg("process", "create", body={
            "name": decide_name, "parent_id": root["id"], "owner": {"kind": "person", "id": me},
            "inputs": [{"item_id": categorized}], "outputs": [{"item_id": categorized}],
            "execution": decide_exec, "when": guard,
        })
    order = [c for c in get(root["id"])["child_ids"] if c != decide["id"]]
    order.insert(order.index(categorize["id"]) + 1, decide["id"])
    patch(root, child_ids=order)

    fix = child(root, "Implement the should-fix changes")
    patch(fix, execution=execution(fix, instruction=fix["execution"]["instruction"] + (
        " Fix the in-scope should-fix items and the needs-founder items the founder chose to fix; never the ones the "
        "founder left. Follow AGENTS.md and the .agents/rules files for the paths you touch.")))

    commit = child(root, "Commit and push the fixes")
    patch(commit, execution=execution(commit, command=commit["execution"]["command"].replace(
        'git commit -m "Address review feedback"', 'git commit -m "fix: address review feedback"')))


def subtask_poll(kai, jira_snapshot, poll_result, work_ticket):
    read = {"name": "Read the sub-tasks and their blockers", "owner": kai, "outputs": [jira_snapshot], "execution": {
        "kind": "agent", "tier": "tier3", "verification": {"kind": "skip"},
        "tier_rationale": "A Jira lookup or transition the instruction spells out: retrieval, not judgment, so the cheapest model on Claude Code, which is where the Jira tools are.",
        "instruction": (
            JIRA + " Find the tickets assigned to you that are in progress and are not sub-tasks (JQL: assignee = "
            "currentUser() AND statusCategory = \"In Progress\" AND issuetype not in subTaskIssueTypes()). Then list "
            "every sub-task of those tickets. For each sub-task give its key, summary, status category, and the keys of "
            "the issues linked to it as \"is blocked by\" whose status category is not Done. Your final message is "
            "exactly one JSON object and nothing else: {\"subtasks\":[{\"key\":\"SS-...\",\"title\":\"...\","
            "\"status\":\"todo|in_progress|done\",\"blocked_by\":[\"SS-...\"],\"url\":\"https://...\"}]}."),
        "acceptance_criteria": ["Every sub-task of every in-progress ticket assigned to you is listed with its open blockers"],
    }}
    release = {"name": "Put the To Do sub-tasks in the pool", "inputs": [jira_snapshot], "outputs": [poll_result], "execution": {
        "kind": "command", "verification": {"kind": "skip"}, "command_timeout_seconds": 120,
        "instruction": (
            "Supply a fresh Work ticket snapshot for each To Do sub-task, carrying its open blockers, and retire the "
            "snapshots of sub-tasks that are no longer To Do. A fresh snapshot replaces the older one of the same "
            "sub-task, which is how a sub-task whose blockers closed becomes buildable."),
        "acceptance_criteria": ["Each To Do sub-task has one live snapshot with its open blockers",
                                "Snapshots of sub-tasks no longer To Do are retired"],
        "command": "\n".join([
            "set -e",
            "printf '%s' \"${PENGUIN_INPUT_JIRA_SNAPSHOT:-}\" | python3 -c '",
            "import json, subprocess, sys",
            f"P = \"{PENGUIN}\"",
            "raw = sys.stdin.read()",
            "data = json.loads(raw) if raw.strip() else {}",
            "if isinstance(data, str):",
            "    data = json.loads(data[data.find(\"{\"):data.rfind(\"}\") + 1])",
            "todo = [s for s in data.get(\"subtasks\", []) if s.get(\"status\") == \"todo\"]",
            "for s in todo:",
            "    payload = json.dumps({\"system\": \"jira_issue\", \"id\": s[\"key\"], \"title\": s.get(\"title\", \"\"), \"url\": s.get(\"url\", \"\")})",
            f"    cmd = [P, \"item\", \"supply\", \"{work_ticket}\", \"--payload-kind\", \"ref\", \"--payload\", payload, \"--summary\", s[\"key\"] + \" \" + s.get(\"title\", \"\"), \"-o\", \"json\", \"--no-input\"]",
            "    for b in s.get(\"blocked_by\", []):",
            "        cmd += [\"--blocked-by\", \"jira_issue:\" + b]",
            "    subprocess.run(cmd, check=True, capture_output=True)",
            f"retire = [P, \"item\", \"retire-stale-refs\", \"{work_ticket}\", \"--system\", \"jira_issue\", \"-o\", \"json\", \"--no-input\"]",
            "for s in todo:",
            "    retire += [\"--live-id\", s[\"key\"]]",
            "subprocess.run(retire, check=True, capture_output=True)",
            "print(json.dumps({\"supplied\": [s[\"key\"] for s in todo], \"blocked\": {s[\"key\"]: s.get(\"blocked_by\", []) for s in todo if s.get(\"blocked_by\")}}))",
            "'",
        ]),
    }}
    ensure_process("Release SureStake sub-tasks whose blockers closed", kai,
                   "Every few minutes, read the sub-tasks of the tickets you have in progress and put each To Do sub-task in the pool, blocked by its open blockers, so Implement starts it the moment nothing blocks it.",
                   [read, release], "*/10 * * * *")


def pr_poll(kai, pr_states, poll_result):
    look = {"name": "Read and advance the open PRs", "outputs": [pr_states], "execution": {
        "kind": "command", "verification": {"kind": "skip"}, "command_timeout_seconds": 300,
        "instruction": (
            "For each of your open PRs on a sub-task branch (<KEY>/<slug>): flag it for a feedback round when it has an "
            "unresolved review thread or a failing check; re-request review once requested changes are addressed; request review from the team once the review "
            "bot has reviewed the head commit, checks pass, and nothing is unresolved; add it to the merge queue once a "
            "human approved it with nothing unresolved. Then list sub-task keys whose PR merged in the last day, and prune "
            "worktrees whose branch is gone."),
        "acceptance_criteria": ["Only PRs on <KEY>/<slug> branches are touched",
                                "The output says whether any merged sub-task needs closing in Jira"],
        "command": "\n".join([
            "set -e",
            f"git -C {ROOT_REPO} worktree prune 1>&2 || true",
            "python3 -c '",
            "import json, re, subprocess, datetime",
            f"P, REPO, REVIEWERS = \"{PENGUIN}\", \"{REPO}\", \"{REVIEWERS}\"",
            "def gh(*a):",
            "    return subprocess.run([\"gh\", *a], check=True, capture_output=True, text=True).stdout",
            "me = gh(\"api\", \"user\", \"-q\", \".login\").strip()",
            "branch_key = re.compile(r\"^(SS-\\d+)/\")",
            "prs = json.loads(gh(\"pr\", \"list\", \"-R\", REPO, \"--author\", me, \"--state\", \"open\", \"--limit\", \"50\", \"--json\", \"number,headRefName,headRefOid,isDraft,reviewDecision,reviewRequests,statusCheckRollup,autoMergeRequest,url\"))",
            "owner, name = REPO.split(\"/\")",
            "flagged, requested, queued = [], [], []",
            "for pr in prs:",
            "    if pr[\"isDraft\"] or not branch_key.match(pr[\"headRefName\"]):",
            "        continue",
            "    n = pr[\"number\"]",
            "    q = \"query($o:String!,$n:String!,$p:Int!){repository(owner:$o,name:$n){pullRequest(number:$p){reviewThreads(first:100){nodes{isResolved}} reviews(last:30){nodes{author{login} commit{oid}}}}}}\"",
            "    data = json.loads(gh(\"api\", \"graphql\", \"-f\", \"query=\" + q, \"-F\", \"o=\" + owner, \"-F\", \"n=\" + name, \"-F\", f\"p={n}\"))[\"data\"][\"repository\"][\"pullRequest\"]",
            "    unresolved = sum(1 for t in data[\"reviewThreads\"][\"nodes\"] if not t[\"isResolved\"])",
            "    checks = pr.get(\"statusCheckRollup\") or []",
            "    failing = any((c.get(\"conclusion\") or c.get(\"state\") or \"\").upper() in (\"FAILURE\", \"ERROR\", \"TIMED_OUT\", \"CANCELLED\") for c in checks)",
            "    pending = any((c.get(\"status\") or \"\").upper() in (\"QUEUED\", \"IN_PROGRESS\", \"PENDING\") or (c.get(\"state\") or \"\").upper() == \"PENDING\" for c in checks)",
            "    bot_reviewed = any(r[\"author\"] and r[\"author\"][\"login\"].endswith(\"[bot]\") or (r[\"author\"] or {}).get(\"login\") == \"github-actions\" for r in data[\"reviews\"][\"nodes\"] if (r.get(\"commit\") or {}).get(\"oid\") == pr[\"headRefOid\"])",
            "    if unresolved or failing:",
            "        flagged.append(n)",
            "        payload = json.dumps({\"system\": \"github_pr\", \"id\": f\"{REPO}#{n}\", \"url\": pr[\"url\"]})",
            "        subprocess.run([P, \"item\", \"supply\", \"i.changes_requested\", \"--payload-kind\", \"ref\", \"--payload\", payload, \"--summary\", f\"PR {n} needs attention\", \"-o\", \"json\", \"--no-input\"], check=True, capture_output=True)",
            "        continue",
            "    if pending:",
            "        continue",
            "    if pr[\"reviewDecision\"] == \"APPROVED\":",
            "        if not pr.get(\"autoMergeRequest\"):",
            "            subprocess.run([\"gh\", \"pr\", \"merge\", str(n), \"-R\", REPO, \"--auto\"], capture_output=True)",
            "            queued.append(n)",
            "        continue",
            "    if pr[\"reviewDecision\"] == \"CHANGES_REQUESTED\" and not pr[\"reviewRequests\"]:",
            "        subprocess.run([\"gh\", \"pr\", \"edit\", str(n), \"-R\", REPO, \"--add-reviewer\", REVIEWERS], capture_output=True)",
            "        requested.append(n)",
            "        continue",
            "    if bot_reviewed and not pr[\"reviewRequests\"] and not pr[\"reviewDecision\"]:",
            "        subprocess.run([\"gh\", \"pr\", \"edit\", str(n), \"-R\", REPO, \"--add-reviewer\", REVIEWERS], capture_output=True)",
            "        requested.append(n)",
            "live = [f\"{REPO}#{n}\" for n in flagged]",
            "retire = [P, \"item\", \"retire-stale-refs\", \"i.changes_requested\", \"--system\", \"github_pr\", \"-o\", \"json\", \"--no-input\"]",
            "for ref in live:",
            "    retire += [\"--live-id\", ref]",
            "subprocess.run(retire, check=True, capture_output=True)",
            "since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime(\"%Y-%m-%d\")",
            "merged = json.loads(gh(\"pr\", \"list\", \"-R\", REPO, \"--author\", me, \"--state\", \"merged\", \"--search\", \"merged:>=\" + since, \"--json\", \"number,headRefName\"))",
            "done = sorted({branch_key.match(p[\"headRefName\"]).group(1) for p in merged if branch_key.match(p[\"headRefName\"])})",
            "print(json.dumps({\"jira_done\": \"yes\" if done else \"no\", \"keys\": done, \"flagged\": flagged, \"review_requested\": requested, \"queued\": queued}))",
            "'",
        ]),
    }}
    close = {"name": "Close merged sub-tasks in Jira", "owner": kai, "inputs": [pr_states], "outputs": [poll_result],
             "when": {"item_id": pr_states, "json_path": "$.jira_done", "equals": "yes"}, "execution": {
        "kind": "agent", "tier": "tier3", "verification": {"kind": "skip"},
        "tier_rationale": "A Jira lookup or transition the instruction spells out: retrieval, not judgment, so the cheapest model on Claude Code, which is where the Jira tools are.",
        "instruction": (
            JIRA + " The PR States input lists sub-task keys whose PR merged. Move each one that is not already done to "
            "Done. Change nothing else. Your final message lists each key and what you did."),
        "acceptance_criteria": ["Every listed sub-task is Done"],
    }}
    ensure_process("Follow SureStake PRs through to merge", kai,
                   "Every few minutes, walk your open sub-task PRs through the review loop: flag the ones with unresolved threads or failing checks for a feedback round, request human review once the bot is satisfied, re-request it after requested changes are addressed, add approved ones to the merge queue, and close out merged ones in Jira.",
                   [look, close], "*/10 * * * *")


def ensure_process(name, owner, description, leaves, cron):
    root = next((p for p in every_page(("process", "list")) if p.get("parent_id") is None and p["name"] == name), None)
    if root is None:
        first = pg("process", "create", body=leaf_body(leaves[0]))
        root = pg("process", "create", body={
            "name": name, "description": description, "owner": {"kind": "agent", "id": owner}, "child_ids": [first["id"]],
        })
    existing = {get(c)["name"]: c for c in get(root["id"])["child_ids"]}
    order = []
    for spec in leaves:
        cid = existing.get(spec["name"])
        if cid is None:
            cid = pg("process", "create", body=dict(leaf_body(spec), parent_id=root["id"]))["id"]
        else:
            body = {"execution": spec["execution"], "inputs": [{"item_id": i} for i in spec.get("inputs", ())],
                    "outputs": [{"item_id": o} for o in spec.get("outputs", ())]}
            if spec.get("owner"):
                body["owner"] = spec["owner"]
            pg("process", "update", cid, body=body)
        order.append(cid)
    patch(get(root["id"]), child_ids=order)
    if not any(s.get("process_id") == root["id"] for s in every_page(("schedule", "list"))):
        pg("schedule", "create", "--process-id", root["id"], "--cron", cron, "--catch-up", "skip")
    return root


def leaf_body(spec):
    body = {"name": spec["name"], "execution": spec["execution"],
            "inputs": [{"item_id": i} for i in spec.get("inputs", ())],
            "outputs": [{"item_id": o} for o in spec.get("outputs", ())]}
    if spec.get("owner"):
        body["owner"] = {"kind": "agent", "id": spec["owner"]}
    if spec.get("when"):
        body["when"] = spec["when"]
    return body


if __name__ == "__main__":
    main()
