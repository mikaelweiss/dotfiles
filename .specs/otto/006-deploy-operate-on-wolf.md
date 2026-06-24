# [006] Deploy & operate Otto on wolf

## Objective
Run otto.py 24/7 on the Mac Mini (wolf) as a launchd agent managed by nix-darwin, keep otto out of stow's symlink set, create the required GitHub labels, and document setup and operation.

## Context
- **wolf is the always-on Mac Mini**; its config is the `wolfConfig` module in `nix-darwin/flake.nix`. The existing `launchd.user.agents.remap-escape` at `nix-darwin/flake.nix:158-168` is the pattern to mirror.
- **The agent must be a user agent, not a daemon**, so it inherits the user's `gh` and `claude` authentication and can drive the simulator.
- **launchd starts processes with a minimal PATH**, so the agent sets PATH explicitly to include the npm-global bin (where `claude` lives — `wolfConfig` already puts `~/.npm-global/bin` on PATH at `nix-darwin/flake.nix:52`), Homebrew (`gh`, `git`), and the nix profile — the top cause of broken launchd jobs.
- **otto runs from its repo path** (like `nix-darwin`, already in `.stowrc`'s ignore list at `.stowrc`), not symlinked into `~`, because it is application code referenced by an absolute path, not a dotfile.
- **No secrets in the flake** (it is version-controlled): otto relies on the existing `gh auth` and `claude` logins on wolf.
- **The `status:` and `priority:` labels must exist in a repo before otto can query it**; a setup script creates them idempotently.
- The required tools are already provisioned in the shared `configuration` module: `gh`, `python`, `git`, `tmux`, `ffmpeg`, Xcode build tooling.

## Requirements
1. `wolfConfig` in `nix-darwin/flake.nix` gains a `launchd.user.agents.otto` whose `ProgramArguments` run an absolute Python interpreter against `/Users/mikaelweiss/code/dotfiles/otto/otto.py`, with `RunAtLoad` true, `KeepAlive` true, a non-zero `ThrottleInterval`, `StandardOutPath`/`StandardErrorPath` under the otto data dir, and `EnvironmentVariables.PATH` covering npm-global, Homebrew, and the nix profile — `KeepAlive` restarts only after a crash because the loop never exits on its own.
2. `.stowrc` ignores `otto` and `.specs` so neither is symlinked into `~` — otto runs from the repo path; specs are planning docs.
3. `otto/setup.sh` creates the required labels in a target repo idempotently — `status:spec-ready`, `status:in-progress`, `status:in-review`, `status:needs-human`, and `priority:1` through `priority:4` — via `gh label create`, ignoring "already exists" — labels are otto's state machine.
4. `otto/README.md` documents: preconditions (`gh auth` and `claude` logged in on wolf; dotfiles pulled and `stow claude` applied so the skills are present), installing/updating the agent (`darwin-rebuild switch --flake .#wolf`), watching (`tail -f` the log), restart/stop (`launchctl kickstart` / `bootout`), pause (the `PAUSED` sentinel), and babysit (stop the agent, run otto.py in tmux) — operability in one place.

## Files
- `nix-darwin/flake.nix` — Modify. Add `launchd.user.agents.otto` to `wolfConfig`.
- `.stowrc` — Modify. Add `otto` and `.specs` to the ignore list.
- `otto/setup.sh` — Create. Idempotent label creation for a target repo.
- `otto/README.md` — Create. Setup and operation documentation.

## Test expectations
- After `darwin-rebuild switch --flake .#wolf`, a `launchctl list` entry for the otto agent exists and the process is running.
- Killing the otto process → launchd restarts it after the throttle interval.
- `setup.sh` against a repo with none of the labels → creates all of them; a second run reports they exist and changes nothing.
- `stow` does not create an `~/otto` or `~/.specs` symlink.

## Boundaries
- Does NOT run as a root daemon — it is a user agent so it has the user's auth and simulator access.
- Does NOT place any secret or token in the flake or any committed file.
- Does NOT install `gh`, `claude`, Python, or Xcode — those are provisioned already.
- Does NOT symlink otto into `~`.
