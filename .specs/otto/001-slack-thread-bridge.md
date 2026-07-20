# [001] Slack thread bridge: one DM thread per issue

## Objective
A Python module (`otto/slack.py`) that gives each GitHub issue its own thread in a Slack DM between a bot and the operator: create the thread on first use, post follow-ups into it, and read the operator's replies — with the thread identity persisted on the GitHub issue itself.

## Context
- **GitHub stays the only durable state store.** Slack is a messaging surface; the thread mapping (`channel` + root `ts`) is written into the issue body as an invisible HTML comment, so any process on any machine can rediscover a thread from GitHub alone and restarts lose nothing.
- **Marker format:** `<!-- otto:slack-thread:<channel>:<ts> -->` appended to the issue body. HTML comments don't render on GitHub, so the operator's issue stays visually clean.
- **DM, not a channel:** `conversations.open` with the operator's Slack member ID returns the DM channel; `chat.postMessage` with `thread_ts` posts threaded replies; `conversations.replies` returns the full thread including the operator's replies (verified at docs.slack.dev/reference/methods/conversations.replies). Required bot scopes: `chat:write`, `im:write`, `im:history`.
- **Slack throttles non-Marketplace apps to ~1 request/minute on `conversations.replies`** (newer apps outside the Slack Marketplace; standard tier is 50+/min). The module therefore honors 429 back-off, and callers are expected to poll sparingly — the module never polls on its own schedule.
- **Stdlib only** (`urllib`, `json`, `tomllib`): the runtime is bare nix Python 3.11 under launchd with no venv, so a third-party dependency would add an install step and a failure mode. Python 3.11.15 at `/run/current-system/sw/bin/python3` on the Mac Mini has `tomllib` built in.
- **The bot token is never committed:** the dotfiles repo is stowed and synced across machines, so the token lives under the otto data dir (outside the repo and outside the mutagen-synced trees).
- Slack app creation (scopes above, workspace install, token issuance) is a one-time manual step in the Slack admin UI, documented in otto's operational README — this module assumes the token file exists.

## Requirements
1. `otto/config.toml` holds `repo` (owner/name), `data_dir`, and a `[slack]` table with `token_file` (absolute path) and `operator_member_id` — all Slack identity comes from config so the module is repo- and workspace-agnostic.
2. The module reads the bot token from `token_file` on each API call — a rotated token takes effect without a restart.
3. Ensuring a thread for issue N is idempotent: if the issue body contains the thread marker, that thread is reused; otherwise the module opens the DM via `conversations.open`, posts a root message containing the issue number, title, and URL, and appends the marker to the issue body via `gh issue edit --body` without altering any existing body text.
4. Posting to an issue's thread ensures the thread exists, then sends the text as a threaded reply (`chat.postMessage` with `thread_ts`).
5. Fetching an issue's thread returns every message with its author ID, timestamp, and text — enough for a caller to select operator replies newer than the module's own last post.
6. On an HTTP 429 the module waits the `Retry-After` duration and retries once; a second 429, any other Slack API error, or a missing/unreadable token file raises to the caller — issue-level failure policy belongs to the caller, not the transport.
7. The module uses only the Python standard library.
8. No message the module sends contains AI attribution — enforced by the module containing no attribution text in any template; message content is issue-derived plus caller-provided text.

## Files
- `otto/slack.py` — Create. DM/thread creation, marker persistence on the issue, threaded posting, thread fetching, rate-limit handling.
- `otto/config.toml` — Create. `repo = "MikaelWeiss/strive"`, `data_dir = "/Users/mikaelweiss/.otto"`, `[slack]` with `token_file = "/Users/mikaelweiss/.otto/slack_token"` and `operator_member_id` left as an obvious placeholder.

## Test expectations
- First post for an issue → a new DM root message appears, and the issue body gains the thread marker while its original text is unchanged.
- Second post for the same issue → lands as a threaded reply under the same root, no new marker.
- Operator replies in the thread → the fetch returns those messages with the operator's member ID and timestamps ordered after the root.
- Token file absent → a raised error naming the path; no Slack call attempted.
- An issue whose body was edited by the operator after the marker was added → the marker is still found and the thread reused.

## Boundaries
- Does NOT use webhooks, the Events API, or Socket Mode — the Mac Mini exposes no endpoint and otto's design is polling throughout.
- Does NOT post to channels — the DM with the operator is the only surface.
- Does NOT decide when or how often to poll — scheduling is the caller's concern.
- Does NOT create or configure the Slack app — that is a one-time manual setup.
- Does NOT store any state outside the GitHub issue body and the token file.
