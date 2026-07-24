"""Otto: label-driven GitHub automation loop.

Watches for issues the operator labels `AI Ready`, runs the ideate skill
headlessly against the repo clone, relays genuine questions through the
issue's Slack thread (acknowledging the operator's answers as they
arrive), and writes the finished spec into the issue (or into
sub-issues for multi-unit work) under `status:spec-ready`. Ideation and
reply handling run on their own scheduler thread with up to
max_ideation_agents claude sessions at once, so the conversation never
waits on a build. Spec-ready
issues are driven through the implement and review skills by a worker
pool of up to max_implementation_agents builds at once, each in its own
worktree, and opened as pull requests for human review: a leaf
issue as one commit, a parent with sub-issues as one commit per sub-issue
in blocked-by order on a single feature branch. Before a PR opens, a
verify gate builds and tests the branch (bouncing failures back into fix
rounds) and posts a
verification report as the PR body and an issue comment; the opened PR is
announced in the issue's Slack thread. Open otto PRs are
polled for review feedback from anyone (the operator, Copilot, CI bots,
other reviewers) and revised by resuming the PR's session; every inline
comment thread gets a reply saying what changed or why nothing needed
to, then the thread is resolved, and every top-level comment gets a
thumbs-up reaction plus a summary comment covering what changed. An open
PR that falls into merge conflict with the default branch is rebased
onto it in the PR's worktree, a claude session resolving any conflicts,
and force-pushed. Claims orphaned
by a crash or reboot re-queue themselves, closed-PR worktrees are
cleaned up, `max_open_prs` pauses new implementation while review backs
up, and a `PAUSED` file in data_dir halts the loop entirely. The main
loop is a pure orchestrator: it never runs claude itself, only reads
the label state machine and dispatches workers, so no worker ever
blocks another stage. Labels are
the whole state machine; GitHub is the only durable store. Stdlib only.
"""

import json
import os
import re
import signal
import subprocess
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import linear
import slack

AI_READY = "AI Ready"
USER_REQUEST = "User Request"
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
STATUS_REACTION = {
    LABEL_IDEATING: "brain",
    LABEL_AWAITING: "raising_hand",
    LABEL_SPEC_READY: "clipboard",
    LABEL_IN_PROGRESS: "hammer",
    LABEL_IN_REVIEW: "eyes",
    LABEL_NEEDS_HUMAN: "rotating_light",
}
MERGED_REACTION = "white_check_mark"

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
REPLIES_SENTINEL = "OTTO_REPLIES"
COMMIT_TITLE_RE = re.compile(r"OTTO_COMMIT:[ \t]*(\S.*)")

# Answers are now acknowledged with a 👍 on the operator's message, but
# threads still hold text acks from before that change. ACK_PREFIX keeps
# those historical acks from advancing the reply cutoff.
ACK_PREFIX = "Got your answers"
ACK_REACTION = "thumbsup"

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


CLONE_LOCK = threading.Lock()
VERIFY_LOCK = threading.Lock()
IN_FLIGHT_LOCK = threading.Lock()
IDEATION_IN_FLIGHT: set[int] = set()
IMPLEMENTATION_IN_FLIGHT: set[int] = set()
REVISIONS_IN_FLIGHT: set[int] = set()


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
        if new_label:
            reaction = STATUS_REACTION.get(new_label)
            if reaction:
                update_root_status(config, number, reaction)


def update_root_status(config: dict, number: int, reaction: str) -> None:
    """Make `reaction` the sole status reaction on the Slack root, best-effort."""
    retired = tuple(
        name
        for name in (*STATUS_REACTION.values(), MERGED_REACTION)
        if name != reaction
    )
    try:
        slack.set_root_status(number, reaction, retired, config)
    except Exception as error:
        log("slack", number, f"root status reaction failed: {error}")


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
        "--model",
        config["model"],
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
    with CLONE_LOCK:
        _sync_clone_locked(config, branch)


def _sync_clone_locked(config: dict, branch: str) -> None:
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


def slack_thread_context(config: dict, number: int, body: str) -> str:
    """Prior otto/operator conversation from the issue's Slack thread.

    A fresh ideation of an issue that already went through a question
    round (a crashed run being redone, or an operator-triggered
    re-ideation) must not re-ask what the operator already answered;
    the thread transcript carries those answers into the prompt.
    """
    if not slack.find_thread_marker(body):
        return ""
    try:
        messages = slack.fetch_thread(number, config)
    except Exception as error:
        log("ideation", number, f"slack history unavailable: {error}")
        return ""
    operator = config["slack"]["operator_member_id"]
    lines = []
    for message in messages[1:]:
        text = message["text"].strip()
        if text:
            speaker = "operator" if message["user"] == operator else "otto"
            lines.append(f"{speaker}: {text}")
    return "\n\n".join(lines)


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
    thread = slack_thread_context(config, number, issue.get("body") or "")
    if thread:
        parts += [
            "",
            "Slack conversation between otto and the operator about this "
            "issue; questions answered here are settled, do not re-ask them:",
            "",
            thread,
        ]
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


def open_spec_sub_issues(config: dict, number: int) -> list[int]:
    """Open sub-issues of number that carry an otto spec section."""
    parent = gh_issue_view(config, number, "subIssues")
    found = []
    for node in (parent.get("subIssues") or {}).get("nodes") or []:
        if node.get("state") != "OPEN":
            continue
        sub_body = gh_issue_view(config, node["number"], "body").get("body") or ""
        if SPEC_MARKER in sub_body:
            found.append(node["number"])
    return sorted(found)


def close_superseded_sub_issue(config: dict, parent: int, number: int) -> None:
    _gh(
        config,
        [
            "issue",
            "close",
            str(number),
            "--repo",
            config["repo"],
            "--reason",
            "not planned",
            "--comment",
            f"Superseded: the decomposition of #{parent} that created this "
            "sub-issue did not complete, and the next landing recreates the "
            "full set.",
        ],
    )


