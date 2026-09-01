# Workspace sync

Topology since 2026-08-31: **elm** (NixOS, always on, home at
`/Users/mikaelweiss`) is the hub and the alpha side of every session. Each Mac
runs its own mutagen daemon (declared in `nix-darwin/flake.nix`) with sessions
to elm, created by `sync-setup`:

| Machine | Sessions |
|---|---|
| MacBook Air, wolf | `code` (`~/code`), `worktrees` (`~/.worktrees`) |
| MacBook Pro (work) | `surestake` (`~/code/surestake`), `surestake-worktrees` (`~/.worktrees/surestake`), `penguin` (`~/code/penguin`), `penguin-worktrees` (`~/.worktrees/penguin`), `dotfiles` (`~/code/dotfiles`) |
| every machine | `penguin-home` (`~/.penguin`), `penguin-state` (`~/.local/state/penguin`) |

Penguin keeps its worktrees in `~/.penguin/worktrees/<repo>/<branch>` and its
run history in `~/.local/state/penguin/runs`, both outside `~/code`, so they
get their own sessions and a run started anywhere continues anywhere. The auth
tokens under `~/.local/state/penguin/auth` sync with them, on the same footing
as `.env` files.

Elm needs nothing but sshd; it never initiates. A machine's ssh key must be in
`nixos/common.nix` (`openssh.authorizedKeys.keys`) before `sync-setup` works.
Claude Code transcripts (`~/.claude/projects`, stow-linked into
`dotfiles/claude/.claude`) sync too, so `claude --resume` and `ccusage` see
every machine. One session file is written by one machine at a time; if two
machines resume the same session at once, elm's copy wins.

The sections below predate the move and describe the wolf agent workflow,
which still applies with wolf as a spoke.


Wolf (the Mac mini) runs coding agents; the MacBook Air is where things get
tested (npm dev servers, Xcode, Chrome extensions via Load Unpacked). Mutagen
keeps `~/code` and `~/.worktrees` byte-identical on both machines —
**including uncommitted changes and git state** — so agent output on wolf is
runnable on the laptop within a second or two, with no push/pull dance.
Worktrunk hooks turn every worktree into a split tab: local shell on the
left for testing, a persistent wolf session on the right for the agent.

The MacBook Pro is the work computer and syncs only the surestake and penguin trees and dotfiles.

## How it works

```
   wolf (Mac mini)                          MacBook Air
   agents edit code                         you test code
   ~/code, ~/.worktrees   ⇄  mutagen  ⇄    ~/code, ~/.worktrees
        (alpha)          two-way-resolved      (beta)
                     over SSH via Tailscale
```

- Two mutagen sessions (`code`, `worktrees`), created by `sync-setup`,
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
| ignore defaults | `terminal/.mutagen.yml` → `~/.mutagen.yml` | Bare artifact names that match at any depth (see below). **Locked into sessions at creation** |
| `sync-lib.zsh` | `terminal/bin/` | Shared by the two below: the session list, the ignore derivation, and the keep-list |
| `sync-setup` | `terminal/bin/` | Creates the sessions. Derives per-repo ignores from `git status --ignored` and re-anchors the `.mutagen.yml` dotfiles paths. Idempotent. The reset-from-scratch command |
| `sync-check` | `terminal/bin/` | Lists sessions whose frozen ignore list no longer matches what git ignores today. Exits non-zero on drift |
| `wolf-attach` | `terminal/bin/` | Runs **on the laptop**: wraps the ssh to wolf-agent in a reconnect loop. Connection drops (ssh exit 255, e.g. lid close) retry every 2s; a clean exit — tmux detach, session killed — ends the pane |
| `wolf-agent` | `terminal/bin/` | Runs **on wolf** (over SSH): waits for a just-created worktree to sync over, then attaches-or-creates its tmux keeper session |
| `wolf-bootstrap` | `terminal/bin/` | Installs node deps in the worktree when missing (lockfile-aware: pnpm/bun/yarn/npm), since node_modules doesn't sync |
| `worktree-cleanup` | `terminal/bin/` | After a worktree is gone: kills the wolf session and clears wolf's leftover dir (Air only), closes the local herdr tab / tmux window (everywhere) |
| `wolf` function | `terminal/.zshrc` | `wolf` from any dir = that dir's session on wolf; `wolf claude` runs claude in it |
| `wolf-split` | `terminal/bin/` | Splits the current herdr/tmux pane and attaches this worktree's wolf session in it — re-opens a closed wolf pane, or gives any dir one on demand |
| `wolf-image` | `terminal/bin/` | Runs **on the laptop**: writes the clipboard image into `~/code/.image-drop`, flushes the `code` sync so it lands on wolf at the identical path, then `send-keys` types that path into this worktree's wolf claude pane. Sidesteps the fact that ctrl+v / drag-drop read wolf's (empty) pasteboard over SSH; the file-path method is the one that survives. `pngpaste` if present, else osascript (PNGf, then TIFF→sips) |
| wt hooks | `terminal/.config/worktrunk/config.toml` | The workflow glue (below) |

