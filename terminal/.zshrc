# Instant Prompt stuff
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
# zstyle ':omz:update' mode disabled # Run this if update hangs when offline
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git dotenv macos sudo rsync systemd xcode)
(( $+functions[omz] )) || source "$ZSH/oh-my-zsh.sh"

# ENV vars
export MAX_MCP_OUTPUT_TOKENS=250000
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1
export CLAUDE_CODE_NO_FLICKER=1
export PI_LENS_STARTUP_MODE=quick

# Alias'
alias gs="git status"
alias gstk='git add . && git stash push && git stash apply'
alias lg='lazygit'
alias gcm="git commit -m"
unalias gcl 2>/dev/null
gcl() {
    git clone git@github.com:mikaelweiss/$1.git
}
gbc() {
    git checkout -b $1 && git push -u origin $1
}
gw() {
    git worktree add -b "mikael/$1" ".worktrees/$1" && \
    cd ".worktrees/$1" && \
    cp ../../.env . && \
    cp ../../.env.local . && \
    direnv allow
    # git push -u origin "mikael/$1"
}
gwa() {
    git worktree add -b "mikael/$1" ".worktrees/$1" && \
    cd ".worktrees/$1" && \
    cp ../../.env . && \
    cp ../../apps/functions/.secret.local apps/functions/
    pnpm i
    # git push -u origin "mikael/$1"
}
gwr() {
    git worktree add -b "mikael/$1" ".worktrees/$1" && \
    cd ".worktrees/$1" && \
    cp ../../.env.local . && \
    bun i
    # git push -u origin "mikael/$1"
}
gwru() {
    git worktree add -b "mikael/$1" ".worktrees/$1" main && \
    cd ".worktrees/$1" && \
    cp ../../.env.local . && \
    npm i
    # git push -u origin "mikael/$1"
}
gwc() {
  git worktree add -b "mikael/$1" "~/.worktrees/ClipSpeak/$1" && \
  cd "/Users/mikaelweiss/.worktrees/ClipSpeak/$1"
}
alias gcp='git checkpoint'
alias gcpl='git listCheckpoints'
alias gcpd='git deleteCheckpoint'
alias gcpld='git loadCheckpoint'
alias minecraftskins='open Library/Application\ Support/minecraft/assets/skins'
alias minecraft='open Library/Application\ Support/minecraft'

# Random
alias icloud='cd ~/Library/Mobile\ Documents/com\~apple\~CloudDocs'
alias venv='source .venv/bin/activate'
alias xc='sh ~/code/dotfiles/resize-xcode.sh'
alias :q='exit'
# Every rebuild moves each flake input to the newest commit on its branch, so
# nothing waits on a lock bump. The lock file stays untouched, which keeps the
# git checkouts on sparrow and oak clean, and is the fallback when offline.
_nix_latest_inputs() {
  nix flake metadata --json --no-write-lock-file ~/code/dotfiles/nix 2>/dev/null | jq -r '
    .locks.nodes as $n | $n.root.inputs | to_entries[]
    | select(.value | type == "string") | .key as $k | $n[.value].original
    | select(.type == "github")
    | "--override-input", $k, "github:\(.owner)/\(.repo)\(if .ref then "/" + .ref else "" end)"'
}
# Unauthenticated GitHub API calls hit a 60 per hour limit.
_nix_github_auth() {
  local token
  token=$(gh auth token 2>/dev/null) || return
  print -l -- --option access-tokens "github.com=$token"
}
nix-rebuild() {
  if [[ $(hostname -s) == oak ]]; then
    echo "Use nix-rebuild-oak on oak."
    return 1
  fi
  local -a latest=(${(f)"$(_nix_latest_inputs)"} ${(f)"$(_nix_github_auth)"})
  if [[ "$OSTYPE" == darwin* ]]; then
    sudo darwin-rebuild switch --flake ~/code/dotfiles/nix#$(scutil --get LocalHostName) --refresh --no-write-lock-file "${latest[@]}"
  else
    sudo nixos-rebuild switch --flake ~/code/dotfiles/nix --refresh --no-write-lock-file "${latest[@]}"
  fi
}

