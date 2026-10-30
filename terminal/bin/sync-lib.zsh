# Shared by sync-setup and sync-check. Elm is the hub and the alpha side of
# every session: on a simultaneous-write conflict, elm's copy wins.
hub=elm

# Git-ignored paths that sync anyway, so `claude --resume` and ccusage see
# every machine, and so a brief rendered over ssh opens on the laptop.
keep='/(claude/\.claude/(projects|plugins|briefs)|codex/\.codex/plugins)$'

# Descends until it finds a repo, then stops.
repos_under() {
  setopt local_options null_glob
  local root=$1 depth=${2:-3} d
  if [[ -e $root/.git ]]; then print -r -- "$root"; return; fi
  (( depth <= 0 )) && return
  for d in "$root"/*; do
    [[ -d "$d" ]] && repos_under "$d" $(( depth - 1 ))
  done
}

# Mutagen cannot read .gitignore, so ask git what it ignores and pass that in.
# The answer freezes at session creation, which is why ~/.mutagen.yml still
# carries bare names: those keep matching directories created later. Run
# sync-check to see when a session has drifted far enough to rebuild.
gitignored() {
  local root=$1 repo prefix
  local -a repos
  repos=( ${(f)"$(repos_under "$root")"} )
  for repo in $repos; do
    prefix=${repo#$root}
    { git -C "$repo" status --ignored --porcelain 2>/dev/null || true; } |
      sed -n 's|^!! ||p' | sed 's|^"||; s|"$||' | sed "s|^|$prefix/|; s|/\$||"
  done | grep -vE "$keep" | sed 's|^|--ignore=|'
}

# One "name root" pair per line.
sessions() {
  print -r -- "code $HOME/code"
  print -r -- "worktrees $HOME/.worktrees"
}

session_ignores() {
  mutagen sync list -l "$1" 2>/dev/null |
    sed -n '/Ignores:/,/Ignore VCS/p' | sed -n 's|^\t\t|--ignore=|p'
}
