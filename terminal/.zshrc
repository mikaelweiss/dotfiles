# Instant Prompt stuff
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
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
if [[ "$OSTYPE" == darwin* ]]; then
  alias nix-rebuild='sudo darwin-rebuild switch --flake ~/code/dotfiles/nix#$(scutil --get LocalHostName)'
else
  alias nix-rebuild='sudo nixos-rebuild switch --flake ~/code/dotfiles/nix'
fi
alias nix-update='(cd ~/code/dotfiles/nix && nix flake update) && nix-rebuild'
alias nix-config='nvim ~/code/dotfiles/nix/shared.nix'
alias nix-clean='nix-collect-garbage --delete-older-than 7d && sudo nix-collect-garbage --delete-older-than 7d && nix-store --optimise'
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
alias fulcrum='/Users/mikaelweiss/Applications/Fulcrum.app/Contents/Resources/bin/fulcrum'
alias f='/Users/mikaelweiss/Applications/Fulcrum.app/Contents/Resources/bin/fulcrum'
alias p='bin/penguin'

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
    gpg --yes --status-file "$statusfile" --quick-generate-key "$uid" default default 2y || {
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
