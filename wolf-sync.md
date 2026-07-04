# Wolf sync — one workspace on two machines

Wolf (the Mac mini) runs coding agents; the MacBook Air is where things get
tested (npm dev servers, Xcode, Chrome extensions via Load Unpacked). Mutagen
keeps `~/code` and `~/.worktrees` byte-identical on both machines —
**including uncommitted changes and git state** — so agent output on wolf is
runnable on the laptop within a second or two, with no push/pull dance.
Worktrunk hooks turn every worktree into a split tab: local shell on the
left for testing, a persistent wolf session on the right for the agent.

The MacBook Pro is the work computer and is **never** part of this.

## How it works

```
   wolf (Mac mini)                          MacBook Air
   agents edit code                         you test code
   ~/code, ~/.worktrees   ⇄  mutagen  ⇄    ~/code, ~/.worktrees
        (alpha)          two-way-resolved      (beta)
                     over SSH via Tailscale
```

- Two mutagen sessions (`code`, `worktrees`), created by `wolf-sync-setup`,
  running `--sync-mode=two-way-resolved --symlink-mode=posix-raw`.
- **Wolf is alpha**: if both machines write the same file in the same instant,
  the agent's version wins, deterministically, with no conflict-file litter.
- The mutagen daemon runs only on the Air (launchd agent `org.nixos.mutagen`,
  declared in the flake); it deploys its own agent binary to wolf over SSH.
  Wolf needs nothing installed.
- Both machines are `/Users/mikaelweiss`, which is what makes synced git
  worktrees work: a worktree's `.git` file points at the main repo's
  `.git/worktrees/<name>` by absolute path, and both ends live inside the
  synced trees. Corollary: **a worktree only works across machines if its
  main repo lives in `~/code`**.
- `.git` directories sync fully (that's the point — branch, index, stash are
  identical everywhere), except transient `index.lock` files.
- `.env` files sync deliberately: agents on wolf need the same secrets.

## The pieces

| Piece | Where | What it does |
|---|---|---|
| mutagen pkg + daemon | `nix-darwin/flake.nix` (`macbookAirConfig`) | Installs mutagen on the Air; launchd keeps the daemon alive. Logs: `/tmp/mutagen.log`, `/tmp/mutagen.err` |
| ignore defaults | `terminal/.mutagen.yml` → `~/.mutagen.yml` | What never syncs (see below). **Locked into sessions at creation** |
| `wolf-sync-setup` | `terminal/bin/` | Creates the two sessions. Idempotent. The reset-from-scratch command |
| `wolf-agent` | `terminal/bin/` | Runs **on wolf** (over SSH): waits for a just-created worktree to sync over, then attaches-or-creates its tmux keeper session |
| `wolf-bootstrap` | `terminal/bin/` | Installs node deps in the worktree when missing (lockfile-aware: pnpm/bun/yarn/npm), since node_modules doesn't sync |
| `worktree-cleanup` | `terminal/bin/` | After a worktree is gone: kills the wolf session, clears wolf's leftover dir, closes the local herdr tab / tmux window |
| `wolf` function | `terminal/.zshrc` | `wolf` from any dir = that dir's session on wolf; `wolf claude` runs claude in it |
| wt hooks | `terminal/.config/worktrunk/config.toml` | The workflow glue (below) |

### Worktrunk hooks

- **post-switch** is a two-step pipeline. Step 1 (pre-existing): open/focus
  the tmux window / herdr tab named after the branch. Step 2: if the tab has
  no wolf pane yet, split right and run
  `ssh -t wolf wolf-agent <worktree> <branch>` — a persistent shell on wolf in
  the same directory, deps installed. Guards: skips when running on wolf
  itself (dotfiles sync there too), and never re-splits an existing pane.
- **post-remove and post-merge** both run `worktree-cleanup`. It no-ops while
  the worktree still exists locally, which makes double-fires harmless and
  leaves everything open after `wt merge --no-remove`. The tab close is
  delayed one second and detached, because you usually run `wt merge` from
  inside the tab it is about to close.

The keeper sessions on wolf are plain tmux used purely as process keepers —
close the laptop and the agent keeps running; reattach and you're back. They
deliberately do **not** auto-start claude (start it yourself, or `wolf claude`).

## Decisions and why