def land_spec(config: dict, number: int, payload: dict) -> None:
    # Landing is idempotent: spec sub-issues a crashed or interrupted
    # earlier landing left behind are closed before this one lands, so
    # redoing a decomposition never duplicates them.
    for stale in open_spec_sub_issues(config, number):
        close_superseded_sub_issue(config, number, stale)
        log("land", number, f"stale spec sub-issue #{stale} closed")
    units = payload["units"]
    if len(units) == 1:
        body = gh_issue_view(config, number, "body").get("body") or ""
        gh_edit_body(config, number, f"{body}\n\n{spec_section(units[0]['spec'])}")
    else:
        created = []
        try:
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
            for sub_number in created:
                try:
                    close_superseded_sub_issue(config, number, sub_number)
                except Exception as cleanup_error:
                    log("land", number, f"cleanup of #{sub_number} failed: {cleanup_error}")
            raise TransientError(
                f"multi-unit landing interrupted after {len(created)} "
                f"sub-issues; they were closed so a retry lands clean: {error}"
            ) from None

    try:
        swap_status(config, number, LABEL_SPEC_READY)
    except TransientError as error:
        log(
            "land",
            number,
            f"spec landed but the swap to spec-ready failed; the reclaim "
            f"pass promotes it from the landed body: {error}",
        )


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


def eligible_for_ideation(config: dict) -> list[int]:
    issues = gh_issue_list(config, AI_READY, "open", "number,labels,parent")
    eligible = [
        issue
        for issue in issues
        if not any(name.startswith("status:") for name in label_names(issue))
        and not issue.get("parent")
    ]
    eligible.sort(key=lambda issue: (not is_user_request(issue), issue["number"]))
    return [issue["number"] for issue in eligible]


def ideate_issue(config: dict, number: int) -> None:
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


def awaiting_reply_numbers(config: dict) -> list[int]:
    issues = gh_issue_list(config, LABEL_AWAITING, "open", "number")
    return sorted(issue["number"] for issue in issues)


def new_replies(config: dict, number: int) -> list[dict]:
    """Operator messages newer than otto's last non-ack thread message.

    Historical text acks must not advance the cutoff: if the run after an
    ack dies, the answers behind it have to stay detectable.
    """
    messages = slack.fetch_thread(number, config)
    operator = config["slack"]["operator_member_id"]
    otto_stamps = [
        float(message["ts"])
        for message in messages
        if message["user"] != operator
        and not message["text"].startswith(ACK_PREFIX)
    ]
    last_otto = max(otto_stamps) if otto_stamps else 0.0
    return [
        message
        for message in messages
        if message["user"] == operator and float(message["ts"]) > last_otto
    ]


def process_replies(config: dict, number: int, replies: list[str]) -> None:
    try:
        issue = gh_issue_view(config, number, "body")
        session_id = find_session_marker(issue.get("body") or "")
        if not session_id:
            raise OttoFailure("parked issue has no ideate-session marker")
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


def run_guarded(number: int, registry: set, work) -> None:
    try:
        work()
    except Exception:
        log("worker", number, f"error: {traceback.format_exc(limit=3).strip()}")
    finally:
        with IN_FLIGHT_LOCK:
            registry.discard(number)


def schedule_reply(pool: ThreadPoolExecutor, config: dict, number: int) -> None:
    """Detect and ack new answers immediately; queue the claude run.

    Detection and the ack run here in the scheduler thread so the
    operator hears back within one tick even when every agent slot is
    busy; only the session resume waits for a slot.
    """
    with IN_FLIGHT_LOCK:
        if number in IDEATION_IN_FLIGHT:
            return
    try:
        replies = new_replies(config, number)
    except Exception as error:
        log("replies", number, f"transient: {error}")
        return
    if not replies:
        return
    with IN_FLIGHT_LOCK:
        IDEATION_IN_FLIGHT.add(number)
    try:
        slack.add_reaction(number, replies[-1]["ts"], ACK_REACTION, config)
        swap_status(config, number, LABEL_IDEATING)
        log("replies", number, "answers-received")
    except Exception as error:
        log("replies", number, f"transient: {error}")
        with IN_FLIGHT_LOCK:
            IDEATION_IN_FLIGHT.discard(number)
        try:
            swap_status(config, number, LABEL_AWAITING)
        except Exception:
            pass
        return
    texts = [message["text"] for message in replies]
    pool.submit(
        run_guarded,
        number,
        IDEATION_IN_FLIGHT,
        lambda: process_replies(config, number, texts),
    )


def schedule_ideation(pool: ThreadPoolExecutor, config: dict, number: int) -> None:
    """Queue a fresh ideation unless the agent slots are already spoken for.

    Unlike replies, fresh ideations are capped by total in-flight work so
    a deep backlog never builds a stale queue; skipped issues are simply
    reconsidered next tick.
    """
    with IN_FLIGHT_LOCK:
        if (
            number in IDEATION_IN_FLIGHT
            or len(IDEATION_IN_FLIGHT) >= config["max_ideation_agents"]
        ):
            return
        IDEATION_IN_FLIGHT.add(number)
    pool.submit(
        run_guarded, number, IDEATION_IN_FLIGHT, lambda: ideate_issue(config, number)
    )


def ideation_loop(config: dict) -> None:
    """Scheduler thread: keep answers and fresh ideations flowing.

    Replies are scheduled before fresh ideations each tick so operator
    answers get agent slots first.
    """
    pool = ThreadPoolExecutor(max_workers=config["max_ideation_agents"])
    while True:
        try:
            if not (Path(config["data_dir"]) / "PAUSED").exists():
                for number in awaiting_reply_numbers(config):
                    schedule_reply(pool, config, number)
                for number in eligible_for_ideation(config):
                    schedule_ideation(pool, config, number)
        except Exception:
            log(
                "ideation-loop",
                "-",
                f"error: {traceback.format_exc(limit=3).strip()}",
            )
        time.sleep(config["poll_seconds"])


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


