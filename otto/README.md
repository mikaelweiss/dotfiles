# Otto

Label-driven GitHub automation loop. Otto watches a repo for issues labeled
`AI Ready`, ideates them into specs, implements the specs in worktrees, and
opens PRs for human review. Labels are the whole state machine; GitHub is the
only durable store. It runs 24/7 on wolf as a launchd user agent
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
| Watch | `tail -f ~/.otto/otto.log` (errors: `~/.otto/otto.err`) |
| Restart | `launchctl kickstart -k gui/$(id -u)/org.nixos.otto` |
| Stop | `launchctl bootout gui/$(id -u)/org.nixos.otto` |
| Pause the loop | `touch ~/.otto/PAUSED` |
| Resume | `rm ~/.otto/PAUSED` |

Pausing halts the loop at the top of the next cycle without killing the
process; launchd's `KeepAlive` only restarts otto after a crash, with a 30s
throttle so a crash loop can't spin.

**Babysit** (run otto interactively to watch a session live): stop the
agent, then run it in tmux:

```sh
launchctl bootout gui/$(id -u)/org.nixos.otto
tmux new -s otto '/run/current-system/sw/bin/python3 ~/code/dotfiles/otto/otto.py'
```

`darwin-rebuild switch` re-bootstraps the agent when you're done.

## Working with otto's output

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
