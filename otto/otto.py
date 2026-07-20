"""Otto: label-driven GitHub automation loop.

Watches for issues the operator labels `AI Ready`, runs the ideate skill
headlessly against the repo clone, relays genuine questions through the
issue's Slack thread (acknowledging the operator's answers as they
arrive), and writes the finished spec into the issue (or into
sub-issues for multi-unit work) under `status:spec-ready`. Spec-ready
issues are then driven through the implement and review skills in a
dedicated worktree and opened as pull requests for human review: a leaf
issue as one commit, a parent with sub-issues as one commit per sub-issue
in blocked-by order on a single feature branch. Before a PR opens, a
verify gate builds and tests the branch (bouncing failures back into fix
rounds), captures a launch screenshot on the simulator, and posts a
verification report as the PR body and an issue comment; the opened PR is
announced in the issue's Slack thread. Open otto PRs are
polled for operator review feedback and revised by resuming the PR's
session; orphaned claims are routed to a human, closed-PR worktrees are
cleaned up, `max_open_prs` pauses new implementation while review backs
up, and a `PAUSED` file in data_dir halts the loop entirely. Labels are
the whole state machine; GitHub is the only durable store. Stdlib only.
"""

import json
import os
import re
import signal
import subprocess
import time
import traceback
from pathlib import Path

import slack

AI_READY = "AI Ready"
LABEL_IDEATING = "status:ideating"
LABEL_AWAITING = "status:awaiting-answers"
LABEL_SPEC_READY = "status:spec-ready"
LABEL_IN_PROGRESS = "status:in-progress"
LABEL_IN_REVIEW = "status:in-review"
LABEL_NEEDS_HUMAN = "status:needs-human"
STATUS_LABELS = {
    LABEL_IDEATING: ("bfd4f2", "otto is ideating this issue"),
    LABEL_AWAITING: ("fbca04", "otto is waiting on operator answers"),
    LABEL_SPEC_READY: ("0e8a16", "spec written into the issue, ready to build"),
    LABEL_NEEDS_HUMAN: ("d93f0b", "otto could not proceed without a human"),
}

SPEC_MARKER = "<!-- otto:spec -->"
# Spec 006 requirement 3 asks otto to tell its comments apart from the
# operator's "by comment author login", but otto posts through the
# operator's own gh login, so author is identical on both sides. This
# marker, standing on its own line of a comment body, is the
# distinguishing signal instead. Detection is line-exact (is_otto_comment)
# because a quote-reply repeats the marker behind `> ` prefixes and must
# still count as operator feedback.
PR_COMMENT_MARKER = "<!-- otto:pr-comment -->"
# Stamps an otto reply with the timestamp of the newest feedback item it
# covers; feedback posted while a revision run was underway stays newer
# than this cutoff and is picked up on a later cycle.
FEEDBACK_THROUGH_TEMPLATE = "<!-- otto:feedback-through:{ts} -->"
FEEDBACK_THROUGH_RE = re.compile(r"<!-- otto:feedback-through:(\S+) -->")
SPEC_HEADING = "## Otto Spec"
SESSION_MARKER_TEMPLATE = "<!-- otto:ideate-session:{id} -->"
SESSION_MARKER_RE = re.compile(r"<!-- otto:ideate-session:([A-Za-z0-9-]+) -->")
FENCED_JSON_RE = re.compile(r"```(?:json)?[ \t]*\n(.*)```", re.DOTALL)

QUESTIONS_SENTINEL = "OTTO_QUESTIONS"
SPEC_SENTINEL = "OTTO_SPEC"

# ACK_PREFIX identifies acks in reply detection; every ack ever posted
# starts with it, including early ones whose wording differed after it.
ACK_PREFIX = "Got your answers"
ACK_TEXT = ACK_PREFIX + ". Working on them now."

PRIORITY_RE = re.compile(r"priority:(\d+)")
VERDICT_RE = re.compile(r"^VERDICT: (CLEAN|ISSUES)\s*$", re.MULTILINE)
VERDICT_INSTRUCTION = (
    "End your final message with exactly `VERDICT: CLEAN` or "
    "`VERDICT: ISSUES` on its own line."
)
CONVENTIONAL_PREFIX_RE = re.compile(
    r"^(fix|feat|refactor|docs|test|chore|spec|localization)(\([^)]*\))?!?: "
)
ISSUE_TAG_RE = re.compile(r"^\[\d+\]\s*")

OVERRIDES = """Overrides for this run:
- Do NOT write any files. Deliver spec content only in your final message, in the format below.
- Research first: read this repository and search the web to answer your own questions. Ask the operator only what genuinely requires their judgment: product/UX preference, scope tradeoffs, constraints you cannot discover.
- If questions remain after research, end your final message with a line reading exactly OTTO_QUESTIONS followed by a numbered list of the questions, nothing after the list.
- When the spec is settled, end your final message with a line reading exactly OTTO_SPEC followed by one fenced json block: {"overview": "<markdown feature overview>", "units": [{"title": "<issue title>", "spec": "<full markdown spec with Objective, Context, Requirements, Files, Test expectations, Boundaries>", "depends_on": [<zero-based indexes of units this unit builds on>]}]}. A single-unit decomposition has exactly one entry in units."""


class OttoFailure(Exception):
    """A step otto cannot finish on its own; routes the issue to a human."""


class TransientError(Exception):
    """An infrastructure call failed; the issue keeps its state for a retry."""


class RunCancelled(Exception):
    """A human closed or unclaimed the issue mid-run; abort without a PR."""


def log(pass_name: str, issue: object, outcome: str) -> None:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    print(f"{stamp} pass={pass_name} issue={issue} outcome={outcome}", flush=True)


def log_step(
    issue: object,
    step: str,
    outcome: str,
    pass_num: object = "-",
    verdict: str = "-",
) -> None:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    print(
        f"{stamp} issue={issue} step={step} pass={pass_num} "
        f"verdict={verdict} outcome={outcome}",
        flush=True,
    )


def issue_url(config: dict, number: int) -> str:
    return f"https://github.com/{config['repo']}/issues/{number}"


def slack_escalate(config: dict, number: int, text: str) -> None:
    """Post a needs-human summary to the issue's Slack thread, best-effort."""
    try:
        slack.post_to_thread(number, text, config)
    except Exception as error:
        log("slack", number, f"escalation failed: {error}")


# --- gh plumbing ---------------------------------------------------------