### Worktrunk hooks

- **post-switch** is a two-step pipeline. Step 1 (pre-existing): open/focus
  the tmux window / herdr tab named after the branch. Step 2: if the tab has
  no wolf pane yet, split right and run
  `wolf-attach <worktree> <branch>` — a persistent shell on wolf in
  the same directory, deps installed, reconnecting on its own whenever the
  link drops. Guards: runs **only on the Air** (wolf and the MacBook Pro
  share these dotfiles but never open wolf panes), never re-splits an
  existing pane, and
  **skips the primary worktree entirely** — the `main` tab is a local-only
  launchpad for creating the next worktree; agents work in feature
  worktrees, so only those get wolf panes/sessions.
- **post-remove and post-merge** both run `worktree-cleanup`. `wt merge`
  fires post-merge *before* its backgrounded removal deletes the worktree,
  so when the dir still exists the script re-launches itself detached and
  waits (up to 30s) for it to vanish; if it never does, that was
  `merge --no-remove` and everything stays open. The tab close is delayed
  and detached, because you usually run `wt merge` from inside the tab it
  is about to close.

Keeper sessions are named after the branch, matching the tab name. The
cleanup hooks carry the same primary-worktree guard, so nothing ever
touches a wolf session named `main`. Like the wolf panes, the wolf side of
cleanup is Air-only — on the MacBook Pro, `wt remove`/`wt merge` just close
the local tab.

The keeper sessions on wolf are plain tmux used purely as process keepers —
close the laptop and the agent keeps running; on wake, wolf-attach notices
the dead link within ~10s (keepalives) and reattaches the pane by itself.
They deliberately do **not** auto-start claude (start it yourself, or
`wolf claude`).

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
- **Only git-included files sync.** Mutagen cannot read `.gitignore` (a
  long-open feature request), so ignores come in two layers. `sync-setup`
  runs `git status --ignored` in every repo under a session root and passes
  each answer as an anchored `--ignore`, which matches that repo's
  `.gitignore` exactly. `.mutagen.yml` then adds bare names
  (`node_modules`, `target`, `.nx`, DerivedData…) taken from the
  github/gitignore templates. The derived layer is accurate but freezes at
  session creation; the bare names keep matching directories made later, at
  any depth, without a rebuild. `wolf-bootstrap` reinstalls node deps on
  wolf when needed.
- **`.git/wt/trash` doesn't sync.** `wt remove` moves the whole worktree
  there instead of deleting it. Git never reports paths inside `.git`, so
  `sync-setup` adds it by hand. It is a local undo buffer and no other
  machine reads it.
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

sync-check                       # which sessions drifted from what git ignores now

wolf                             # this dir's session on wolf (plain shell)
wolf claude                      # same, running claude
wolf-split                       # same, but in a new split next to this pane
wolf-image                       # clipboard image -> synced path -> typed into this dir's wolf claude
ssh wolf 'tmux ls'               # list keeper sessions (non-interactive ssh skips herdr)
ssh wolf 'tmux kill-session -t "=name"'

