# Instant Prompt stuff
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git dotenv sudo rsync systemd)
source $ZSH/oh-my-zsh.sh

# ENV vars
export MAX_MCP_OUTPUT_TOKENS=250000
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1
export PI_LENS_STARTUP_MODE=quick

# Alias'
alias gs="git status"
alias gstk='git add . && git stash push && git stash apply'
alias lg='lazygit'
alias gcm="git commit -m"
unalias gcl 2>/dev/null
gcl() {
    git clone git@github.com:MikaelWeiss/$1.git
}
gbc() {
    git checkout -b $1 && git push -u origin $1
}
alias gcp='git checkpoint'
alias gcpl='git listCheckpoints'
alias gcpd='git deleteCheckpoint'
alias gcpld='git loadCheckpoint'

# Random
alias venv='source .venv/bin/activate'
alias :q='exit'
alias tm='tmux new-session -A -s main'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# Zoxide
export _ZO_EXCLUDE_DIRS="$HOME/.t3/*"
eval "$(zoxide init zsh)"

# Enable shell history with iex
export ERL_AFLAGS="-kernel shell_history enabled"

# Set up term
export TERM=xterm-256color

# alias's
alias claude='claude --dangerously-skip-permissions --model claude-opus-4-6\[1m\]'
alias codex='codex -c model_reasoning_effort="high" --ask-for-approval never --sandbox danger-full-access'
alias c='claude'
alias st='bun run dev:desktop'
alias s='bunx convex dev'
alias sta='pnpm -F web electron:dev'
alias sa='pnpm run start'

# Elixir stuff
export PATH=$HOME/.elixir-install/installs/otp/28.1/bin:$PATH
export PATH=$HOME/.elixir-install/installs/elixir/1.19.5-otp-28/bin:$PATH
