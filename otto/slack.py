"""Slack DM thread bridge: one thread per GitHub issue.

The thread identity (DM channel + root message ts) is persisted on the GitHub
issue itself as an invisible HTML comment, so any process on any machine can
rediscover a thread from GitHub alone. Stdlib only.
"""

import json
import re
import subprocess
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SLACK_API_BASE = "https://slack.com/api/"
MARKER_TEMPLATE = "<!-- otto:slack-thread:{channel}:{ts} -->"
MARKER_RE = re.compile(r"<!-- otto:slack-thread:([A-Z0-9]+):(\d+\.\d+) -->")


class SlackApiError(Exception):
    """A Slack API call failed (non-ok response or exhausted 429 retry)."""


def load_config() -> dict:
    with open(Path(__file__).with_name("config.toml"), "rb") as f:
        return tomllib.load(f)


def find_thread_marker(body: str) -> tuple[str, str] | None:
    """Return (channel, ts) from the thread marker in an issue body, if present."""
    match = MARKER_RE.search(body or "")
    return (match.group(1), match.group(2)) if match else None


def _root_text(
    config: dict, issue_number: int, title: str, url: str, emoji: str = ""
) -> str:
    prefix = f"{emoji} " if emoji else ""
    branch = f"{config['branch_prefix']}iss-{issue_number}"
    return f"{prefix}Issue #{issue_number}: {title}\n{url}\n`wt switch {branch}`"


def ensure_thread(issue_number: int, config: dict | None = None) -> tuple[str, str]:
    """Return (channel, root_ts) for the issue's DM thread, creating it if needed.

    Idempotent: an existing marker on the issue wins. Otherwise a DM is opened
    with the operator, a root message is posted, and the marker is appended to
    the issue body.
    """
    config = config or load_config()
    issue = _gh_issue_view(config, issue_number)
    existing = find_thread_marker(issue["body"])
    if existing:
        return existing

    opened = _slack_call(
        config,
        "conversations.open",
        {"users": config["slack"]["operator_member_id"]},
    )
    channel = opened["channel"]["id"]
    root_text = _root_text(config, issue_number, issue["title"], issue["url"])
    posted = _slack_call(
        config, "chat.postMessage", {"channel": channel, "text": root_text}
    )
    ts = posted["ts"]

    marker = MARKER_TEMPLATE.format(channel=channel, ts=ts)
    body = issue["body"]
    new_body = f"{body}\n\n{marker}" if body else marker
    _gh_issue_edit_body(config, issue_number, new_body)
    return channel, ts


def set_root_status(issue_number: int, emoji: str, config: dict | None = None) -> None:
    """Rewrite the issue's thread root to lead with `emoji`; no-op without a thread.

    The root text is rebuilt from the issue's current title and url, so an
    edited title also refreshes here.
    """
    config = config or load_config()
    issue = _gh_issue_view(config, issue_number)
    thread = find_thread_marker(issue["body"])
    if not thread:
        return
    channel, ts = thread
    root_text = _root_text(config, issue_number, issue["title"], issue["url"], emoji)
    _slack_call(
        config, "chat.update", {"channel": channel, "ts": ts, "text": root_text}
    )


def add_reaction(
    issue_number: int, message_ts: str, name: str, config: dict | None = None
) -> None:
    """React to a message in the issue's thread; a repeat reaction is a no-op."""
    config = config or load_config()
    channel, _ = ensure_thread(issue_number, config)
    try:
        _slack_call(
            config,
            "reactions.add",
            {"channel": channel, "timestamp": message_ts, "name": name},
        )
    except SlackApiError as error:
        if "already_reacted" not in str(error):
            raise


def post_to_thread(issue_number: int, text: str, config: dict | None = None) -> str:
    """Post text as a threaded reply in the issue's thread; return the reply ts."""
    config = config or load_config()
    channel, root_ts = ensure_thread(issue_number, config)
    posted = _slack_call(
        config,
        "chat.postMessage",
        {"channel": channel, "text": text, "thread_ts": root_ts},
    )
    return posted["ts"]


def fetch_thread(issue_number: int, config: dict | None = None) -> list[dict]:
    """Return every message in the issue's thread, oldest first.

    Each message is {"user": author member ID, "ts": timestamp, "text": text},
    enough for a caller to select operator replies newer than the module's own
    last post.
    """
    config = config or load_config()
    channel, root_ts = ensure_thread(issue_number, config)
    messages = []
    cursor = None
    while True:
        params = {"channel": channel, "ts": root_ts, "limit": 200}
        if cursor:
            params["cursor"] = cursor
        payload = _slack_call(config, "conversations.replies", params, http_get=True)
        for message in payload.get("messages", []):
            messages.append(
                {
                    "user": message.get("user", ""),
                    "ts": message["ts"],
                    "text": message.get("text", ""),
                }
            )
        cursor = payload.get("response_metadata", {}).get("next_cursor")
        if not cursor:
            break
    return messages


def _read_token(config: dict) -> str:
    return Path(config["slack"]["token_file"]).read_text(encoding="utf-8").strip()


def _slack_call(
    config: dict, method: str, params: dict, *, http_get: bool = False
) -> dict:
    """Call a Slack Web API method and return its payload.

    The token is read from token_file on every call so a rotated token takes
    effect without a restart. On HTTP 429, waits Retry-After and retries once.
    """
    token = _read_token(config)
    url = SLACK_API_BASE + method
    if http_get:
        query = urllib.parse.urlencode(params)
        request = urllib.request.Request(f"{url}?{query}", method="GET")
    else:
        request = urllib.request.Request(
            url, data=json.dumps(params).encode("utf-8"), method="POST"
        )
        request.add_header("Content-Type", "application/json; charset=utf-8")
    request.add_header("Authorization", f"Bearer {token}")

    retried = False
    while True:
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as error:
            if error.code == 429 and not retried:
                retried = True
                time.sleep(float(error.headers.get("Retry-After", "60")))
                continue
            raise SlackApiError(f"{method} failed with HTTP {error.code}") from error

    if not payload.get("ok"):
        raise SlackApiError(f"{method} failed: {payload.get('error', 'unknown')}")
    return payload


def _gh_issue_view(config: dict, issue_number: int) -> dict:
    result = subprocess.run(
        [
            "gh",
            "issue",
            "view",
            str(issue_number),
            "--repo",
            config["repo"],
            "--json",
            "title,body,url",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def _gh_issue_edit_body(config: dict, issue_number: int, body: str) -> None:
    subprocess.run(
        [
            "gh",
            "issue",
            "edit",
            str(issue_number),
            "--repo",
            config["repo"],
            "--body-file",
            "-",
        ],
        input=body,
        check=True,
        capture_output=True,
        text=True,
    )