- **Mutagen over Syncthing**: purpose-built for laptop↔dev-box code sync
  (it's what Sculptor embeds for the identical problem), sub-second
  propagation, and `two-way-resolved` gives deterministic wolf-wins conflicts
  instead of `.sync-conflict` litter. Syncthing would win if the mesh grew
  or versioning-as-undo mattered more than latency.
- **Over git round-trips** (what Claude Code web / Cursor cloud agents do):
  requires commits; the whole goal was uncommitted state flowing freely.
- **Over network mounts / remote editing**: FSEvents don't propagate over
  SMB (dev-server watchers silently break), Xcode over a mount is painful,
  and Chrome/Xcode need real local files anyway.
- **Artifacts don't sync** (`node_modules`, `dist`, `build`, `_build`,
  `deps`, `.build`, DerivedData…): huge churn for regenerable files.
  `wolf-bootstrap` reinstalls node deps on wolf when needed. The list came
  from github/gitignore templates; mutagen cannot read `.gitignore` files
  (long-open feature request), hence the curated list in `.mutagen.yml`.
- **Live app state doesn't sync**: stow links `~/.claude`, `~/.codex`, and
  `~/Library/Developer` into this repo, so agent session transcripts, Codex's
  SQLite/WAL files (sync would corrupt them), simulators, and DerivedData all
  sit inside `~/code`. They're excluded in both `.mutagen.yml` and
  `.gitignore`. Shared *config* (settings, skills, CLAUDE.md, Xcode themes)
  does sync — that's the dotfiles part.
- **Laptop was source of truth at cutover** (2026-07-03). Wolf's old
  `~/code`/`~/.worktrees` — including wolf-only repos flow-mvp1, meetily,
  odysseus, opsync-api, river-finance — are parked in
  `~/presync-backup-2026-07-03` on wolf, safe to delete.

## Daily commands

```sh
mutagen sync list                # health check — both sessions "Watching for changes"
mutagen sync list -l             # detail, incl. conflicts/problems
mutagen sync monitor code        # live view of one session
mutagen sync flush code worktrees   # force + wait for a sync cycle (before closing the lid)
mutagen sync pause code worktrees   # before filesystem-violent ops (filter-repo etc.)
mutagen sync resume code worktrees
mutagen sync reset code          # full rescan if a session looks wedged

wolf                             # this dir's session on wolf (plain shell)
wolf claude                      # same, running claude
ssh wolf 'tmux ls'               # list keeper sessions (non-interactive ssh skips herdr)
ssh wolf 'tmux kill-session -t "=name"'

wt hook show                     # every hook and when it fires
wt hook post-remove              # manually re-fire cleanup for an orphaned tab/session
```

**After editing `~/.mutagen.yml`**: ignores are locked in at creation, so

```sh
mutagen sync terminate code worktrees && wolf-sync-setup
```

## Gotchas (learned the hard way)

- **Never `ln -sf` toward a stowed path.** Stow dir-symlinks
  (`~/.config/worktrunk` on wolf → this repo) mean "live" paths and repo
  paths are the same file; careless `ln` created self-loop symlinks twice,
  and sync happily propagated the loop. Fix files at their repo path.
- **wolf's `/etc/zshrc` (nix) execs herdr** in any interactive shell with
  `SSH_CONNECTION` set. That's the wanted `ssh wolf` → herdr flow, but it
  would hijack keeper sessions — so `wolf-agent` creates them with
  `-e SSH_CONNECTION=`.
- **tmux 3.7**: `=name` works as a *session* target (`has-session`,
  `kill-session`) but fails as a *pane* target (`send-keys`,
  `capture-pane`) — use `=name:`.
- **zsh expands `=word`** in ssh remote commands (command-path expansion) —
  quote anything starting with `=`.
- **First sync of two populated dirs union-merges them** (newest file wins,
  per file) — Frankenstein working trees. When connecting a machine, empty
  one side first and let sync repopulate it.
- Ignored files never get deleted by sync — that's why `worktree-cleanup`
  rm's the wolf-side worktree dir (its node_modules would otherwise anchor a
  husk forever).

## Resetting a machine

1. Clone dotfiles, `stow .`, rebuild nix (installs mutagen + daemon on the Air).
2. Make sure the other machine's copy is the one to keep; empty this
   machine's `~/code`/`~/.worktrees` (or leave them absent).
3. `wolf-sync-setup` from the laptop. Done — sessions resume from `~/.mutagen`
   on their own after reboots; the launchd daemon keeps itself alive.
