# Instant Prompt stuff
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git dotenv macos sudo rsync systemd xcode)
source $ZSH/oh-my-zsh.sh

# ENV vars
export MAX_MCP_OUTPUT_TOKENS=250000
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1
export CLAUDE_CODE_NO_FLICKER=1
# export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-6[1m]'
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
alias nix-rebuild='sudo darwin-rebuild switch --flake ~/code/dotfiles/nix-darwin#$(scutil --get LocalHostName)'
alias nix-update='(cd ~/code/dotfiles/nix-darwin && nix flake update) && nix-rebuild'
alias nix-config='nvim /Users/mikaelweiss/code/dotfiles/nix-darwin/flake.nix'
alias nix-clean='nix-collect-garbage --delete-older-than 7d && sudo nix-collect-garbage --delete-older-than 7d && nix-store --optimise'
alias tm='tmux new-session -A -s main'

# Wolf (Mac mini): attach this directory's session there (deps auto-install,
# then a plain shell); pass a command to run instead, e.g. `wolf claude`.
# wolf-attach reconnects automatically when the link drops (lid close).
export PATH="$HOME/code/dotfiles/terminal/bin:$PATH"
wolf() {
  ~/code/dotfiles/terminal/bin/wolf-attach "$PWD" "${PWD:t}" $*
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

eval $(/opt/homebrew/bin/brew shellenv)

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

# Direnv stuff
eval "$(direnv hook zsh)"
eval "$(atuin init zsh --disable-up-arrow)"

# Set up term
export TERM=xterm-256color

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/mikaelweiss/.lmstudio/bin"
# End of LM Studio CLI section

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

# Claude Code driven by a Codex-backed model, via the local cliproxyapi proxy.
# CLIPROXY_TOKEN is set in ~/.config/cliproxy/env (not in git) and must match an
# entry in /opt/homebrew/etc/cliproxyapi.conf `api-keys`. It stays a plain shell
# var, never exported — an exported ANTHROPIC_AUTH_TOKEN would hijack plain
# `claude` too.
[[ -f ~/.config/cliproxy/env ]] && source ~/.config/cliproxy/env
: ${CLAUDEX_MODEL:=gpt-5.6-sol-fast}
claudex() {
  if [[ -z "$CLIPROXY_TOKEN" ]]; then
    print -u2 "claudex: CLIPROXY_TOKEN unset — create ~/.config/cliproxy/env"
    return 1
  fi
  local proxy_status
  proxy_status=$(curl -sS -m 2 -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:8317/v1/models" \
      -H "Authorization: Bearer $CLIPROXY_TOKEN")
  if [[ "$proxy_status" != 200 ]]; then
    print -u2 "claudex: cliproxyapi health check failed (HTTP ${proxy_status:-unreachable})"
    print -u2 "claudex: check /opt/homebrew/etc/cliproxyapi.conf and run: brew services restart cliproxyapi"
    return 1
  fi
  ANTHROPIC_BASE_URL=http://127.0.0.1:8317 \
  ANTHROPIC_AUTH_TOKEN="$CLIPROXY_TOKEN" \
  CLAUDE_CODE_SUBAGENT_MODEL="$CLAUDEX_MODEL" \
  CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 \
  CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3 \
  ENABLE_TOOL_SEARCH=false \
  command claude --dangerously-skip-permissions --model "$CLAUDEX_MODEL" --effort high "$@"
}

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
