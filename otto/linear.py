"""Linear status bridge: flips the Linear issue synced to a GitHub issue.

The GitHub Issues sync attaches the GitHub URL to its Linear counterpart,
so attachmentsForURL is the join. Stdlib only.
"""

import json
import urllib.request
from pathlib import Path

API_URL = "https://api.linear.app/graphql"


class LinearApiError(Exception):
    """A Linear API call failed (HTTP error or GraphQL errors)."""


def _read_token(config: dict) -> str:
    return Path(config["linear"]["token_file"]).read_text(encoding="utf-8").strip()


def _call(config: dict, query: str, variables: dict) -> dict:
    request = urllib.request.Request(
        API_URL,
        data=json.dumps({"query": query, "variables": variables}).encode("utf-8"),
        method="POST",
    )
    request.add_header("Content-Type", "application/json")
    request.add_header("Authorization", _read_token(config))
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("errors"):
        raise LinearApiError(str(payload["errors"])[:300])
    return payload["data"]


def set_state(github_url: str, target_name: str, config: dict) -> str:
    """Move the Linear issue attached to github_url into the named state.

    Prefers the team's state with that exact name; for "In Progress" a
    team without one falls back to its first started-type state. Returns
    a short outcome for the log.
    """
    data = _call(
        config,
        """query($url: String!) {
          attachmentsForURL(url: $url) {
            nodes { issue { id identifier state { name } team { id } } }
          }
        }""",
        {"url": github_url},
    )
    nodes = data["attachmentsForURL"]["nodes"]
    if not nodes:
        return "no-linked-issue"
    issue = nodes[0]["issue"]
    if issue["state"]["name"] == target_name:
        return f"{issue['identifier']} already {target_name}"
    states = _call(
        config,
        """query($teamId: ID!) {
          workflowStates(filter: { team: { id: { eq: $teamId } } }) {
            nodes { id name type position }
          }
        }""",
        {"teamId": issue["team"]["id"]},
    )["workflowStates"]["nodes"]
    matches = [state for state in states if state["name"] == target_name]
    if not matches and target_name == "In Progress":
        matches = sorted(
            (state for state in states if state["type"] == "started"),
            key=lambda state: state["position"],
        )
    if not matches:
        raise LinearApiError(f"team has no workflow state named {target_name}")
    _call(
        config,
        """mutation($id: String!, $stateId: String!) {
          issueUpdate(id: $id, input: { stateId: $stateId }) { success }
        }""",
        {"id": issue["id"], "stateId": matches[0]["id"]},
    )
    return f"{issue['identifier']} moved to {target_name}"
