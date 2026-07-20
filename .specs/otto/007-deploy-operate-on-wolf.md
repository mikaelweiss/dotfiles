# [007] Deploy & operate otto on wolf

## Objective
Run `otto.py` 24/7 on the Mac Mini (wolf) as a launchd agent managed by nix-darwin, keep otto and the specs out of stow's symlink set, create the required GitHub labels idempotently, and document setup and operation — including the one-time Slack app setup.

## Context
- **wolf's config is the `wolfConfig` module in `nix-darwin/flake.nix`**; the existing `launchd.user.agents.open-webui` block (`nix-darwin/flake.nix:101-122`) is the pattern to mirror — ProgramArguments, EnvironmentVariables, RunAtLoad, KeepAlive, log paths.
- **A user agent, not a daemon** — otto inherits the user's `gh` and `claude` logins and can drive the simulator; root has none of that.
- **launchd starts processes with a minimal PATH and never reads shell init** (wolf's PATH exports live in zsh init, `nix-darwin/flake.nix:126-137`, invisible to launchd) — the top cause of broken launchd jobs, so the agent sets PATH explicitly. Verified locations on wolf: `claude` → `/Users/mikaelweiss/.local/bin/claude` (a symlink into `~/.local/share/claude/versions/`, so auto-updates don't break the path); `gh`, `xcbeautify`, `tmux`, `python3` (3.11.15) → `/run/current-system/sw/bin`; `git`, `xcodebuild`, `xcrun` → `/usr/bin`.
- **otto runs from its repo path** (`/Users/mikaelweiss/code/dotfiles/otto`), not symlinked into `~` — it is application code referenced absolutely, not a dotfile. `.specs` is planning docs, equally not stowable.
- **No secrets in the flake or the repo** (both are version-controlled and synced): `gh` and `claude` are already logged in on wolf; the Slack bot token lives only in `~/.otto/slack_token`.
- **The labels must exist before otto can run against a repo** — they are its entire state machine. `AI Ready` already exists in MikaelWeiss/strive with color `4cb782`; creation is still included so the script fully provisions a fresh repo.
- KeepAlive restarts otto only after a crash — the loop never exits on its own — and ThrottleInterval stops a crash loop from spinning.

## Requirements
1. `wolfConfig` gains `launchd.user.agents.otto`: `ProgramArguments = [ "/run/current-system/sw/bin/python3" "/Users/mikaelweiss/code/dotfiles/otto/otto.py" ]`, `WorkingDirectory` the otto dir, `RunAtLoad = true`, `KeepAlive = true`, `ThrottleInterval = 30`, `StandardOutPath = "/Users/mikaelweiss/.otto/otto.log"`, `StandardErrorPath = "/Users/mikaelweiss/.otto/otto.err"`, and `EnvironmentVariables` with `HOME = "/Users/mikaelweiss"` and `PATH = "/Users/mikaelweiss/.local/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"`.
2. `.stowrc` gains `--ignore='otto'` and `--ignore='\.specs'` — neither belongs in `~`.
3. `otto/setup.sh` idempotently creates the labels in a target repo via `gh label create`, ignoring "already exists" errors: `AI Ready` (`4cb782`), `status:ideating`, `status:awaiting-answers`, `status:spec-ready`, `status:in-progress`, `status:in-review`, `status:needs-human`, and `priority:1` through `priority:4`. The repo is an argument so any project can be provisioned.
4. `otto/README.md` documents, in one place:
   - **Slack app setup:** create the app at api.slack.com/apps in the workspace, grant bot scopes `chat:write`, `im:write`, `im:history`, install to the workspace, write the bot token to `~/.otto/slack_token` with mode 600, and put the operator's Slack member ID in `config.toml`.
   - **Preconditions:** `gh auth login` and `claude` logged in on wolf, dotfiles pulled with `stow claude` applied (the skills must resolve), the target repo cloned at its `clone_path`, `setup.sh` run against it.
   - **Install/update:** `darwin-rebuild switch --flake .#wolf`; **watch:** `tail -f ~/.otto/otto.log`; **restart/stop:** `launchctl kickstart` / `launchctl bootout`; **pause/resume:** create or delete `~/.otto/PAUSED`; **babysit:** bootout, then run `otto.py` in tmux.
   - **Working with otto's output:** test a PR's branch from the laptop with `wt switch <branch>` (the worktree is already synced); recover a `status:needs-human` issue by fixing the cause and relabeling (`status:spec-ready` to re-queue, or clearing `status:*` labels to re-ideate); close a lingering laptop tab after otto removes a merged PR's worktree with `wt hook post-remove`.

## Files
- `nix-darwin/flake.nix` — Modify. Add `launchd.user.agents.otto` to `wolfConfig`.
- `.stowrc` — Modify. Add the `otto` and `.specs` ignores.
- `otto/setup.sh` — Create. Idempotent label creation for a target repo.
- `otto/README.md` — Create. Slack setup, preconditions, and operations.

## Test expectations
- After `darwin-rebuild switch --flake .#wolf`, `launchctl list` shows the otto agent and the process is running with the log file growing.
- Killing the otto process → launchd restarts it after the throttle interval.
- `setup.sh MikaelWeiss/strive` on a repo missing the labels → creates them all; a second run changes nothing and exits zero.
- `stow` from the repo root creates no `~/otto` or `~/.specs` symlink.
- A shell with launchd's default PATH can run `claude`, `gh`, `git`, `python3`, `xcodebuild`, and `xcbeautify` using the agent's PATH value.

## Boundaries
- Does NOT run as a root daemon — user auth and simulator access require the user session.
- Does NOT place any secret in the flake, the repo, or any synced file.
- Does NOT install `gh`, `claude`, Python, Xcode tooling, or `xcbeautify` — wolf already provisions them.
- Does NOT symlink otto or `.specs` into `~`.
- Does NOT create the Slack app — that is the documented manual step.