def branch_pr_merged(config: dict, number: int) -> bool:
    out = _gh(
        config,
        [
            "pr", "list", "--repo", config["repo"],
            "--head", f"{config['branch_prefix']}iss-{number}",
            "--state", "merged", "--json", "number", "--limit", "1",
        ],
    )
    return bool(json.loads(out or "[]"))


def merged_pass(config: dict) -> None:
    """React ✅ on the Slack root of issues closed by a merged otto PR.

    Otto PRs carry `Closes #N`, so merging one closes its issue while the
    `status:in-review` label is still on it; a closed issue with that
    label has just left review. Clearing the label makes the pass
    one-shot. An issue closed by hand while its PR never merged gets the
    label cleared but no ✅.
    """
    for issue in gh_issue_list(config, LABEL_IN_REVIEW, "closed", "number,labels"):
        number = issue["number"]
        swap_status(config, number, None, current_names=label_names(issue))
        if branch_pr_merged(config, number):
            update_root_status(config, number, MERGED_REACTION)
            log_step(number, "merged", "root reaction set")
        else:
            log_step(number, "merged", "closed without merge, label cleared")


def reclaim_pass(config: dict) -> None:
    """Recover stale claims.

    Live ideation work is tracked in IDEATION_IN_FLIGHT, so a
    `status:ideating` issue outside that set means a crash or a failed
    release. A body that already carries a landed spec section lost only
    its label swap and is promoted straight to `status:spec-ready`. An
    issue with a parked session goes back to `status:awaiting-answers`
    (its thread replies resume that session) and one without is requeued
    for a fresh ideation; either way the next landing sweeps whatever
    sub-issues a crashed landing left behind.
    """
    issues = gh_issue_list(config, LABEL_IDEATING, "open", "number,body")
    for issue in issues:
        number = issue["number"]
        # The list is a snapshot; a worker may have finished (or a reply
        # may have claimed the issue) since it was taken. Only live state
        # is safe to act on.
        with IN_FLIGHT_LOCK:
            if number in IDEATION_IN_FLIGHT:
                continue
        live = label_names(gh_issue_view(config, number, "labels"))
        if LABEL_IDEATING not in live:
            continue
        body = issue.get("body") or ""
        if SPEC_MARKER in body:
            swap_status(config, number, LABEL_SPEC_READY, current_names=live)
            log("reclaim", number, "landed-spec-promoted")
        elif find_session_marker(body):
            swap_status(config, number, LABEL_AWAITING, current_names=live)
            log("reclaim", number, "re-parked")
        else:
            swap_status(config, number, None, current_names=live)
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


def is_user_request(issue: dict) -> bool:
    return USER_REQUEST in label_names(issue)


def priority_rank(issue: dict) -> float:
    ranks = [
        int(match.group(1))
        for name in label_names(issue)
        if (match := PRIORITY_RE.fullmatch(name))
    ]
    return min(ranks) if ranks else float("inf")


def select_spec_ready(config: dict, exclude: set[int] = frozenset()) -> dict | None:
    issues = gh_issue_list(
        config,
        LABEL_SPEC_READY,
        "open",
        "number,title,body,labels,parent,subIssues,blockedBy",
    )
    candidates = []
    for issue in issues:
        if issue["number"] in exclude or issue.get("parent"):
            continue
        if SPEC_MARKER not in (issue.get("body") or ""):
            continue
        blockers = (issue.get("blockedBy") or {}).get("nodes") or []
        if any(blocker.get("state") != "CLOSED" for blocker in blockers):
            continue
        candidates.append(issue)
    if not candidates:
        return None
    return min(
        candidates,
        key=lambda issue: (
            not is_user_request(issue),
            priority_rank(issue),
            issue["number"],
        ),
    )


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
    linear_state(config, number, "In Progress")


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


def render_report(gate: dict) -> str:
    build_line = "✓ passed" if gate["build_ok"] else "✗ failed"
    if gate["test_ok"] is None:
        test_line = "not run (build failed)"
    else:
        test_line = "✓ passed" if gate["test_ok"] else "✗ failed"
    lines = [
        "## Otto verification report",
        "",
        f"- Build: {build_line}",
        f"- Tests: {test_line}",
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
        "**Needs your eyes:** product behavior beyond the automated checks, "
        "and the diff itself.",
    ]
    return "\n".join(lines) + "\n"


def verify_stage(
    config: dict, number: int, worktree: str, branch: str, session_id: str
) -> str:
    """Run the pre-PR gate: build, test; return the report.

    The gate serializes across implementation workers: DerivedData and
    the simulator are shared, so concurrent verifies would corrupt each
    other's builds.
    """
    with VERIFY_LOCK:
        gate = build_test_gate(config, number, worktree, branch, session_id)
    return render_report(gate)


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


def linear_state(config: dict, number: int, state_name: str) -> None:
    """Move the issue's synced Linear counterpart, best-effort."""
    try:
        log_step(
            number,
            "linear",
            linear.set_state(issue_url(config, number), state_name, config),
        )
    except FileNotFoundError:
        log_step(number, "linear", "no token file, skipped")
    except Exception as error:
        log_step(number, "linear", f"update failed: {error}")


def announce_pr(config: dict, number: int, url: str) -> None:
    """Post the PR link to the issue's Slack thread, best-effort."""
    try:
        slack.post_to_thread(number, f"PR is ready for review: {url}", config)
    except Exception as error:
        log_step(number, "slack", f"pr notice failed: {error}")
    linear_state(config, number, "In Review")


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
    unspecced = sorted(
        sub_number
        for sub_number, sub in subs.items()
        if SPEC_MARKER not in (sub.get("body") or "")
    )
    for sub_number in unspecced:
        del subs[sub_number]
    if unspecced:
        log_step(
            number,
            "select",
            "skipped sub-issues without a spec section: "
            + ", ".join(f"#{sub_number}" for sub_number in unspecced),
        )
    if not subs:
        raise OttoFailure("feature has no open sub-issues with a spec section")

    completed: list[int] = []
    session_id = ""
    for sub_number in sub_issue_order(subs):
        check_run_cancelled(config, number)
        sub = subs[sub_number]
        try:
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


