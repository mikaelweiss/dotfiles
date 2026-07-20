# Otto

Label-driven GitHub automation loop. Otto watches a repo for issues labeled
`AI Ready`, ideates them into specs, implements the specs in worktrees, and
opens PRs for human review. The loop is a pure orchestrator that only
dispatches workers: ideation and Slack replies run on a scheduler thread
with up to `max_ideation_agents` concurrent sessions, and implementations
plus PR revisions run on a worker pool sized by `max_implementation_agents`
(raise it to build several at once; the pre-PR verify gate still serializes
on the shared simulator). Nothing blocks anything else. Labels are the whole
state machine; GitHub is the only durable store. It runs 24/7 on wolf as a launchd user agent
(`org.nixos.otto`, defined in `nix-darwin/flake.nix`) so it inherits the
user's `gh` and `claude` logins and can drive the simulator.

## Slack app setup (one time)

Otto relays ideation questions and status updates through Slack DMs.

1. Create an app at [api.slack.com/apps](https://api.slack.com/apps) ("From
   scratch") in the workspace.
2. Under **OAuth & Permissions → Scopes → Bot Token Scopes**, add
   `chat:write`, `im:write`, and `im:history`.
3. **Install to Workspace** and copy the Bot User OAuth Token (`xoxb-...`).
4. On wolf, write the token to `~/.otto/slack_token` with mode 600:

   ```sh
   mkdir -p ~/.otto
   printf '%s\n' 'xoxb-...' > ~/.otto/slack_token
   chmod 600 ~/.otto/slack_token
   ```

5. Put the operator's Slack member ID (Slack profile → **⋮ → Copy member
   ID**) in `config.toml` as `operator_member_id` under `[slack]`.

The token lives only in `~/.otto/slack_token`: never in the repo, the
flake, or any synced file.

## Linear setup (one time)

Otto drives the synced Linear issue through Linear's API: In Progress
when it claims the issue for implementation, In Review when the PR
opens. Done needs no call; merging the PR closes the GitHub issue and
the GitHub Issues sync closes the Linear side. (The sync alone cannot
do the first two: it only reacts to a linked PR, which otto's branch
naming never triggers, and only when the PR opens, which is too late.)

1. In Linear: **Settings -> Security & access -> Personal API keys**,
   create a key.
2. On wolf, write it to `~/.otto/linear_token` with mode 600:

   ```sh
   printf '%s\n' 'lin_api_...' > ~/.otto/linear_token
   chmod 600 ~/.otto/linear_token
   ```

Until the token file exists, otto logs `linear ... skipped` and carries on;
a Linear outage or unlinked issue never blocks a run.

## Preconditions

On wolf, before the agent can do anything useful:

- `gh auth login` completed and `claude` logged in.
- Dotfiles pulled to `~/code/dotfiles` with `stow claude` applied; the
  ideate/implement/review skills must resolve from `~/.claude`.
- The target repo cloned at its `clone_path` from `config.toml`
  (`/Users/mikaelweiss/code/strive` for strive).
- Labels provisioned in the target repo:

  ```sh
  ./setup.sh MikaelWeiss/strive
  ```

  Idempotent: existing labels are left untouched, so it can be re-run on
  any repo at any time.

## Operations

| Action | Command |
| --- | --- |
| Install / update | `sudo darwin-rebuild switch --flake ~/code/dotfiles/nix-darwin#wolf` |
| Dashboard | `~/code/dotfiles/otto/status.py` (live: `status.py --watch [sec]`) |
| Watch | `tail -f ~/.otto/otto.log` (errors: `~/.otto/otto.err`) |
| Restart | `launchctl kickstart -k gui/$(id -u)/org.nixos.otto` |
| Stop | `launchctl bootout gui/$(id -u)/org.nixos.otto` |
| Pause the loop | `touch ~/.otto/PAUSED` |
| Resume | `rm ~/.otto/PAUSED` |

Pausing halts dispatch (orchestrator and ideation scheduler) without
killing the process; workers already running finish normally. launchd's
`KeepAlive` only restarts otto after a crash, with a 30s throttle so a
crash loop can't spin.

**Safe restart** (config or code changes): killing otto mid-build orphans
the build and routes its issue to needs-human, so drain first. A worker
is running whenever a headless claude session OR a verify step (xcodebuild
or simctl, which run without any claude process) is alive:

```sh
touch ~/.otto/PAUSED
while pgrep -f "claude -p --output-format" > /dev/null \
   || pgrep -x xcodebuild > /dev/null || pgrep -x simctl > /dev/null \
   || ! tail -1 ~/.otto/otto.log | grep -q "outcome=paused"; do sleep 15; done
launchctl kickstart -k gui/$(id -u)/org.nixos.otto
rm ~/.otto/PAUSED
```

**Babysit** (run otto interactively to watch a session live): stop the
agent, then run it in tmux:

```sh
launchctl bootout gui/$(id -u)/org.nixos.otto
tmux new -s otto '/run/current-system/sw/bin/python3 ~/code/dotfiles/otto/otto.py'
```

`darwin-rebuild switch` re-bootstraps the agent when you're done.

## Working with otto's output

- **PR review feedback:** otto acts on feedback from anyone, the operator,
  Copilot, or any other reviewer. It replies to every inline comment
  thread with what it changed (or why nothing needed to change) and then
  resolves the conversation. To push back on a reply, unresolve the
  thread or leave a new comment elsewhere on the PR; comments added to a
  thread that stays resolved are treated as settled and ignored, as is
  anything posted by an author in `ignored_feedback_authors` (CI status
  bots like `github-actions`).
- **Test a PR's branch from the laptop:** `wt switch <branch>`. The
  worktree under `~/.worktrees/strive` is already synced to the laptop, so
  the branch is ready to build and run locally.
- **Recover a `status:needs-human` issue:** fix the underlying cause (the
  issue comment says what failed), then relabel: `status:spec-ready` to
  re-queue implementation, or clear all `status:*` labels to re-ideate from
  scratch.
- **Lingering laptop tab after a merge:** otto removes a merged PR's
  worktree on wolf; on the laptop, run `wt hook post-remove` to close out
  the now-gone worktree's tab.