def _gh(config: dict, args: list[str], input_text: str | None = None) -> str:
    try:
        result = subprocess.run(
            ["gh", *args],
            input=input_text,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise TransientError(f"gh {' '.join(args[:3])} timed out") from None
    if result.returncode != 0:
        raise TransientError(
            f"gh {' '.join(args[:3])} failed: {result.stderr.strip()[:300]}"
        )
    return result.stdout


def gh_issue_list(config: dict, label: str, state: str, fields: str) -> list[dict]:
    out = _gh(
        config,
        [
            "issue",
            "list",
            "--repo",
            config["repo"],
            "--label",
            label,
            "--state",
            state,
            "--json",
            fields,
            "--limit",
            "200",
        ],
    )
    return json.loads(out)


def gh_issue_view(config: dict, number: int, fields: str) -> dict:
    out = _gh(
        config,
        ["issue", "view", str(number), "--repo", config["repo"], "--json", fields],
    )
    return json.loads(out)


def gh_edit_body(config: dict, number: int, body: str) -> None:
    _gh(
        config,
        ["issue", "edit", str(number), "--repo", config["repo"], "--body-file", "-"],
        input_text=body,
    )


def gh_comment(config: dict, number: int, body: str) -> None:
    _gh(
        config,
        ["issue", "comment", str(number), "--repo", config["repo"], "--body-file", "-"],
        input_text=body,
    )


def label_names(issue: dict) -> set[str]:
    return {label["name"] for label in issue.get("labels", [])}


def swap_status(
    config: dict,
    number: int,
    new_label: str | None,
    current_names: set[str] | None = None,
) -> None:
    """Remove otto's status:* labels and add new_label (if any) in one edit."""
    if current_names is None:
        current_names = label_names(gh_issue_view(config, number, "labels"))
    args = ["issue", "edit", str(number), "--repo", config["repo"]]
    changed = False
    for name in sorted(current_names):
        if name.startswith("status:") and name != new_label:
            args += ["--remove-label", name]
            changed = True
    if new_label and new_label not in current_names:
        args += ["--add-label", new_label]
        changed = True
    if changed:
        _gh(config, args)


def ensure_status_labels(config: dict) -> None:
    out = _gh(
        config,
        ["label", "list", "--repo", config["repo"], "--json", "name", "--limit", "200"],
    )
    existing = {entry["name"] for entry in json.loads(out)}
    for name, (color, description) in STATUS_LABELS.items():
        if name not in existing:
            _gh(
                config,
                [
                    "label",
                    "create",
                    name,
                    "--repo",
                    config["repo"],
                    "--color",
                    color,
                    "--description",
                    description,
                ],
            )


# --- claude invocation and sentinel parsing ------------------------------


def run_claude(
    config: dict,
    prompt: str,
    resume_id: str | None = None,
    cwd: str | None = None,
    from_pr: int | None = None,
) -> tuple[str, str]:
    """Run a skill prompt headlessly; return (result_text, session_id)."""
    cmd = [
        config["claude_bin"],
        "-p",
        "--output-format",
        "json",
        "--dangerously-skip-permissions",
    ]
    if resume_id:
        cmd += ["--resume", resume_id]
    if from_pr:
        cmd += ["--from-pr", str(from_pr)]

    def invoke() -> tuple[int, str, str]:
        process = subprocess.Popen(
            cmd,
            cwd=cwd or config["clone_path"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(prompt, timeout=config["step_timeout_s"])
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise OttoFailure(
                f"claude timed out after {config['step_timeout_s']}s"
            ) from None
        return process.returncode, stdout, stderr

    returncode, stdout, stderr = invoke()
    if returncode != 0:
        returncode, stdout, stderr = invoke()
        if returncode != 0:
            raise OttoFailure(
                f"claude exited {returncode}: {stderr.strip()[:300]}"
            )
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        raise OttoFailure("claude output was not valid json") from None
    return payload.get("result") or "", payload.get("session_id") or ""


def parse_outcome(result_text: str) -> tuple[str, object]:
    """Return ("questions", text) or ("spec", payload); raise OttoFailure otherwise."""
    lines = result_text.splitlines()
    spec_idx = None
    questions_idx = None
    for index, line in enumerate(lines):
        if line.strip() == SPEC_SENTINEL:
            spec_idx = index
        elif line.strip() == QUESTIONS_SENTINEL:
            questions_idx = index

    if spec_idx is not None and (questions_idx is None or spec_idx > questions_idx):
        tail = "\n".join(lines[spec_idx + 1 :])
        match = FENCED_JSON_RE.search(tail)
        if not match:
            raise OttoFailure("OTTO_SPEC sentinel without a fenced json block")
        try:
            payload = json.loads(match.group(1))
        except json.JSONDecodeError as error:
            raise OttoFailure(f"OTTO_SPEC json invalid: {error}") from None
        units = payload.get("units")
        if not isinstance(units, list) or not units:
            raise OttoFailure("OTTO_SPEC payload has no units")
        for index, unit in enumerate(units):
            if not unit.get("title") or not unit.get("spec"):
                raise OttoFailure("OTTO_SPEC unit missing title or spec")
            depends_on = unit.get("depends_on")
            if depends_on is None:
                depends_on = []
            if not isinstance(depends_on, list):
                raise OttoFailure(f"OTTO_SPEC unit {index} depends_on is not a list")
            for dep in depends_on:
                if type(dep) is not int or not 0 <= dep < len(units):
                    raise OttoFailure(
                        f"OTTO_SPEC unit {index} has invalid depends_on index {dep!r}"
                    )
        return "spec", payload

    if questions_idx is not None:
        questions = "\n".join(lines[questions_idx + 1 :]).strip()
        if not questions:
            raise OttoFailure("OTTO_QUESTIONS sentinel with no questions")
        return "questions", questions

    raise OttoFailure("output contains neither OTTO_QUESTIONS nor OTTO_SPEC")


# --- body markers --------------------------------------------------------


def find_session_marker(body: str) -> str | None:
    match = SESSION_MARKER_RE.search(body or "")
    return match.group(1) if match else None


def set_session_marker(body: str, session_id: str) -> str:
    cleaned = SESSION_MARKER_RE.sub("", body or "").rstrip()
    marker = SESSION_MARKER_TEMPLATE.format(id=session_id)
    return f"{cleaned}\n\n{marker}" if cleaned else marker


def spec_section(markdown: str) -> str:
    return f"{SPEC_MARKER}\n\n{SPEC_HEADING}\n\n{markdown.strip()}"


# --- ideation stage ------------------------------------------------------


def sync_clone(config: dict) -> None:
    branch = config["default_branch"]
    for cmd in (
        ["git", "fetch", "origin", branch],
        ["git", "checkout", branch],
        ["git", "merge", "--ff-only", f"origin/{branch}"],
    ):
        try:
            result = subprocess.run(
                cmd,
                cwd=config["clone_path"],
                capture_output=True,
                text=True,
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            raise TransientError(f"{' '.join(cmd)} timed out") from None
        if result.returncode != 0:
            raise TransientError(
                f"{' '.join(cmd)} failed: {result.stderr.strip()[:300]}"
            )


def build_ideation_prompt(config: dict, number: int, issue: dict) -> str:
    parts = [
        f"/ideate for GitHub issue #{number} of {config['repo']}.",
        "",
        f"Title: {issue['title']}",
        "",
        issue.get("body") or "",
    ]
    for comment in issue.get("comments", []):
        author = (comment.get("author") or {}).get("login", "unknown")
        parts += ["", f"Comment by {author}:", comment.get("body") or ""]
    parts += ["", OVERRIDES]
    return "\n".join(parts)


def park_with_questions(
    config: dict, number: int, questions: str, session_id: str
) -> None:
    if not session_id:
        raise OttoFailure("claude returned no session_id to park")
    slack.post_to_thread(number, questions, config)
    body = gh_issue_view(config, number, "body").get("body") or ""
    gh_edit_body(config, number, set_session_marker(body, session_id))
    swap_status(config, number, LABEL_AWAITING)


def land_spec(config: dict, number: int, payload: dict) -> None:
    units = payload["units"]
    if len(units) == 1:
        body = gh_issue_view(config, number, "body").get("body") or ""
        gh_edit_body(config, number, f"{body}\n\n{spec_section(units[0]['spec'])}")
    else:
        try:
            created = []
            for unit in units:
                out = _gh(
                    config,
                    [
                        "issue",
                        "create",
                        "--repo",
                        config["repo"],
                        "--parent",
                        str(number),
                        "--title",
                        unit["title"],
                        "--body-file",
                        "-",
                    ],
                    input_text=spec_section(unit["spec"]),
                )
                match = re.search(r"/issues/(\d+)", out)
                if not match:
                    raise OttoFailure(
                        f"could not parse created sub-issue from: {out.strip()[:200]}"
                    )
                created.append(int(match.group(1)))
            for index, unit in enumerate(units):
                for dep in unit.get("depends_on") or []:
                    _gh(
                        config,
                        [
                            "issue",
                            "edit",
                            str(created[index]),
                            "--repo",
                            config["repo"],
                            "--add-blocked-by",
                            str(created[dep]),
                        ],
                    )
            body = gh_issue_view(config, number, "body").get("body") or ""
            overview = payload.get("overview") or ""
            gh_edit_body(config, number, f"{body}\n\n{spec_section(overview)}")
        except TransientError as error:
            raise OttoFailure(
                "multi-unit landing interrupted; re-running would duplicate "
                f"sub-issues: {error}"
            ) from None

    try:
        swap_status(config, number, LABEL_SPEC_READY)
    except TransientError as error:
        raise OttoFailure(
            "spec landed but the swap to status:spec-ready failed; "
            f"re-running would duplicate the landed spec: {error}"
        ) from None

    try:
        issue = gh_issue_view(config, number, "body,url")
        if slack.find_thread_marker(issue.get("body") or ""):
            slack.post_to_thread(
                number,
                f"Spec is ready. Your answers settled it: {issue['url']}",
                config,
            )
    except Exception as error:
        log("slack", number, f"closing message failed: {error}")


def handle_outcome(
    config: dict, number: int, result_text: str, session_id: str
) -> str:
    kind, payload = parse_outcome(result_text)
    if kind == "questions":
        park_with_questions(config, number, payload, session_id)
        return "questions-parked"
    land_spec(config, number, payload)
    return "spec-ready"


def fail_issue(config: dict, number: int, reason: str) -> None:
    swap_status(config, number, LABEL_NEEDS_HUMAN)
    try:
        gh_comment(
            config,
            number,
            f"Otto could not finish ideation for this issue: {reason}\n\n"
            f"Automation labels were replaced with `{LABEL_NEEDS_HUMAN}`; "
            "it needs a human decision before otto can pick it up again.",
        )
    except Exception as error:
        log("fail", number, f"failure notice incomplete: {error}")
    slack_escalate(
        config,
        number,
        f"Ideation on issue #{number} needs a human ({reason}); fix, then "
        f"remove the `status:*` labels to re-ideate: {issue_url(config, number)}",
    )


def withdrawn(config: dict, number: int) -> bool:
    """The operator closed the issue or pulled `AI Ready` mid-run."""
    issue = gh_issue_view(config, number, "state,labels")
    return issue.get("state") != "OPEN" or AI_READY not in label_names(issue)


def release_claim(config: dict, number: int) -> None:
    """Best-effort unclaim after a transient error; reclaim_pass is the backstop."""
    try:
        swap_status(config, number, None)
        log("ideation", number, "claim-released")
    except Exception as error:
        log("ideation", number, f"claim release failed: {error}")


def ideation_pass(config: dict) -> None:
    issues = gh_issue_list(config, AI_READY, "open", "number,labels,parent")
    eligible = [
        issue["number"]
        for issue in issues
        if not any(name.startswith("status:") for name in label_names(issue))
        and not issue.get("parent")
    ]
    if not eligible:
        return
    number = min(eligible)
    swap_status(config, number, LABEL_IDEATING)
    log("ideation", number, "claimed")
    try:
        sync_clone(config)
        issue = gh_issue_view(config, number, "title,body,comments")
        prompt = build_ideation_prompt(config, number, issue)
        result_text, session_id = run_claude(config, prompt)
        if withdrawn(config, number):
            swap_status(config, number, None)
            log("ideation", number, "cancelled")
            return
        outcome = handle_outcome(config, number, result_text, session_id)
        log("ideation", number, outcome)
    except OttoFailure as error:
        fail_issue(config, number, str(error))
        log("ideation", number, f"failed: {error}")
    except Exception as error:
        log("ideation", number, f"transient: {error}")
        release_claim(config, number)


def reply_pass(config: dict, state: dict) -> None:
    issues = gh_issue_list(config, LABEL_AWAITING, "open", "number")
    numbers = sorted(issue["number"] for issue in issues)
    if not numbers:
        return
    number = next((n for n in numbers if n > state["last_polled"]), numbers[0])
    state["last_polled"] = number
    try:
        issue = gh_issue_view(config, number, "body")
        session_id = find_session_marker(issue.get("body") or "")
        if not session_id:
            raise OttoFailure("parked issue has no ideate-session marker")
        messages = slack.fetch_thread(number, config)
        operator = config["slack"]["operator_member_id"]
        # Acks must not advance the cutoff: if the run after an ack dies,
        # the answers behind it have to stay detectable.
        otto_stamps = [
            float(message["ts"])
            for message in messages
            if message["user"] != operator
            and not message["text"].startswith(ACK_PREFIX)
        ]
        last_otto = max(otto_stamps) if otto_stamps else 0.0
        replies = [
            message["text"]
            for message in messages
            if message["user"] == operator and float(message["ts"]) > last_otto
        ]
        if not replies:
            log("replies", number, "no-new-replies")
            return
        slack.post_to_thread(number, ACK_TEXT, config)
        swap_status(config, number, LABEL_IDEATING)
        log("replies", number, "answers-received")
        prompt = "Operator answers:\n\n" + "\n\n".join(replies) + "\n\n" + OVERRIDES
        result_text, new_session_id = run_claude(config, prompt, resume_id=session_id)
        if withdrawn(config, number):
            swap_status(config, number, None)
            log("replies", number, "cancelled")
            return
        outcome = handle_outcome(config, number, result_text, new_session_id)
        log("replies", number, outcome)
    except OttoFailure as error:
        fail_issue(config, number, str(error))
        log("replies", number, f"failed: {error}")
    except Exception as error:
        log("replies", number, f"transient: {error}")
        try:
            swap_status(config, number, LABEL_AWAITING)
        except Exception as swap_error:
            log("replies", number, f"re-park failed: {swap_error}")


def cancellation_pass(config: dict) -> None:
    for status_label in (LABEL_IDEATING, LABEL_AWAITING):
        for issue_state in ("open", "closed"):
            for issue in gh_issue_list(
                config, status_label, issue_state, "number,labels"
            ):
                names = label_names(issue)
                if issue_state == "closed" or AI_READY not in names:
                    swap_status(config, issue["number"], None, current_names=names)
                    log("cancel", issue["number"], "status-cleared")


def reclaim_pass(config: dict) -> None:
    """Requeue stale claims.

    Claims are made and resolved inside a single cycle, so `status:ideating`
    at the start of a cycle means a crash or a failed release. An issue with
    a parked session goes back to `status:awaiting-answers` (its thread
    replies resume that session) and one without is requeued, unless spec
    sub-issues already exist, in which case re-running would duplicate them
    and a human must finish.
    """
    issues = gh_issue_list(
        config, LABEL_IDEATING, "open", "number,labels,subIssues,body"
    )
    for issue in issues:
        number = issue["number"]
        crashed_multi = False
        for sub in issue.get("subIssues") or []:
            sub_body = gh_issue_view(config, sub["number"], "body").get("body") or ""
            if SPEC_MARKER in sub_body:
                crashed_multi = True
                break
        if crashed_multi:
            swap_status(config, number, LABEL_NEEDS_HUMAN, current_names=label_names(issue))
            gh_comment(
                config,
                number,
                "Otto restarted mid-ideation after spec sub-issues were already "
                "created; re-running would duplicate them. A human needs to "
                "finish or clean up the decomposition.",
            )
            slack_escalate(
                config,
                number,
                f"Ideation of issue #{number} needs a human (a restart left "
                "spec sub-issues mid-decomposition); finish or clean them up, "
                f"then relabel: {issue_url(config, number)}",
            )
            log("reclaim", number, "needs-human")
        elif find_session_marker(issue.get("body") or ""):
            swap_status(
                config, number, LABEL_AWAITING, current_names=label_names(issue)
            )
            log("reclaim", number, "re-parked")
        else:
            swap_status(config, number, None, current_names=label_names(issue))
            log("reclaim", number, "requeued")


# --- implementation stage ------------------------------------------------


def _git(config: dict, args: list[str], cwd: str | None = None) -> str:
    def invoke() -> subprocess.CompletedProcess:
        try:
            return subprocess.run(
                ["git", *args],
                cwd=cwd or config["clone_path"],
                capture_output=True,
                text=True,
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            raise OttoFailure(f"git {' '.join(args[:2])} timed out") from None

    result = invoke()
    if result.returncode != 0:
        result = invoke()
        if result.returncode != 0:
            raise OttoFailure(
                f"git {' '.join(args[:2])} failed: {result.stderr.strip()[:300]}"
            )
    return result.stdout


def sanitize_branch(branch: str) -> str:
    return branch.replace("/", "-").replace("\\", "-")


def priority_rank(issue: dict) -> float:
    ranks = [
        int(match.group(1))
        for name in label_names(issue)
        if (match := PRIORITY_RE.fullmatch(name))
    ]
    return min(ranks) if ranks else float("inf")


def select_spec_ready(config: dict) -> dict | None:
    issues = gh_issue_list(
        config,
        LABEL_SPEC_READY,
        "open",
        "number,title,body,labels,parent,subIssues,blockedBy",
    )
    candidates = []
    for issue in issues:
        if issue.get("parent"):
            continue
        if SPEC_MARKER not in (issue.get("body") or ""):
            continue
        blockers = (issue.get("blockedBy") or {}).get("nodes") or []
        if any(blocker.get("state") != "CLOSED" for blocker in blockers):
            continue
        candidates.append(issue)
    if not candidates:
        return None
    return min(candidates, key=lambda issue: (priority_rank(issue), issue["number"]))


def write_spec_file(config: dict, number: int, body: str) -> str:
    spec_text = body.split(SPEC_MARKER, 1)[1].strip()
    specs_dir = Path(config["data_dir"]) / "specs"
    specs_dir.mkdir(parents=True, exist_ok=True)
    path = specs_dir / f"iss-{number}.md"
    path.write_text(spec_text + "\n", encoding="utf-8")
    return str(path)


def parse_verdict(review_text: str) -> str:
    matches = VERDICT_RE.findall(review_text)
    if not matches:
        raise OttoFailure("review emitted no VERDICT line")
    return matches[-1]


def commit_message(title: str) -> str:
    cleaned = ISSUE_TAG_RE.sub("", title).strip()
    if CONVENTIONAL_PREFIX_RE.match(cleaned):
        return cleaned
    return f"feat: {cleaned}"


def remove_worktree(config: dict, number: int, worktree: str, branch: str) -> None:
    for args in (
        ["worktree", "remove", "--force", worktree],
        ["branch", "-D", branch],
    ):
        try:
            _git(config, args)
        except Exception as error:
            log_step(number, "cleanup", f"git {args[0]} failed: {error}")


def fail_implementation(
    config: dict, number: int, reason: str, worktree: str, branch: str
) -> None:
    try:
        swap_status(config, number, LABEL_NEEDS_HUMAN)
        gh_comment(
            config,
            number,
            f"Otto could not finish implementing this issue: {reason}\n\n"
            f"Automation labels were replaced with `{LABEL_NEEDS_HUMAN}`; "
            "it needs a human decision before otto can pick it up again. "
            f"Any commits already pushed remain on `{branch}` for inspection.",
        )
    except Exception as error:
        log_step(number, "failure", f"failure notice incomplete: {error}")
    slack_escalate(
        config,
        number,
        f"Implementing issue #{number} needs a human ({reason}); fix, then "
        f"relabel `{LABEL_SPEC_READY}` to re-queue: {issue_url(config, number)}",
    )
    remove_worktree(config, number, worktree, branch)


def check_run_cancelled(config: dict, number: int) -> None:
    """Abort if a human closed the issue or pulled its claim mid-run."""
    issue = gh_issue_view(config, number, "state,labels")
    if issue.get("state") != "OPEN" or LABEL_IN_PROGRESS not in label_names(issue):
        raise RunCancelled(f"issue #{number} closed or unclaimed externally")


def claim_issue(config: dict, issue: dict) -> None:
    number = issue["number"]
    swap_status(config, number, LABEL_IN_PROGRESS, current_names=label_names(issue))
    _gh(
        config,
        ["issue", "edit", str(number), "--repo", config["repo"], "--add-assignee", "@me"],
    )
    log_step(number, "claim", "claimed")


def create_worktree(config: dict, number: int, branch: str, worktree: str) -> None:
    sync_clone(config)
    _git(
        config,
        ["worktree", "add", worktree, "-b", branch, config["default_branch"]],
    )
    log_step(number, "worktree", "created")


def implement_and_review(
    config: dict, number: int, spec_path: str, worktree: str
) -> str:
    _, session_id = run_claude(config, f"/implement {spec_path}", cwd=worktree)
    if not session_id:
        raise OttoFailure("implement run returned no session_id")
    log_step(number, "implement", "done")

    review_prompt = f"/review {spec_path}\n\n{VERDICT_INSTRUCTION}"
    for pass_num in range(1, config["max_fix_rounds"] + 1):
        review_text, _ = run_claude(config, review_prompt, cwd=worktree)
        verdict = parse_verdict(review_text)
        log_step(number, "review", "reviewed", pass_num=pass_num, verdict=verdict)
        if verdict == "CLEAN":
            break
        fix_prompt = (
            f"{review_text}\n\n"
            "Fix these review findings. Leave all changes uncommitted."
        )
        _, session_id = run_claude(
            config, fix_prompt, resume_id=session_id, cwd=worktree
        )
        log_step(number, "fix", "fixed", pass_num=pass_num)
    return session_id


def commit_and_push(
    config: dict, number: int, title: str, branch: str, worktree: str
) -> None:
    _git(config, ["add", "-A"], cwd=worktree)
    _git(config, ["commit", "-m", commit_message(title)], cwd=worktree)
    log_step(number, "commit", "committed")
    _git(config, ["push", "-u", "origin", branch], cwd=worktree)
    log_step(number, "push", branch)


# --- verify stage --------------------------------------------------------


def run_verify_cmd(config: dict, worktree: str, cmd: str) -> tuple[bool, str]:
    """Run a build or test command in the worktree; return (passed, output)."""
    try:
        result = subprocess.run(
            ["/bin/bash", "-c", cmd],
            cwd=worktree,
            capture_output=True,
            text=True,
            timeout=config["step_timeout_s"],
        )
    except subprocess.TimeoutExpired:
        raise OttoFailure(
            f"verify command timed out after {config['step_timeout_s']}s"
        ) from None
    output = result.stdout
    if result.stderr:
        output = f"{output}\n{result.stderr}" if output else result.stderr
    return result.returncode == 0, output.strip()


def tail(text: str, limit: int = 3000) -> str:
    text = text.strip()
    return text if len(text) <= limit else "…" + text[-limit:]


def verify_fix_round(
    config: dict,
    number: int,
    worktree: str,
    branch: str,
    stage: str,
    output: str,
    session_id: str,
) -> str:
    """Feed a build/test failure back as a finding; commit and push any fix."""
    fix_prompt = (
        f"The {stage} command failed after implementation. The failure is a "
        "code defect in this branch; find and fix it.\n\n"
        f"Command output:\n\n```\n{tail(output, 20000)}\n```\n\n"
        "Fix the underlying defects. Leave all changes uncommitted."
    )
    _, new_session_id = run_claude(
        config, fix_prompt, resume_id=session_id or None, cwd=worktree
    )
    if _git(config, ["status", "--porcelain"], cwd=worktree).strip():
        _git(config, ["add", "-A"], cwd=worktree)
        _git(config, ["commit", "-m", f"fix: resolve {stage} failures"], cwd=worktree)
        _git(config, ["push", "origin", branch], cwd=worktree)
    log_step(number, "verify-fix", stage)
    return new_session_id or session_id


def build_test_gate(
    config: dict, number: int, worktree: str, branch: str, session_id: str
) -> dict:
    """Build and test the branch, bouncing failures back into fix rounds.

    Fix rounds are budgeted at max_fix_rounds total across the gate; once
    exhausted, the remaining failure is returned unresolved so the PR can
    open with it stated in the report. test_ok None means the tests never
    ran because the build failed.
    """
    rounds = 0
    while True:
        build_ok, build_output = run_verify_cmd(config, worktree, config["build_cmd"])
        log_step(number, "build", "pass" if build_ok else "fail", pass_num=rounds)
        if not build_ok:
            if rounds >= config["max_fix_rounds"]:
                return {
                    "build_ok": False,
                    "build_output": build_output,
                    "test_ok": None,
                    "test_output": "",
                }
            rounds += 1
            session_id = verify_fix_round(
                config, number, worktree, branch, "build", build_output, session_id
            )
            continue
        test_ok, test_output = run_verify_cmd(config, worktree, config["test_cmd"])
        log_step(number, "test", "pass" if test_ok else "fail", pass_num=rounds)
        if not test_ok:
            if rounds >= config["max_fix_rounds"]:
                return {
                    "build_ok": True,
                    "build_output": build_output,
                    "test_ok": False,
                    "test_output": test_output,
                }
            rounds += 1
            session_id = verify_fix_round(
                config, number, worktree, branch, "test", test_output, session_id
            )
            continue
        return {
            "build_ok": True,
            "build_output": build_output,
            "test_ok": True,
            "test_output": test_output,
        }


def _simctl(args: list[str], timeout: int = 180) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout
    )


def latest_built_app() -> str:
    derived = Path.home() / "Library/Developer/Xcode/DerivedData"
    apps = sorted(
        derived.glob("*/Build/Products/Debug-iphonesimulator/*.app"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not apps:
        raise RuntimeError("no built .app under DerivedData")
    return str(apps[0])


def simulator_capture(config: dict, number: int) -> str:
    """Boot sim_name, install and launch the freshly built app, screenshot it."""
    sim = config["sim_name"]
    boot = _simctl(["bootstatus", sim, "-b"], timeout=300)
    if boot.returncode != 0:
        raise RuntimeError(f"simulator boot failed: {boot.stderr.strip()[:200]}")
    app_path = latest_built_app()
    install = _simctl(["install", sim, app_path])
    if install.returncode != 0:
        raise RuntimeError(f"install failed: {install.stderr.strip()[:200]}")
    plist = subprocess.run(
        ["plutil", "-extract", "CFBundleIdentifier", "raw", f"{app_path}/Info.plist"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if plist.returncode != 0:
        raise RuntimeError(f"bundle id read failed: {plist.stderr.strip()[:200]}")
    bundle_id = plist.stdout.strip()
    _simctl(["terminate", sim, bundle_id])
    launch = _simctl(["launch", sim, bundle_id])
    if launch.returncode != 0:
        raise RuntimeError(f"launch failed: {launch.stderr.strip()[:200]}")
    time.sleep(5)
    shots_dir = Path(config["data_dir"]) / "screenshots"
    shots_dir.mkdir(parents=True, exist_ok=True)
    shot_path = shots_dir / f"iss-{number}-{int(time.time())}.png"
    shot = _simctl(["io", sim, "screenshot", str(shot_path)])
    if shot.returncode != 0:
        raise RuntimeError(f"screenshot failed: {shot.stderr.strip()[:200]}")
    return str(shot_path)


def capture_screenshot(config: dict, number: int) -> str | None:
    """Capture the launch state; a failure is environmental, so retry once."""
    for attempt in (1, 2):
        try:
            path = simulator_capture(config, number)
            log_step(number, "screenshot", "captured")
            return path
        except Exception as error:
            log_step(number, "screenshot", f"attempt {attempt} failed: {error}")
    return None


def upload_screenshot(config: dict, number: int, path: str) -> str | None:
    """Upload the screenshot to the artifacts prerelease; return its URL."""
    tag = config["artifacts_release_tag"]
    repo = config["repo"]
    try:
        try:
            _gh(config, ["release", "view", tag, "--repo", repo, "--json", "name"])
        except TransientError:
            _gh(
                config,
                [
                    "release",
                    "create",
                    tag,
                    "--repo",
                    repo,
                    "--prerelease",
                    "--title",
                    "Otto artifacts",
                    "--notes",
                    "Screenshots otto attaches to pull request reports.",
                ],
            )
        _gh(config, ["release", "upload", tag, path, "--repo", repo, "--clobber"])
        assets = json.loads(
            _gh(config, ["release", "view", tag, "--repo", repo, "--json", "assets"])
        )
        name = Path(path).name
        for asset in assets.get("assets") or []:
            if asset.get("name") == name and asset.get("url"):
                return asset["url"]
        return f"https://github.com/{repo}/releases/download/{tag}/{name}"
    except Exception as error:
        log_step(number, "screenshot", f"upload failed: {error}")
        return None


def render_report(gate: dict, screenshot_url: str | None) -> str:
    build_line = "✓ passed" if gate["build_ok"] else "✗ failed"
    if gate["test_ok"] is None:
        test_line = "not run (build failed)"
    else:
        test_line = "✓ passed" if gate["test_ok"] else "✗ failed"
    shot_line = (
        f"[app launch]({screenshot_url})" if screenshot_url else "unavailable"
    )
    lines = [
        "## Otto verification report",
        "",
        f"- Build: {build_line}",
        f"- Tests: {test_line}",
        f"- Screenshot: {shot_line}",
    ]
    failures = []
    if not gate["build_ok"]:
        failures.append(("Build", gate["build_output"]))
    if gate["test_ok"] is False:
        failures.append(("Tests", gate["test_output"]))
    if failures:
        lines += [
            "",
            "### Unresolved failures",
            "",
            "Fix rounds are exhausted; this branch is unverified until these "
            "are resolved:",
        ]
        for stage, output in failures:
            lines += ["", f"**{stage}**", "", "```", tail(output), "```"]
    lines += [
        "",
        "**Needs your eyes:** visual correctness of the launch screenshot, "
        "product behavior beyond the automated checks, and the diff itself.",
    ]
    return "\n".join(lines) + "\n"


def verify_stage(
    config: dict, number: int, worktree: str, branch: str, session_id: str
) -> str:
    """Run the pre-PR gate: build, test, screenshot; return the report."""
    gate = build_test_gate(config, number, worktree, branch, session_id)
    screenshot_url = None
    if gate["build_ok"]:
        shot_path = capture_screenshot(config, number)
        if shot_path:
            screenshot_url = upload_screenshot(config, number, shot_path)
    return render_report(gate, screenshot_url)


def post_report_comment(config: dict, number: int, report: str) -> None:
    try:
        gh_comment(config, number, report)
        log_step(number, "report", "commented")
    except Exception as error:
        log_step(number, "report", f"issue comment failed: {error}")


def open_pull_request(
    config: dict, number: int, branch: str, title: str, body: str
) -> str:
    out = _gh(
        config,
        [
            "pr",
            "create",
            "--repo",
            config["repo"],
            "--head",
            branch,
            "--base",
            config["default_branch"],
            "--title",
            title,
            "--body-file",
            "-",
        ],
        input_text=body,
    )
    url = out.strip().splitlines()[-1] if out.strip() else ""
    log_step(number, "pr", url or "opened")
    return url


def announce_pr(config: dict, number: int, url: str) -> None:
    """Post the PR link to the issue's Slack thread, best-effort."""
    try:
        slack.post_to_thread(number, f"PR is ready for review: {url}", config)
    except Exception as error:
        log_step(number, "slack", f"pr notice failed: {error}")


def finish_in_review(config: dict, number: int) -> None:
    try:
        swap_status(config, number, LABEL_IN_REVIEW)
        log_step(number, "relabel", LABEL_IN_REVIEW)
    except Exception as error:
        log_step(number, "relabel", f"failed, PR is open: {error}")


def run_implementation(
    config: dict, issue: dict, branch: str, worktree: str
) -> None:
    number = issue["number"]
    claim_issue(config, issue)
    create_worktree(config, number, branch, worktree)
    spec_path = write_spec_file(config, number, issue.get("body") or "")
    session_id = implement_and_review(config, number, spec_path, worktree)
    check_run_cancelled(config, number)
    commit_and_push(config, number, issue["title"], branch, worktree)
    report = verify_stage(config, number, worktree, branch, session_id)
    check_run_cancelled(config, number)
    pr_url = open_pull_request(
        config,
        number,
        branch,
        commit_message(issue["title"]),
        f"Closes #{number}\n\n{report}",
    )
    announce_pr(config, number, pr_url)
    post_report_comment(config, number, report)
    finish_in_review(config, number)


def open_sub_issues(config: dict, issue: dict) -> dict[int, dict]:
    subs = {}
    for node in (issue.get("subIssues") or {}).get("nodes") or []:
        sub = gh_issue_view(
            config, node["number"], "number,title,body,state,blockedBy"
        )
        if sub.get("state") == "OPEN":
            subs[sub["number"]] = sub
    return subs


def sub_issue_order(subs: dict[int, dict]) -> list[int]:
    """Topological order of open sub-issues by their mutual blockedBy edges."""
    order: list[int] = []
    done: set[int] = set()
    remaining = sorted(subs)
    while remaining:
        ready = [
            number
            for number in remaining
            if all(
                blocker["number"] in done
                for blocker in (subs[number].get("blockedBy") or {}).get("nodes") or []
                if blocker["number"] in subs
            )
        ]
        if not ready:
            raise OttoFailure(
                "sub-issues "
                + ", ".join(f"#{number}" for number in remaining)
                + " form a blocked-by cycle"
            )
        picked = ready[0]
        order.append(picked)
        done.add(picked)
        remaining.remove(picked)
    return order


def run_feature(config: dict, issue: dict, branch: str, worktree: str) -> None:
    number = issue["number"]
    claim_issue(config, issue)
    create_worktree(config, number, branch, worktree)

    subs = open_sub_issues(config, issue)
    if not subs:
        raise OttoFailure("feature has no open sub-issues to implement")

    completed: list[int] = []
    session_id = ""
    for sub_number in sub_issue_order(subs):
        check_run_cancelled(config, number)
        sub = subs[sub_number]
        try:
            if SPEC_MARKER not in (sub.get("body") or ""):
                raise OttoFailure("no spec section in the sub-issue body")
            spec_path = write_spec_file(config, sub_number, sub["body"])
            session_id = implement_and_review(config, sub_number, spec_path, worktree)
            commit_and_push(config, sub_number, sub["title"], branch, worktree)
        except Exception as error:
            raise OttoFailure(f"sub-issue #{sub_number} failed: {error}") from None
        completed.append(sub_number)

    parent = gh_issue_view(config, number, "subIssues")
    open_outside_pr = [
        node["number"]
        for node in (parent.get("subIssues") or {}).get("nodes") or []
        if node.get("state") == "OPEN" and node["number"] not in completed
    ]
    closes = [f"Closes #{sub_number}" for sub_number in completed]
    if not open_outside_pr:
        closes.append(f"Closes #{number}")
    report = verify_stage(config, number, worktree, branch, session_id)
    check_run_cancelled(config, number)
    pr_url = open_pull_request(
        config,
        number,
        branch,
        commit_message(issue["title"]),
        "\n".join(closes) + "\n\n" + report,
    )
    announce_pr(config, number, pr_url)
    post_report_comment(config, number, report)
    finish_in_review(config, number)


def implementation_pass(config: dict, open_prs: list[dict]) -> None:
    if len(open_prs) >= config["max_open_prs"]:
        log_step(
            "-",
            "select",
            f"waiting-on-review: {len(open_prs)} open otto PRs at "
            f"max_open_prs ({config['max_open_prs']})",
        )
        return
    issue = select_spec_ready(config)
    if issue is None:
        log_step("-", "select", "idle")
        return
    number = issue["number"]
    branch = f"{config['branch_prefix']}iss-{number}"
    worktree = str(Path(config["worktree_root"]) / sanitize_branch(branch))
    log_step(number, "select", "picked")
    try:
        if ((issue.get("subIssues") or {}).get("totalCount") or 0) > 0:
            run_feature(config, issue, branch, worktree)
        else:
            run_implementation(config, issue, branch, worktree)
    except RunCancelled as error:
        log_step(number, "cancel", str(error))
        remove_worktree(config, number, worktree, branch)
    except Exception as error:
        log_step(number, "failure", f"failed: {error}")
        fail_implementation(config, number, str(error), worktree, branch)


# --- robustness: revisions, watchdog, pacing, cleanup ---------------------


def otto_pr_comment(
    config: dict, number: int, body: str, feedback_through: str = ""
) -> None:
    """Comment on a PR, marked as otto's own.

    Otto runs under the operator's gh login, so authorship cannot tell its
    messages apart from the operator's; the embedded marker can. When the
    comment answers review feedback, feedback_through records the newest
    feedback timestamp it covers, so operator comments posted during the
    run remain newer than the cutoff and get handled next cycle.
    """
    markers = [PR_COMMENT_MARKER]
    if feedback_through:
        markers.append(FEEDBACK_THROUGH_TEMPLATE.format(ts=feedback_through))
    _gh(
        config,
        ["pr", "comment", str(number), "--repo", config["repo"], "--body-file", "-"],
        input_text=f"{body}\n\n" + "\n".join(markers),
    )


def is_otto_comment(body: str) -> bool:
    """True when otto authored the body.

    The marker must stand alone on a line: a quote-reply repeats otto's
    text behind `> ` prefixes, and a quoted marker is operator feedback.
    """
    return any(line.strip() == PR_COMMENT_MARKER for line in body.splitlines())


def list_otto_prs(config: dict, pr_state: str = "open") -> list[dict]:
    """PRs whose head branch starts with branch_prefix: otto's own."""
    out = _gh(
        config,
        [
            "pr",
            "list",
            "--repo",
            config["repo"],
            "--state",
            pr_state,
            "--json",
            "number,state,headRefName,url",
            "--limit",
            "200",
        ],
    )
    return [
        pr
        for pr in json.loads(out)
        if pr["headRefName"].startswith(config["branch_prefix"])
    ]


def list_inline_comments(config: dict, number: int) -> list[dict]:
    """All inline review comments on a PR, following pagination."""
    comments: list[dict] = []
    page = 1
    while True:
        batch = json.loads(
            _gh(
                config,
                [
                    "api",
                    f"repos/{config['repo']}/pulls/{number}/comments"
                    f"?per_page=100&page={page}",
                ],
            )
        )
        comments.extend(batch)
        if len(batch) < 100:
            return comments
        page += 1


def collect_pr_feedback(config: dict, pr: dict) -> list[dict]:
    """Operator feedback on the PR that otto has not yet answered.

    Top-level PR comments, review bodies, and inline review comments all
    count. Otto shares the operator's gh login, so its own replies are told
    apart by PR_COMMENT_MARKER on its own line, not by author. The cutoff
    is the newest feedback timestamp otto's replies say they cover (their
    feedback-through stamp), falling back to a reply's own timestamp when
    it carries no stamp, so feedback posted mid-run is not lost behind
    the reply that follows it.
    """
    number = pr["number"]
    view = json.loads(
        _gh(
            config,
            [
                "pr",
                "view",
                str(number),
                "--repo",
                config["repo"],
                "--json",
                "comments,reviews",
            ],
        )
    )
    inline = list_inline_comments(config, number)
    items = []
    for comment in view.get("comments") or []:
        items.append(
            {
                "author": ((comment.get("author") or {}).get("login") or "").lower(),
                "ts": comment.get("createdAt") or "",
                "kind": "PR comment",
                "body": comment.get("body") or "",
            }
        )
    for review in view.get("reviews") or []:
        items.append(
            {
                "author": ((review.get("author") or {}).get("login") or "").lower(),
                "ts": review.get("submittedAt") or "",
                "kind": f"Review ({review.get('state') or 'COMMENTED'})",
                "body": review.get("body") or "",
            }
        )
    for comment in inline:
        line = comment.get("line") or comment.get("original_line") or "?"
        items.append(
            {
                "author": ((comment.get("user") or {}).get("login") or "").lower(),
                "ts": comment.get("created_at") or "",
                "kind": f"Inline comment on {comment.get('path') or '?'}:{line}",
                "body": comment.get("body") or "",
            }
        )
    operator = config["operator_login"].lower()
    cutoff = ""
    for item in items:
        if not is_otto_comment(item["body"]):
            continue
        stamps = FEEDBACK_THROUGH_RE.findall(item["body"])
        cutoff = max(cutoff, max(stamps) if stamps else item["ts"])
    feedback = [
        item
        for item in items
        if item["author"] == operator
        and not is_otto_comment(item["body"])
        and item["ts"] > cutoff
        and item["body"].strip()
    ]
    feedback.sort(key=lambda item: item["ts"])
    return feedback


def ensure_pr_worktree(config: dict, number: int, branch: str, worktree: str) -> None:
    """Check out the PR's branch, latest remote state, in its worktree.

    A reboot or cleanup may have removed the worktree; it is recreated from
    the branch at the standard path.
    """
    _git(config, ["fetch", "origin", branch])
    if not Path(worktree).exists():
        Path(config["worktree_root"]).mkdir(parents=True, exist_ok=True)
        # `git worktree add` refuses a path that is still registered to a
        # deleted checkout, so deregister missing worktrees before adding.
        _git(config, ["worktree", "prune"])
        if _git(config, ["branch", "--list", branch]).strip():
            _git(config, ["worktree", "add", worktree, branch])
        else:
            _git(
                config,
                [
                    "worktree",
                    "add",
                    "--track",
                    "-b",
                    branch,
                    worktree,
                    f"origin/{branch}",
                ],
            )
        log_step(number, "worktree", "recreated")
    _git(config, ["checkout", branch], cwd=worktree)
    _git(config, ["merge", "--ff-only", f"origin/{branch}"], cwd=worktree)


def build_revision_prompt(config: dict, pr: dict, feedback: list[dict]) -> str:
    parts = [
        f"Operator review feedback on PR #{pr['number']} ({pr.get('url') or ''}). "
        "Address every item below with code changes on this branch, leave all "
        "changes uncommitted, and end your final message with a short summary "
        "of what you changed; that summary is posted back to the PR.",
    ]
    for item in feedback:
        parts += ["", f"{item['kind']}:", "", item["body"]]
    return "\n".join(parts)


def run_revision(config: dict, pr: dict, feedback: list[dict]) -> None:
    number = pr["number"]
    branch = pr["headRefName"]
    worktree = str(Path(config["worktree_root"]) / sanitize_branch(branch))
    ensure_pr_worktree(config, number, branch, worktree)
    result_text, _ = run_claude(
        config,
        build_revision_prompt(config, pr, feedback),
        cwd=worktree,
        from_pr=number,
    )
    if _git(config, ["status", "--porcelain"], cwd=worktree).strip():
        _git(config, ["add", "-A"], cwd=worktree)
        _git(
            config,
            ["commit", "-m", "fix: address PR review feedback"],
            cwd=worktree,
        )
        _git(config, ["push", "origin", branch], cwd=worktree)
        log_step(number, "revise", "pushed")
    else:
        log_step(number, "revise", "no-changes")
    reply = result_text.strip() or "Revised per the review feedback."
    otto_pr_comment(
        config,
        number,
        tail(reply, 60000),
        feedback_through=max(item["ts"] for item in feedback),
    )
    log_step(number, "revise", "replied")


def escalate_revision(
    config: dict, pr: dict, feedback: list[dict], reason: str
) -> None:
    """Route a failed revision to a human.

    The PR comment's feedback-through stamp covers the feedback that
    failed, so the same feedback does not re-trigger a revision every
    cycle while feedback posted mid-run still gets picked up.
    """
    number = pr["number"]
    try:
        otto_pr_comment(
            config,
            number,
            f"Otto could not revise this PR from the review feedback: "
            f"{reason}\n\nA human needs to handle the feedback; otto acts "
            "only on feedback newer than the items this comment covers.",
            feedback_through=max((item["ts"] for item in feedback), default=""),
        )
    except Exception as error:
        log_step(number, "revise", f"failure notice incomplete: {error}")
    match = re.search(r"iss-(\d+)$", pr["headRefName"])
    if not match:
        return
    issue_number = int(match.group(1))
    try:
        swap_status(config, issue_number, LABEL_NEEDS_HUMAN)
    except Exception as error:
        log_step(issue_number, "revise", f"needs-human relabel failed: {error}")
    slack_escalate(
        config,
        issue_number,
        f"Revising PR #{number} needs a human ({reason}); fix, then leave "
        f"fresh feedback on the PR: {pr.get('url') or ''}",
    )


def revision_pass(config: dict, open_prs: list[dict]) -> bool:
    """Revise at most one PR from operator feedback; True if a run happened."""
    for pr in sorted(open_prs, key=lambda pr: pr["number"]):
        try:
            feedback = collect_pr_feedback(config, pr)
        except Exception as error:
            log_step(pr["number"], "revise", f"feedback check failed: {error}")
            continue
        if not feedback:
            continue
        log_step(pr["number"], "revise", f"{len(feedback)} feedback items")
        try:
            run_revision(config, pr, feedback)
        except OttoFailure as error:
            log_step(pr["number"], "revise", f"failed: {error}")
            escalate_revision(config, pr, feedback, str(error))
        except Exception as error:
            log_step(pr["number"], "revise", f"transient, retries next cycle: {error}")
        return True
    return False


def remove_stale_checkout(config: dict, number: int, branch: str) -> None:
    """Remove the worktree and local branch a dead run left behind.

    Left in place they make `create_worktree` fail when the operator
    relabels the issue `status:spec-ready` to re-queue it.
    """
    worktree = Path(config["worktree_root"]) / sanitize_branch(branch)
    if worktree.exists():
        try:
            _git(config, ["worktree", "remove", "--force", str(worktree)])
            log("orphan", number, "stale worktree removed")
        except Exception as error:
            log("orphan", number, f"worktree remove failed: {error}")
    try:
        if _git(config, ["branch", "--list", branch]).strip():
            _git(config, ["branch", "-D", branch])
            log("orphan", number, "stale local branch removed")
    except Exception as error:
        log("orphan", number, f"branch delete failed: {error}")


def orphan_pass(config: dict, open_prs: list[dict]) -> None:
    """Route claimed issues whose runs died to a human.

    A `status:in-progress` issue with no open otto PR lost its subprocess
    with the process: a crash or reboot.
    """
    issues = gh_issue_list(config, LABEL_IN_PROGRESS, "open", "number,labels")
    if not issues:
        return
    open_heads = {pr["headRefName"] for pr in open_prs}
    for issue in issues:
        number = issue["number"]
        branch = f"{config['branch_prefix']}iss-{number}"
        if branch in open_heads:
            continue
        try:
            swap_status(
                config, number, LABEL_NEEDS_HUMAN, current_names=label_names(issue)
            )
        except Exception as error:
            log("orphan", number, f"relabel failed: {error}")
            continue
        remove_stale_checkout(config, number, branch)
        try:
            gh_comment(
                config,
                number,
                "Otto claimed this issue but its run died with the process "
                "(crash or reboot) before a pull request opened.\n\n"
                f"Automation labels were replaced with `{LABEL_NEEDS_HUMAN}`. "
                f"Relabel `{LABEL_SPEC_READY}` to re-queue implementation, or "
                "remove all `status:*` labels to re-ideate.",
            )
        except Exception as error:
            log("orphan", number, f"failure notice incomplete: {error}")
        slack_escalate(
            config,
            number,
            f"Issue #{number} was in progress with no open PR (its run died); "
            f"fix, then relabel `{LABEL_SPEC_READY}` to re-queue: "
            f"{issue_url(config, number)}",
        )
        log("orphan", number, "needs-human")


def cleanup_pass(config: dict) -> None:
    """Remove worktrees and local branches whose PRs are closed or merged."""
    prefix = config["branch_prefix"]
    local_branches = {
        line.strip()
        for line in _git(
            config,
            ["for-each-ref", "--format=%(refname:short)", f"refs/heads/{prefix}"],
        ).splitlines()
        if line.strip()
    }
    root = Path(config["worktree_root"])
    if not local_branches and not (root.exists() and any(root.iterdir())):
        return
    prs = list_otto_prs(config, "all")
    open_heads = {pr["headRefName"] for pr in prs if pr["state"] == "OPEN"}
    for pr in prs:
        if pr["state"] == "OPEN" or pr["headRefName"] in open_heads:
            continue
        branch = pr["headRefName"]
        worktree = root / sanitize_branch(branch)
        removed = []
        if worktree.exists():
            try:
                _git(config, ["worktree", "remove", "--force", str(worktree)])
                removed.append("worktree")
            except Exception as error:
                log_step(pr["number"], "cleanup", f"worktree remove failed: {error}")
        if branch in local_branches:
            try:
                _git(config, ["branch", "-D", branch])
                removed.append("local branch")
            except Exception as error:
                log_step(pr["number"], "cleanup", f"branch delete failed: {error}")
        if removed:
            log_step(pr["number"], "cleanup", f"{branch}: removed {', '.join(removed)}")


# --- loop ----------------------------------------------------------------


def run_cycle(config: dict, state: dict) -> None:
    reclaim_pass(config)
    cancellation_pass(config)
    open_prs = list_otto_prs(config)
    orphan_pass(config, open_prs)
    cleanup_pass(config)
    revised = revision_pass(config, open_prs)
    reply_pass(config, state)
    ideation_pass(config)
    if revised:
        log_step("-", "select", "deferred: a revision ran this cycle")
    else:
        implementation_pass(config, open_prs)


def main() -> None:
    config = slack.load_config()
    state = {"labels_ensured": False, "last_polled": 0}
    while True:
        try:
            if (Path(config["data_dir"]) / "PAUSED").exists():
                log("cycle", "-", "paused")
            else:
                if not state["labels_ensured"]:
                    ensure_status_labels(config)
                    state["labels_ensured"] = True
                run_cycle(config, state)
                log("cycle", "-", "complete")
        except Exception:
            log("cycle", "-", f"error: {traceback.format_exc(limit=3).strip()}")
        time.sleep(config["poll_seconds"])


if __name__ == "__main__":
    main()