def implement_issue(config: dict, issue: dict, branch: str, worktree: str) -> None:
    number = issue["number"]
    # Closed sub-issues do not make a feature: a superseded decomposition
    # leaves closed subs on an issue whose landed spec lives in its own
    # body, and that spec builds as a single unit.
    has_open_subs = any(
        node.get("state") == "OPEN"
        for node in (issue.get("subIssues") or {}).get("nodes") or []
    )
    try:
        if has_open_subs:
            run_feature(config, issue, branch, worktree)
        else:
            run_implementation(config, issue, branch, worktree)
    except RunCancelled as error:
        log_step(number, "cancel", str(error))
        remove_worktree(config, number, worktree, branch)
    except Exception as error:
        log_step(number, "failure", f"failed: {error}")
        fail_implementation(config, number, str(error), worktree, branch)


def dispatch_implementation(
    config: dict, pool: ThreadPoolExecutor, open_prs: list[dict]
) -> None:
    """Fill free implementation slots with spec-ready issues.

    Open PRs plus live builds count against max_open_prs so a burst of
    dispatches cannot overshoot the review backlog cap.
    """
    while True:
        with IN_FLIGHT_LOCK:
            building = set(IMPLEMENTATION_IN_FLIGHT)
        if len(open_prs) + len(building) >= config["max_open_prs"]:
            log_step(
                "-",
                "select",
                f"waiting-on-review: {len(open_prs)} open otto PRs and "
                f"{len(building)} live builds at max_open_prs "
                f"({config['max_open_prs']})",
            )
            return
        if len(building) >= config["max_implementation_agents"]:
            return
        issue = select_spec_ready(config, exclude=building)
        if issue is None:
            if not building:
                log_step("-", "select", "idle")
            return
        number = issue["number"]
        branch = f"{config['branch_prefix']}iss-{number}"
        worktree = str(Path(config["worktree_root"]) / sanitize_branch(branch))
        with IN_FLIGHT_LOCK:
            IMPLEMENTATION_IN_FLIGHT.add(number)
        log_step(number, "select", "picked")
        pool.submit(
            run_guarded,
            number,
            IMPLEMENTATION_IN_FLIGHT,
            lambda issue=issue, branch=branch, worktree=worktree: implement_issue(
                config, issue, branch, worktree
            ),
        )


# --- robustness: revisions, watchdog, pacing, cleanup ---------------------