# Nobody can reach oak's console, so a bad switch must undo itself. A timer
# switches back to the previous system unless a fresh SSH session proves the
# new one still lets people in.
_nix_rebuild_with_revert() {
  local revert=nix-rebuild-revert profile=/nix/var/nix/profiles/system
  if [[ $1 == keep ]]; then
    if ! systemctl is-active -q $revert.timer; then
      echo "No revert is pending. Running: $(readlink -f /run/current-system)"
      return 1
    fi
    sudo systemctl stop $revert.timer && echo "Kept $(readlink -f $profile)."
    return
  fi
  if systemctl is-active -q $revert.timer; then
    echo "A revert is pending. Run 'nix-rebuild-oak keep' from a new SSH session, or let it revert."
    return 1
  fi

  local -a latest=(${(f)"$(_nix_latest_inputs)"} ${(f)"$(_nix_github_auth)"})
  local old=$(readlink -f $profile) new
  new=$(nix build --no-link --print-out-paths --refresh --no-write-lock-file "${latest[@]}" \
    ~/code/dotfiles/nix#nixosConfigurations.$(hostname -s).config.system.build.toplevel) || return 1
  if [[ $new == $old ]]; then
    echo "Already up to date."
    return
  fi

  sudo systemd-run --quiet --collect --on-active=10min --unit=$revert -p Type=oneshot \
    /bin/sh -c "$old/sw/bin/nix-env -p $profile --set $old && $old/bin/switch-to-configuration switch" || return 1
  # A transient unit keeps switching even if this SSH session drops mid-activation.
  if ! sudo systemd-run --quiet --collect --wait --pipe --unit=nix-rebuild-switch \
    /bin/sh -c "$old/sw/bin/nix-env -p $profile --set $new && $new/bin/switch-to-configuration switch"; then
    echo "Switch failed. Reverting now."
    sudo systemctl start $revert.service; sudo systemctl stop $revert.timer
    return 1
  fi

  local failed=$(systemctl --failed --no-legend | wc -l)
  if ! systemctl is-active -q sshd || ! systemctl is-active -q tailscaled || (( failed > 0 )) \
    || ! tailscale ping --tsmp -c 1 --timeout 10s elm >/dev/null 2>&1; then
    echo "Health check failed (failed units: $failed). Reverting now."
    sudo systemctl start $revert.service; sudo systemctl stop $revert.timer
    return 1
  fi
  echo "Switched to $new."
  echo "Open a new SSH session and run 'nix-rebuild-oak keep' within 10 minutes, or it reverts."
}
nix-rebuild-oak() {
  if [[ $(hostname -s) != oak ]]; then
    echo "nix-rebuild-oak only runs on oak."
    return 1
  fi
  _nix_rebuild_with_revert "$@"
}
alias nix-config='nvim ~/code/dotfiles/nix/shared.nix'
alias nix-clean='nix-collect-garbage --delete-older-than 7d && sudo nix-collect-garbage --delete-older-than 7d && nix-store --optimise'
if [[ "$OSTYPE" == darwin* ]]; then
  alias clean='mole clean && nix-clean'
else
  alias clean='nix-clean'
fi
alias tm='tmux new-session -A -s main'
alias stopheat='xcrun simctl shutdown all'

# Wolf (Mac mini): attach this directory's session there (deps auto-install,
# then a plain shell); pass a command to run instead, e.g. `wolf claude`.
# wolf-attach reconnects automatically when the link drops (lid close).
export PATH="$HOME/code/dotfiles/terminal/bin:$PATH"
wolf() {
  ~/code/dotfiles/terminal/bin/wolf-attach "$PWD" "${PWD:t}" $*
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# Stuff for fly.io
export FLYCTL_INSTALL="/Users/mikaelweiss/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
# Cargo
export PATH="$HOME/.cargo/bin:$PATH"
# Ruby
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
# Erlang/OTP 28 (keg-only; must precede unversioned erlang so elixir/mix run on OTP 28)
export PATH="/opt/homebrew/opt/erlang@28/bin:$PATH"
# Local bin
export PATH="$HOME/.local/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/mikaelweiss/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# opencode
export PATH=/Users/mikaelweiss/.opencode/bin:$PATH

export PATH="/opt/homebrew/opt/node/bin:$PATH"

# Source Kit LSP
export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp:$PATH"

export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"

export _ZO_EXCLUDE_DIRS="$HOME/.t3/*"
eval "$(zoxide init zsh)"

# Enable shell history with iex
export ERL_AFLAGS="-kernel shell_history enabled"

eval "$(atuin init zsh --disable-up-arrow)"

# Set up term
export TERM=xterm-256color

# SwiftPM
export PATH="$HOME/.swiftpm/bin:$PATH"

# Route claude through the rotating proxy on wolf. Each machine keeps its own
# device key outside ~/.config, which mutagen syncs.
[[ -r ~/.local/state/claude-rotate/env ]] && source ~/.local/state/claude-rotate/env

# alias's
alias home='cd /Users/mikaelweiss/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/Home'
alias claude='claude --dangerously-skip-permissions'
alias codex='codex -c model_reasoning_effort="high" --ask-for-approval never --sandbox danger-full-access'
alias c='claude'
alias st='bun run dev:desktop'
alias s='bunx convex dev'
alias sta='pnpm -F web electron:dev'
alias sa='pnpm run start'
alias claudef='claude --model fable'
alias cf='claude --model fable'
alias cs='claude --model sonnet'
alias ca='env -u ANTHROPIC_BASE_URL -u CLAUDE_CODE_OAUTH_TOKEN claude'
alias aspen="/Users/mikaelweiss/code/aspen-grove/core/bin/aspen"
alias a="/Users/mikaelweiss/code/aspen-grove/core/bin/aspen"
alias noveltty="/Users/mikaelweiss/code/noveltty/target/release/noveltty"
alias p='$HOME/code/penguin-v2/bin/penguin'

# Added by ma CLI installer
export PATH="$HOME/.ma/bin:$PATH"
export PATH="$HOME/.ma/bin:$PATH"

# mise (node/python/etc version manager, per-project pinning)
# eval "$(mise activate zsh)"

# Added by cog CLI installer
export PATH="$HOME/.cog/bin:$PATH"

# Keep Homebrew on the main branch for macOS 27 pre-release support (until a stable tag ships it)
export HOMEBREW_DEVELOPER=1

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

export CONTEXT7_API_KEY="$(
  security find-generic-password \
    -a "$USER" \
    -s "context7-api-key" \
    -w 2>/dev/null
  )"
export PATH="/Users/mikaelweiss/.config/herd-lite/bin:$PATH"
export PHP_INI_SCAN_DIR="/Users/mikaelweiss/.config/herd-lite/bin:$PHP_INI_SCAN_DIR"
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# bun completions
[ -s "/Users/mikaelweiss/spike-bun-test/bunlatest/_bun" ] && source "/Users/mikaelweiss/spike-bun-test/bunlatest/_bun"

# pass
setup-pass() {
  local uid="Mikael Weiss <campingmikael@icloud.com>"
  local fpr statusfile

  if [[ "$1" != "--new" ]]; then
    fpr=$(gpg --list-secret-keys --with-colons "$uid" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
  fi

  if [[ -z "$fpr" ]]; then
    statusfile=$(mktemp "${TMPDIR:-/tmp}/setup-pass.XXXXXX") || return 1
    # Naming an algo skips the encryption subkey that pass requires.
    gpg --batch --passphrase "" --yes --status-file "$statusfile" --quick-generate-key "$uid" default default 2y || {
      rm -f "$statusfile"
      return 1
    }
    fpr=$(awk '/KEY_CREATED/ {print $4}' "$statusfile")
    rm -f "$statusfile"
  fi

  if [[ -z "$fpr" ]]; then
    print -u2 "setup-pass: could not determine key fingerprint"
    return 1
  fi

  pass init "$fpr"
}

unsetopt autocd

# >>> command-nvm-directory-switch >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use
# nvm refuses to switch while NPM_CONFIG_PREFIX is set, and Nix exports it for npm globals.
use_nvmrc_node() {
  local nvmrc_dir
  nvmrc_dir="$(nvm_find_up .nvmrc)"
  if [[ -z "$nvmrc_dir" ]]; then
    [[ "$(nvm current)" != "$(nvm version default)" ]] && NPM_CONFIG_PREFIX= nvm use --silent default
    return
  fi
  local wanted
  wanted="$(nvm version "$(<"$nvmrc_dir/.nvmrc")")"
  if [[ "$wanted" == "N/A" ]]; then
    NPM_CONFIG_PREFIX= nvm install
  elif [[ "$(nvm current)" != "$wanted" ]]; then
    NPM_CONFIG_PREFIX= nvm use --silent "$wanted"
  fi
}
autoload -U add-zsh-hook
add-zsh-hook chpwd use_nvmrc_node
use_nvmrc_node
# <<< command-nvm-directory-switch <<<
