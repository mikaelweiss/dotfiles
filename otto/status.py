#!/usr/bin/env python3
"""Compact terminal dashboard for otto.

Usage: status.py [--watch [seconds]]
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# The macOS system python is 3.9, but slack.py needs tomllib (3.11+);
# re-exec into the first interpreter that has it: nix on wolf, homebrew
# or a versioned install on the laptop.
if sys.version_info < (3, 11):
    for candidate in (
        "/run/current-system/sw/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "python3.13",
        "python3.12",
        "python3.11",
    ):
        found = shutil.which(candidate)
        if not found:
            continue
        check = subprocess.run([found, "-c", "import tomllib"], capture_output=True)
        if check.returncode == 0:
            os.execv(found, [found, *sys.argv])
    sys.exit("status.py needs Python 3.11+; none found on this machine")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slack

STATUS_ORDER = [
    ("ideate queue", None),
    ("ideating", "status:ideating"),
    ("awaiting you", "status:awaiting-answers"),
    ("spec queue", "status:spec-ready"),
    ("building", "status:in-progress"),
    ("in review", "status:in-review"),
    ("NEEDS HUMAN", "status:needs-human"),
]

TTY = sys.stdout.isatty()


def color(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if TTY else text


def sh(args: list[str], timeout: int = 60) -> str:
    try:
        return subprocess.run(
            args, capture_output=True, text=True, timeout=timeout
        ).stdout
    except Exception:
        return ""


def age(stamp: str) -> str:
    try:
        then = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        seconds = (datetime.now(timezone.utc) - then).total_seconds()
    except ValueError:
        return "?"
    if seconds < 90:
        return f"{int(seconds)}s"
    if seconds < 5400:
        return f"{int(seconds / 60)}m"
    return f"{seconds / 3600:.1f}h"


def daemon_line(config: dict) -> str:
    pid = sh(["pgrep", "-f", "otto.py"]).split()
    pid = pid[0] if pid else ""
    if not pid:
        return color("1;31", "otto: NOT RUNNING")
    uptime = sh(["ps", "-o", "etime=", "-p", pid]).strip()
    paused = (Path(config["data_dir"]) / "PAUSED").exists()
    workers = []
    helpers = 0
    for line in sh(["ps", "-axo", "ppid=,etime=,command="]).splitlines():
        if "claude -p --output-format" not in line:
            continue
        parent, elapsed = line.split()[:2]
        if parent == pid:
            workers.append(elapsed)
        else:
            helpers += 1
    if paused and workers:
        state = color("1;33", "PAUSE PENDING (finishing in-flight work)")
    elif paused:
        state = color("1;33", "PAUSED")
    else:
        state = color("1;32", "running")
    sessions = f"{len(workers)} worker(s)" + (
        f" [{' '.join(workers)}]" if workers else ""
    )
    if helpers:
        sessions += f" +{helpers} helper(s)"
    return f"otto {state}  pid {pid}  up {uptime}  {sessions}"


def issues_by_status(config: dict) -> dict[str, list[dict]]:
    out = sh(
        [
            "gh", "issue", "list", "--repo", config["repo"],
            "--label", "AI Ready", "--state", "open",
            "--json", "number,title,labels", "--limit", "200",
        ]
    )
    grouped: dict[str, list[dict]] = {label: [] for _, label in STATUS_ORDER}
    for issue in json.loads(out or "[]"):
        names = {label["name"] for label in issue["labels"]}
        status = next((n for n in names if n.startswith("status:")), None)
        grouped.setdefault(status, []).append(issue)
    for issues in grouped.values():
        issues.sort(key=lambda issue: issue["number"])
    return grouped


def otto_prs(config: dict) -> list[dict]:
    out = sh(
        [
            "gh", "pr", "list", "--repo", config["repo"], "--state", "open",
            "--json", "number,title,headRefName,url,createdAt", "--limit", "50",
        ]
    )
    return [
        pr
        for pr in json.loads(out or "[]")
        if pr["headRefName"].startswith(config["branch_prefix"])
    ]


def revising(config: dict) -> dict[int, str]:
    """PR numbers otto is mid-revision on, mapped to how long ago it began.

    A revision logs 'N feedback items' when it picks feedback up and a
    terminal line (pushed/no-changes/replied/...) when it finishes, so a
    PR whose latest revise line is still the dispatch is being worked.
    """
    path = Path(config["data_dir"]) / "otto.log"
    if not path.exists():
        return {}
    latest: dict[int, tuple[str, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines()[-300:]:
        match = re.match(r"(\S+) issue=(\d+) step=revise .*?outcome=(.*)", line)
        if match:
            stamp, number, outcome = match.groups()
            latest[int(number)] = (stamp, outcome)
    return {
        number: age(stamp)
        for number, (stamp, outcome) in latest.items()
        if "feedback items" in outcome
    }


def pr_issue_number(pr: dict) -> int | None:
    match = re.search(r"iss-(\d+)$", pr["headRefName"])
    return int(match.group(1)) if match else None


def last_activity(config: dict) -> dict[int, tuple[str, int, str]]:
    """Latest log line per issue, as (stamp, issue, 'step outcome (age)')."""
    path = Path(config["data_dir"]) / "otto.log"
    if not path.exists():
        return {}
    activity: dict[int, tuple[str, int, str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines()[-300:]:
        match = re.match(r"(\S+) (?:pass=(\S+) issue=(\d+)|issue=(\d+) step=(\S+).*?)"
                         r" .*?outcome=(.*)", line)
        if not match:
            continue
        stamp, pass_name, n1, n2, step, outcome = match.groups()
        number = int(n1 or n2)
        stage = step or pass_name
        activity[number] = (stamp, number, f"{stage}: {outcome[:40]} ({age(stamp)} ago)")
    return activity


def sub_numbers(config: dict, number: int) -> list[int]:
    out = sh(
        ["gh", "issue", "view", str(number), "--repo", config["repo"],
         "--json", "subIssues"]
    )
    try:
        nodes = (json.loads(out).get("subIssues") or {}).get("nodes") or []
    except json.JSONDecodeError:
        return []
    return [node["number"] for node in nodes]


def title_of(issue: dict, width: int = 46) -> str:
    title = issue["title"].strip()
    return title if len(title) <= width else title[: width - 1] + "…"


def render(config: dict) -> str:
    grouped = issues_by_status(config)
    prs = otto_prs(config)
    activity = last_activity(config)
    active = revising(config)
    pr_by_issue = {
        issue: pr for pr in prs if (issue := pr_issue_number(pr)) is not None
    }
    lines = [daemon_line(config)]
    if activity:
        _, source, text = max(activity.values())
        lines.append(color("1;36", f"latest: #{source} {text}"))
    lines.append("")

    waiting = grouped.get("status:awaiting-answers", [])
    if waiting or prs:
        lines.append(color("1;33", "WAITING ON YOU"))
        for issue in waiting:
            lines.append(
                f"  #{issue['number']:<4} {title_of(issue)}  "
                + color("33", "answer in Slack")
            )
        for pr in prs:
            if pr["number"] in active:
                tag = color(
                    "1;35", f"↻ responding to feedback ({active[pr['number']]} ago)"
                )
            else:
                tag = color("33", f"review ({age(pr['createdAt'])} old)")
            lines.append(f"  PR #{pr['number']:<3} {pr['title'][:46]}  " + tag)
        lines.append("")

    lines.append(color("1", "PIPELINE"))
    for name, label in STATUS_ORDER:
        issues = grouped.get(label, [])
        if name == "awaiting you":
            continue
        if not issues:
            continue
        style = "1;31" if label == "status:needs-human" else "0"
        lines.append(color(style, f"  {name}"))
        for issue in issues:
            numbers = [issue["number"]]
            if label == "status:in-progress":
                numbers += sub_numbers(config, issue["number"])
            pr = pr_by_issue.get(issue["number"]) if label == "status:in-review" else None
            if pr:
                numbers.append(pr["number"])
            latest = max(
                (activity[n] for n in numbers if n in activity), default=None
            )
            extra = ""
            if latest:
                _, source, text = latest
                extra = text if source == issue["number"] else f"#{source} {text}"
            if pr and pr["number"] in active:
                tag = color(
                    "1;35", f"  ↻ responding to feedback ({active[pr['number']]} ago)"
                )
            elif extra:
                tag = color("90", f"  {extra}")
            else:
                tag = ""
            lines.append(f"    #{issue['number']:<4} {title_of(issue)}" + tag)
    lines.append("")

    lines.append(
        color("1", f"OPEN OTTO PRS ({len(prs)}/{config['max_open_prs']})")
        + ("" if prs else "  none")
    )
    for pr in prs:
        lines.append(f"  #{pr['number']} {pr['title'][:56]}  {pr['url']}")
    lines.append("")

    log_path = Path(config["data_dir"]) / "otto.log"
    if log_path.exists():
        lines.append(color("1", "LOG"))
        for line in log_path.read_text(encoding="utf-8").splitlines()[-6:]:
            lines.append(color("90", "  " + line[11:19] + line[24:]))
    return "\n".join(lines)


def main() -> None:
    config = slack.load_config()
    if "--watch" in sys.argv:
        index = sys.argv.index("--watch")
        interval = (
            int(sys.argv[index + 1])
            if len(sys.argv) > index + 1 and sys.argv[index + 1].isdigit()
            else 30
        )
        while True:
            frame = render(config)
            print("\033[2J\033[H" + frame, flush=True)
            time.sleep(interval)
    else:
        print(render(config))


if __name__ == "__main__":
    main()