wt hook show                     # every hook and when it fires
wt hook post-remove              # manually re-fire cleanup for an orphaned tab/session
```

**After editing `~/.mutagen.yml` or any synced repo's `.gitignore`**: ignores
are locked in at creation, so

```sh
mutagen sync terminate code worktrees && sync-setup
```

Exceptions that sync despite being git-ignored live in `sync-setup`'s `keep`
pattern: Claude transcripts and the Claude and Codex plugin dirs, so
`claude --resume` and `ccusage` see every machine.

## Gotchas (learned the hard way)

- **Any ignore pattern containing a slash anchors to the session root**, with
  or without a leading `/`. Only single-segment names like `node_modules`
  match at every depth. So `~/.mutagen.yml`'s `/dotfiles/xcode/...` paths,
  written for the `~/code` root the Air and wolf sync, match nothing in the
  Pro's `dotfiles` session, whose root is `~/code/dotfiles` itself.
  `sync-setup` re-anchors them with `--ignore` flags, which append to the
  yml defaults rather than replacing them. Symptom when this is wrong: the
  session sits in "Staging files on alpha" for hours and no edit propagates,
  with `mutagen sync list` showing beta many times larger than alpha.
- **A stale herdr server silently kills the post-switch tab.** The CLI
  refuses to talk to an older server (`protocol_mismatch`), writes that JSON
  to stderr, and still exits 0, so `wt switch` opened no tab and said
  nothing. Restart herdr after it updates:
  `HERDR_SOCKET_PATH=~/.config/herdr/herdr.sock herdr server stop`, then
  start it again with the same override. Stopping exits pane processes.
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
- **A first sync can delete branches that exist only on the beta side.**
  `.git` syncs like any other directory, so alpha's `refs/heads` and
  `packed-refs` win the initial reconciliation wholesale. Resetting elm's
  copy to a different commit before creating the session cost 23 branches in
  penguin and 10 in surestake, showing up as `00000000` in
  `git worktree list`. The commits survive: pause the session, then rebuild
  each ref from its reflog, whose files are untouched.

  ```sh
  find .git/logs/refs/heads -type f | while read -r f; do
    b=${f#.git/logs/refs/heads/}
    git rev-parse --verify -q "refs/heads/$b" >/dev/null && continue
    sha=$(awk 'END{print $2}' "$f")
    git cat-file -e "$sha" 2>/dev/null && git update-ref "refs/heads/$b" "$sha"
  done
  ```

  Only the first sync is dangerous. Once a common ancestor exists, a ref
  created on either side propagates instead of losing to alpha.
- **Edits made inside a tree before its session exists can be reverted** by
  that first reconciliation, because elm is alpha and wins. Commit them, or
  make them after the session reaches "Watching for changes". Editing
  `.mutagen.yml` or `sync-setup` while rebuilding a session is the easy way
  to hit this: the fix undoes itself and the sessions keep the ignores they
  were created with, so nothing looks broken.
- Ignored files never get deleted by sync — that's why `worktree-cleanup`
  rm's the wolf-side worktree dir (its node_modules would otherwise anchor a
  husk forever).
- **Sleep kills the ssh, never the session.** Agents stream output, so
  there's always TCP data in flight when the lid closes; the connection
  cannot survive, only reconnect. ssh signals connection errors with exit
  255 — that's the one code `wolf-attach` retries on. `wolf-agent` attaches
  with `-d` to kick the dropped client (otherwise the session stays
  letterboxed at its size), and the loop switches off stray mouse-reporting
  modes so clicks don't land as garbage while disconnected.

## Connecting a machine

The first sync has no common ancestor, so elm wins every disagreement,
`.git/refs` included. Decide which side is authoritative **per tree** before
creating any session, and never reset elm's copy to a different commit first.

1. Clone dotfiles, `stow .`, rebuild nix (installs mutagen and the daemon).
2. Pick the authoritative side for each tree:
   - **Elm's copy wins**: empty this machine's tree, or leave it absent.
   - **This machine wins**: empty elm's copy instead, so nothing collides.
   - **Neither can be emptied**: `git push --all` every repo on this machine
     first, so a ref lost to alpha is recoverable from the remote as well as
     from the reflog.
3. `sync-setup`. Sessions resume from `~/.mutagen` after reboots, and the
   launchd daemon keeps itself alive.
4. `sync-check` to confirm each session's frozen ignore list matches what git
   ignores today.
5. `git worktree list` in every synced repo. Any `00000000` means the first
   sync ate refs, recoverable from the reflogs (see Gotchas).