def otto_pr_comment(
    config: dict, number: int, body: str, feedback_through: str = ""
) -> None:
    """Comment on a PR, marked as otto's own.

    Otto runs under the operator's gh login, so authorship cannot tell its
    messages apart from the operator's; the embedded marker can. When the
    comment answers review feedback, feedback_through records the newest
    feedback timestamp it covers, so feedback posted during the run
    remains newer than the cutoff and gets handled next cycle.
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
            "number,state,headRefName,url,mergeable",
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


def list_top_level_comments(config: dict, number: int) -> list[dict]:
    """All top-level comments on a PR, following pagination.

    GraphQL rather than `gh pr view` because feedback needs what gh's
    comments json does not expose: each comment's node id (to react to
    it), its updatedAt (a status bot edits one comment in place after
    every push, and the edit must read as fresh feedback), and the
    viewer's existing 👍 reactions, whose newest timestamp is returned
    as `acked`, the comment's acknowledgment marker.
    """
    owner, name = config["repo"].split("/", 1)
    query = """
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          body
          createdAt
          updatedAt
          author { login }
          reactions(content: THUMBS_UP, first: 100) {
            nodes { createdAt user { login } }
          }
        }
      }
    }
  }
}"""
    comments: list[dict] = []
    cursor = ""
    while True:
        args = [
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-f",
            f"owner={owner}",
            "-f",
            f"name={name}",
            "-F",
            f"number={number}",
        ]
        if cursor:
            args += ["-f", f"cursor={cursor}"]
        payload = json.loads(_gh(config, args))
        viewer = payload["data"]["viewer"]["login"]
        connection = payload["data"]["repository"]["pullRequest"]["comments"]
        for node in connection["nodes"] or []:
            acked = max(
                (
                    reaction.get("createdAt") or ""
                    for reaction in (node.get("reactions") or {}).get("nodes") or []
                    if ((reaction.get("user") or {}).get("login") or "") == viewer
                ),
                default="",
            )
            comments.append(
                {
                    "node_id": node["id"],
                    "author": (node.get("author") or {}).get("login") or "",
                    "body": node.get("body") or "",
                    "ts": node.get("updatedAt") or node.get("createdAt") or "",
                    "acked": acked,
                }
            )
        page = connection["pageInfo"]
        if not page["hasNextPage"]:
            return comments
        cursor = page["endCursor"]


def fetch_review_threads(config: dict, number: int) -> dict[int, dict]:
    """Map each inline comment's database id to its review thread.

    Thread ids drive replies and resolution; isResolved lets feedback in
    threads a human already resolved be skipped.
    """
    owner, name = config["repo"].split("/", 1)
    query = """
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 100) { nodes { databaseId } }
        }
      }
    }
  }
}"""
    threads: dict[int, dict] = {}
    cursor = ""
    while True:
        args = [
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-f",
            f"owner={owner}",
            "-f",
            f"name={name}",
            "-F",
            f"number={number}",
        ]
        if cursor:
            args += ["-f", f"cursor={cursor}"]
        payload = json.loads(_gh(config, args))
        connection = payload["data"]["repository"]["pullRequest"]["reviewThreads"]
        for node in connection["nodes"] or []:
            for comment in (node.get("comments") or {}).get("nodes") or []:
                if comment.get("databaseId") is not None:
                    threads[comment["databaseId"]] = {
                        "thread_id": node["id"],
                        "resolved": bool(node["isResolved"]),
                    }
        page = connection["pageInfo"]
        if not page["hasNextPage"]:
            return threads
        cursor = page["endCursor"]


def collect_pr_feedback(config: dict, pr: dict) -> list[dict]:
    """Review feedback on the PR that otto has not yet answered.

    Top-level PR comments, review bodies, and inline review comments all
    count, from any author: the operator, Copilot, CI bots, and other
    reviewers alike. Otto shares the operator's gh login, so its own
    replies are told apart by PR_COMMENT_MARKER on its own line, not by
    author. Each kind of feedback has its own settled marker. A
    top-level comment is settled by otto's 👍 reaction: it is pending
    whenever its last edit (updatedAt) is newer than the newest 👍, so a
    status bot editing its comment in place after a push makes it fresh
    feedback again. An inline comment answers to its own thread: pending
    unless the thread is resolved or otto's reply there stamps a
    feedback-through cutoff at or past it. A review body answers to the
    PR-wide cutoff, the newest feedback timestamp otto's summary
    comments say they cover, falling back to a reply's own timestamp
    when it carries no stamp, so feedback posted mid-run is not lost
    behind the reply that follows it.
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
                "reviews",
            ],
        )
    )
    inline = list_inline_comments(config, number)
    threads = fetch_review_threads(config, number)
    items = []
    for comment in list_top_level_comments(config, number):
        items.append(
            {
                "author": comment["author"].lower(),
                "ts": comment["ts"],
                "kind": "PR comment",
                "body": comment["body"],
                "reactable_id": comment["node_id"],
                "acked": comment["acked"],
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
        thread = threads.get(comment.get("id")) or {}
        items.append(
            {
                "author": ((comment.get("user") or {}).get("login") or "").lower(),
                "ts": comment.get("created_at") or "",
                "kind": f"Inline comment on {comment.get('path') or '?'}:{line}",
                "body": comment.get("body") or "",
                "comment_id": comment.get("id"),
                "reactable_id": comment.get("node_id"),
                "thread_id": thread.get("thread_id"),
                "resolved": thread.get("resolved", False),
            }
        )
    cutoff = ""
    thread_cutoff: dict[str, str] = {}
    for item in items:
        if not is_otto_comment(item["body"]):
            continue
        stamps = FEEDBACK_THROUGH_RE.findall(item["body"])
        stamp = max(stamps) if stamps else item["ts"]
        if item.get("thread_id"):
            thread_cutoff[item["thread_id"]] = max(
                thread_cutoff.get(item["thread_id"], ""), stamp
            )
        else:
            cutoff = max(cutoff, stamp)
    feedback = []
    for item in items:
        if is_otto_comment(item["body"]) or not item["body"].strip():
            continue
        if item.get("resolved"):
            continue
        if item.get("thread_id"):
            if item["ts"] <= thread_cutoff.get(item["thread_id"], ""):
                continue
        elif item.get("reactable_id"):
            if item["ts"] <= item["acked"]:
                continue
        elif item["ts"] <= cutoff:
            continue
        feedback.append(item)
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
    instructions = (
        f"Review feedback on PR #{pr['number']} ({pr.get('url') or ''}). "
        "For every item below, either fix it with code changes on this branch "
        "or conclude the code is right as it stands; never ignore an item. "
        "Leave all changes uncommitted. End your final message with a short "
        "summary of what you changed and what you left alone and why; that "
        "summary is posted back to the PR. If you changed any code, also "
        "include a line reading exactly 'OTTO_COMMIT: <title>' where <title> "
        "is a conventional commit title for those changes (fix:/feat:/"
        "refactor: prefix, imperative, specific, 72 characters max), e.g. "
        "'OTTO_COMMIT: fix: guard bulk mailto behind canOpen'. That title "
        "becomes the commit message for this revision; omit the line if you "
        "changed nothing."
    )
    if any(item.get("tag") for item in feedback):
        instructions += (
            " Items tagged like [T1] are inline comment threads. After the "
            f"summary, add a line reading exactly {REPLIES_SENTINEL} followed "
            "by one fenced json block mapping every tag to the reply to post "
            'on that thread, e.g. {"T1": "Fixed by ...", "T2": "No change: '
            '..."}. Each reply states either what you changed or why the '
            "comment needs no change; the thread is resolved right after the "
            "reply posts."
        )
    parts = [instructions]
    for item in feedback:
        tag = f"[{item['tag']}] " if item.get("tag") else ""
        parts += ["", f"{tag}{item['kind']} by {item['author']}:", "", item["body"]]
    return "\n".join(parts)


def extract_commit_title(result_text: str) -> tuple[str, str]:
    """Split a revision result into (text without marker lines, commit title).

    The first OTTO_COMMIT line supplies the title; every OTTO_COMMIT line
    is dropped from the text so the marker never reaches the PR.
    """
    title = ""
    kept = []
    for line in result_text.splitlines():
        match = COMMIT_TITLE_RE.fullmatch(line.strip())
        if match:
            if not title:
                title = " ".join(match.group(1).split())[:72]
            continue
        kept.append(line)
    return "\n".join(kept).strip(), title


def parse_revision_replies(
    result_text: str, tags: list[str]
) -> tuple[str, dict[str, str]]:
    """Split a revision result into (summary, tag -> thread reply)."""
    lines = result_text.splitlines()
    sentinel_idx = None
    for index, line in enumerate(lines):
        if line.strip() == REPLIES_SENTINEL:
            sentinel_idx = index
    if sentinel_idx is None:
        raise OttoFailure("revision output has no OTTO_REPLIES sentinel")
    summary = "\n".join(lines[:sentinel_idx]).strip()
    match = FENCED_JSON_RE.search("\n".join(lines[sentinel_idx + 1 :]))
    if not match:
        raise OttoFailure("OTTO_REPLIES sentinel without a fenced json block")
    try:
        replies = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        raise OttoFailure(f"OTTO_REPLIES json invalid: {error}") from None
    if not isinstance(replies, dict):
        raise OttoFailure("OTTO_REPLIES json is not an object")
    missing = [tag for tag in tags if not str(replies.get(tag) or "").strip()]
    if missing:
        raise OttoFailure("OTTO_REPLIES has no reply for " + ", ".join(missing))
    return summary, {tag: str(replies[tag]).strip() for tag in tags}


def reply_in_thread(config: dict, number: int, comment_id: int, body: str) -> None:
    _gh(
        config,
        [
            "api",
            "-X",
            "POST",
            f"repos/{config['repo']}/pulls/{number}/comments/{comment_id}/replies",
            "--input",
            "-",
        ],
        input_text=json.dumps({"body": body}),
    )


def resolve_thread(config: dict, thread_id: str) -> None:
    mutation = (
        "mutation($thread: ID!) { resolveReviewThread(input: {threadId: "
        "$thread}) { thread { id } } }"
    )
    _gh(
        config,
        ["api", "graphql", "-f", f"query={mutation}", "-f", f"thread={thread_id}"],
    )


def add_reaction(config: dict, subject_id: str, content: str) -> None:
    """Add a reaction (EYES, THUMBS_UP, ...) to a comment node, idempotently."""
    mutation = (
        "mutation($subject: ID!) { addReaction(input: {subjectId: $subject, "
        "content: " + content + "}) { reaction { id } } }"
    )
    _gh(
        config,
        ["api", "graphql", "-f", f"query={mutation}", "-f", f"subject={subject_id}"],
    )


def thumbs_up(config: dict, subject_id: str) -> None:
    """React 👍 to a comment, refreshing the reaction's timestamp.

    The reaction's createdAt is the comment's acknowledgment marker, and
    addReaction on an already-reacted comment returns the old reaction
    with its old timestamp; removing first makes a re-acknowledgment
    (after the comment was edited) newer than the edit it answers.
    """
    remove = (
        "mutation($subject: ID!) { removeReaction(input: {subjectId: $subject, "
        "content: THUMBS_UP}) { reaction { id } } }"
    )
    try:
        _gh(
            config,
            ["api", "graphql", "-f", f"query={remove}", "-f", f"subject={subject_id}"],
        )
    except TransientError:
        pass
    add_reaction(config, subject_id, "THUMBS_UP")


def run_revision(config: dict, pr: dict, feedback: list[dict]) -> None:
    number = pr["number"]
    branch = pr["headRefName"]
    worktree = str(Path(config["worktree_root"]) / sanitize_branch(branch))
    threaded = [
        item for item in feedback if item.get("thread_id") and item.get("comment_id")
    ]
    for index, item in enumerate(threaded, start=1):
        item["tag"] = f"T{index}"
    ensure_pr_worktree(config, number, branch, worktree)
    result_text, _ = run_claude(
        config,
        build_revision_prompt(config, pr, feedback),
        cwd=worktree,
        from_pr=number,
    )
    result_text, commit_title = extract_commit_title(result_text)
    if _git(config, ["status", "--porcelain"], cwd=worktree).strip():
        _git(config, ["add", "-A"], cwd=worktree)
        _git(
            config,
            ["commit", "-m", commit_title or "fix: address PR review feedback"],
            cwd=worktree,
        )
    # Push whenever the branch is ahead, not only when this run changed
    # something: a crash between a prior run's commit and its push leaves
    # finished work stranded locally, and this run must publish it even
    # if it concluded nothing more needed changing.
    if _git(
        config, ["rev-list", "--count", f"origin/{branch}..HEAD"], cwd=worktree
    ).strip() != "0":
        _git(config, ["push", "origin", branch], cwd=worktree)
        log_step(number, "revise", "pushed")
    else:
        log_step(number, "revise", "no-changes")
    if threaded:
        summary, replies = parse_revision_replies(
            result_text, [item["tag"] for item in threaded]
        )
    else:
        summary, replies = result_text.strip(), {}
    # Each thread reply carries its own item's timestamp and suppression
    # is per-thread, so a failure partway through leaves the unanswered
    # threads with no otto reply and they are picked up next cycle.
    for item in threaded:
        reply_in_thread(
            config,
            number,
            item["comment_id"],
            f"{tail(replies[item['tag']], 60000)}\n\n{PR_COMMENT_MARKER}\n"
            + FEEDBACK_THROUGH_TEMPLATE.format(ts=item["ts"]),
        )
        resolve_thread(config, item["thread_id"])
        log_step(number, "revise", f"thread {item['tag']} answered and resolved")
    # Non-threaded feedback is acknowledged where it sits: each top-level
    # comment gets the 👍 that marks it settled, and one summary comment
    # answers the batch, its feedback-through stamp settling any review
    # bodies (which are not reactable). When the batch was all inline
    # threads, the thread replies say everything and no PR-wide comment
    # is added.
    unthreaded = [item for item in feedback if not item.get("tag")]
    for item in unthreaded:
        if not item.get("reactable_id"):
            continue
        try:
            thumbs_up(config, item["reactable_id"])
            log_step(
                number, "revise", f"{item['kind']} by {item['author']} acknowledged"
            )
        except Exception as error:
            log_step(number, "revise", f"reaction failed: {error}")
    if unthreaded:
        reply = summary or "Revised per the review feedback."
        otto_pr_comment(
            config,
            number,
            tail(reply, 60000),
            feedback_through=max(item["ts"] for item in unthreaded),
        )
        log_step(number, "revise", "replied")


def escalate_revision(
    config: dict, pr: dict, feedback: list[dict], reason: str
) -> None:
    """Route a failed revision to a human.

    The failure notice lands both as a PR comment and as a reply in every
    inline thread the failed batch covered, each with a feedback-through
    stamp, so the same feedback does not re-trigger a revision every
    cycle while feedback posted mid-run still gets picked up. Threads are
    left unresolved for the human to settle.
    """
    number = pr["number"]
    notice = (
        f"Otto could not revise this PR from the review feedback: {reason}"
        "\n\nA human needs to handle the feedback; otto acts only on "
        "feedback newer than the items this comment covers."
    )
    for item in feedback:
        if not (item.get("thread_id") and item.get("comment_id")):
            continue
        try:
            reply_in_thread(
                config,
                number,
                item["comment_id"],
                f"{notice}\n\n{PR_COMMENT_MARKER}\n"
                + FEEDBACK_THROUGH_TEMPLATE.format(ts=item["ts"]),
            )
        except Exception as error:
            log_step(number, "revise", f"thread failure notice incomplete: {error}")
    # A top-level comment is settled only by the 👍 marker, so the failed
    # batch's comments are acknowledged here too; without this they would
    # re-trigger a doomed revision every cycle. The notice comment tells
    # the human the 👍 means escalated, not fixed.
    for item in feedback:
        if item.get("thread_id") or not item.get("reactable_id"):
            continue
        try:
            thumbs_up(config, item["reactable_id"])
        except Exception as error:
            log_step(number, "revise", f"failure ack incomplete: {error}")
    try:
        otto_pr_comment(
            config,
            number,
            notice,
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


def revise_pr(config: dict, pr: dict, feedback: list[dict]) -> None:
    try:
        run_revision(config, pr, feedback)
    except OttoFailure as error:
        log_step(pr["number"], "revise", f"failed: {error}")
        escalate_revision(config, pr, feedback, str(error))
    except Exception as error:
        log_step(pr["number"], "revise", f"transient, retries next cycle: {error}")


def acknowledge_feedback(config: dict, number: int, feedback: list[dict]) -> None:
    """React 👀 to each fresh feedback item so its author sees otto has it.

    Runs in the orchestrator thread the moment feedback is detected, not
    in the revision worker, so the reaction lands within a poll cycle even
    when every build slot is busy and the revision itself is still queued.
    The settled marker (a 👍 or a thread reply) still follows when the
    revision finishes. Review bodies carry no reactable node and are
    acknowledged by that later reply instead.
    """
    for item in feedback:
        subject = item.get("reactable_id")
        if not subject:
            continue
        try:
            add_reaction(config, subject, "EYES")
        except Exception as error:
            log_step(number, "revise", f"eyes reaction failed: {error}")


def dispatch_revisions(
    config: dict, pool: ThreadPoolExecutor, open_prs: list[dict]
) -> None:
    """Queue a revision for every PR with fresh review feedback.

    Revisions share the implementation pool and are dispatched first, so
    review feedback gets a slot ahead of new builds.
    """
    for pr in sorted(open_prs, key=lambda pr: pr["number"]):
        number = pr["number"]
        with IN_FLIGHT_LOCK:
            if number in REVISIONS_IN_FLIGHT:
                continue
        try:
            feedback = collect_pr_feedback(config, pr)
        except Exception as error:
            log_step(number, "revise", f"feedback check failed: {error}")
            continue
        if not feedback:
            continue
        log_step(number, "revise", f"{len(feedback)} feedback items")
        acknowledge_feedback(config, number, feedback)
        with IN_FLIGHT_LOCK:
            REVISIONS_IN_FLIGHT.add(number)
        pool.submit(
            run_guarded,
            number,
            REVISIONS_IN_FLIGHT,
            lambda pr=pr, feedback=feedback: revise_pr(config, pr, feedback),
        )


def abort_rebase(config: dict, worktree: str) -> None:
    """Abort any in-progress rebase in the worktree, best-effort."""
    try:
        subprocess.run(
            ["git", "rebase", "--abort"],
            cwd=worktree,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except Exception:
        pass


def rebase_in_progress(config: dict, worktree: str) -> bool:
    for name in ("rebase-merge", "rebase-apply"):
        path = _git(config, ["rev-parse", "--git-path", name], cwd=worktree).strip()
        if (Path(worktree) / path).exists():
            return True
    return False


def run_rebase(config: dict, pr: dict) -> None:
    """Rebase a conflicted PR branch onto the default branch and force-push.

    A clean rebase pushes straight away; one that stops on conflicts hands
    the worktree to a claude session (with the PR's context) to resolve
    them and finish the rebase. Any outcome short of a completed rebase
    with a clean tree aborts back to the pre-rebase branch, so the
    worktree stays usable for revisions either way.
    """
    number = pr["number"]
    branch = pr["headRefName"]
    base = config["default_branch"]
    worktree = str(Path(config["worktree_root"]) / sanitize_branch(branch))
    if Path(worktree).exists():
        abort_rebase(config, worktree)
    ensure_pr_worktree(config, number, branch, worktree)
    _git(config, ["fetch", "origin", base], cwd=worktree)
    try:
        result = subprocess.run(
            ["git", "rebase", f"origin/{base}"],
            cwd=worktree,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        abort_rebase(config, worktree)
        raise OttoFailure(f"git rebase onto origin/{base} timed out") from None
    if result.returncode != 0:
        if not rebase_in_progress(config, worktree):
            raise OttoFailure(
                f"git rebase failed without conflicts: "
                f"{result.stderr.strip()[:300]}"
            )
        log_step(number, "rebase", "conflicts, resolving")
        prompt = (
            f"A rebase of branch {branch} onto origin/{base} stopped on "
            "merge conflicts in this worktree. Resolve every conflict so "
            "the branch keeps its intended behavior on top of the updated "
            "base: inspect each conflicted file, edit it to the correct "
            "merged result, `git add` it, and run `git rebase --continue`, "
            "repeating until the rebase completes. Never run `git rebase "
            "--abort` or `git rebase --skip`, never discard the branch's "
            "changes wholesale, and do not push."
        )
        try:
            run_claude(config, prompt, cwd=worktree, from_pr=number)
        except OttoFailure:
            abort_rebase(config, worktree)
            raise
        if rebase_in_progress(config, worktree):
            abort_rebase(config, worktree)
            raise OttoFailure("conflict resolution left the rebase unfinished")
    if _git(config, ["status", "--porcelain"], cwd=worktree).strip():
        raise OttoFailure("rebase left uncommitted changes in the worktree")
    _git(config, ["push", "--force-with-lease", "origin", branch], cwd=worktree)
    log_step(number, "rebase", "rebased and pushed")


def escalate_rebase(config: dict, pr: dict, reason: str) -> None:
    """Route a failed rebase to a human.

    The issue's `status:needs-human` label is also the suppression
    marker: dispatch_rebases skips conflicted PRs whose issue carries it,
    so the same conflict does not re-trigger a doomed rebase every cycle.
    """
    number = pr["number"]
    try:
        otto_pr_comment(
            config,
            number,
            f"Otto could not rebase this PR onto `{config['default_branch']}` "
            f"to clear its merge conflicts: {reason}\n\n"
            "A human needs to resolve the conflicts on this branch.",
        )
    except Exception as error:
        log_step(number, "rebase", f"failure notice incomplete: {error}")
    match = re.search(r"iss-(\d+)$", pr["headRefName"])
    if not match:
        return
    issue_number = int(match.group(1))
    try:
        swap_status(config, issue_number, LABEL_NEEDS_HUMAN)
    except Exception as error:
        log_step(issue_number, "rebase", f"needs-human relabel failed: {error}")
    slack_escalate(
        config,
        issue_number,
        f"PR #{number} has merge conflicts otto could not rebase away "
        f"({reason}); resolve them on the branch yourself: "
        f"{pr.get('url') or ''}",
    )


def rebase_pr(config: dict, pr: dict) -> None:
    try:
        run_rebase(config, pr)
    except OttoFailure as error:
        log_step(pr["number"], "rebase", f"failed: {error}")
        escalate_rebase(config, pr, str(error))
    except Exception as error:
        log_step(pr["number"], "rebase", f"transient, retries next cycle: {error}")


def dispatch_rebases(
    config: dict, pool: ThreadPoolExecutor, open_prs: list[dict]
) -> None:
    """Queue a rebase for every open PR that conflicts with its base.

    GitHub's mergeable state drives detection: CONFLICTING dispatches,
    UNKNOWN (still computing) waits for a later cycle. Rebases share
    REVISIONS_IN_FLIGHT with dispatch_revisions so a PR is never rebased
    and revised at the same time, and a PR whose issue is already
    `status:needs-human` is a human's problem until the conflict clears.
    """
    for pr in sorted(open_prs, key=lambda pr: pr["number"]):
        if pr.get("mergeable") != "CONFLICTING":
            continue
        number = pr["number"]
        with IN_FLIGHT_LOCK:
            if number in REVISIONS_IN_FLIGHT:
                continue
        match = re.search(r"iss-(\d+)$", pr["headRefName"])
        if match:
            try:
                labels = label_names(
                    gh_issue_view(config, int(match.group(1)), "labels")
                )
            except Exception as error:
                log_step(number, "rebase", f"label check failed: {error}")
                continue
            if LABEL_NEEDS_HUMAN in labels:
                continue
        log_step(number, "rebase", "merge conflicts detected")
        with IN_FLIGHT_LOCK:
            REVISIONS_IN_FLIGHT.add(number)
        pool.submit(
            run_guarded,
            number,
            REVISIONS_IN_FLIGHT,
            lambda pr=pr: rebase_pr(config, pr),
        )


def remove_stale_checkout(config: dict, number: int, branch: str) -> None:
    """Remove the worktree and branches a dead run left behind.

    Left in place, the worktree and local branch make `create_worktree`
    fail on the re-queued build, and a remote branch with the dead run's
    pushed commits rejects the fresh build's push as non-fast-forward.
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
    try:
        if _git(config, ["ls-remote", "--heads", "origin", branch]).strip():
            _git(config, ["push", "origin", "--delete", branch])
            log("orphan", number, "stale remote branch removed")
    except Exception as error:
        log("orphan", number, f"remote branch delete failed: {error}")


def orphan_pass(config: dict, open_prs: list[dict]) -> None:
    """Re-queue claimed issues whose runs died.

    Live builds are tracked in IMPLEMENTATION_IN_FLIGHT, so a
    `status:in-progress` issue outside that set with no open otto PR
    lost its run to a crash or reboot. The dead run's checkout and
    branches are discarded and the issue goes back to
    `status:spec-ready` for a fresh build; nothing about a died process
    needs a human decision.
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
        # The list and open_prs are snapshots; a build may have finished
        # (or been dispatched) since they were taken. Only live state is
        # safe to declare dead.
        with IN_FLIGHT_LOCK:
            if number in IMPLEMENTATION_IN_FLIGHT:
                continue
        live = label_names(gh_issue_view(config, number, "labels"))
        if LABEL_IN_PROGRESS not in live:
            continue
        if branch in {pr["headRefName"] for pr in list_otto_prs(config)}:
            continue
        try:
            swap_status(config, number, LABEL_SPEC_READY, current_names=live)
        except Exception as error:
            log("orphan", number, f"relabel failed: {error}")
            continue
        remove_stale_checkout(config, number, branch)
        log("orphan", number, "re-queued")


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


def run_cycle(config: dict, impl_pool: ThreadPoolExecutor) -> None:
    reclaim_pass(config)
    cancellation_pass(config)
    merged_pass(config)
    open_prs = list_otto_prs(config)
    orphan_pass(config, open_prs)
    cleanup_pass(config)
    dispatch_revisions(config, impl_pool, open_prs)
    dispatch_rebases(config, impl_pool, open_prs)
    dispatch_implementation(config, impl_pool, open_prs)


def main() -> None:
    config = slack.load_config()
    impl_pool = ThreadPoolExecutor(max_workers=config["max_implementation_agents"])
    labels_ensured = False
    ideation_started = False
    while True:
        try:
            if (Path(config["data_dir"]) / "PAUSED").exists():
                log("cycle", "-", "paused")
            else:
                if not labels_ensured:
                    ensure_status_labels(config)
                    labels_ensured = True
                if not ideation_started:
                    threading.Thread(
                        target=ideation_loop, args=(config,), daemon=True
                    ).start()
                    ideation_started = True
                run_cycle(config, impl_pool)
                log("cycle", "-", "complete")
        except Exception:
            log("cycle", "-", f"error: {traceback.format_exc(limit=3).strip()}")
        time.sleep(config["poll_seconds"])


if __name__ == "__main__":
    main()
