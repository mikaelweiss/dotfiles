# Instant Prompt stuff
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git dotenv macos sudo rsync systemd xcode)
source $ZSH/oh-my-zsh.sh

# Alias'
alias cat=lolcat
alias gs="git status"
alias lg='lazygit'
alias gcm="git commit -m"
unalias gcl 2>/dev/null
gcl() {
    git clone git@github.com:MikaelWeiss/$1.git
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
alias nix-rebuild='sudo darwin-rebuild switch'
alias nix-config='nvim /Users/mikaelweiss/code/dotfiles/nix-darwin/flake.nix'
alias nix-clean='nix-collect-garbage --delete-older-than 7d && sudo nix-collect-garbage --delete-older-than 7d && nix-store --optimise'
alias tm='tmux new-session -A -s main'

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
# Elixir
export PATH="$PATH:/path/to/elixir/bin"
# Local bin
export PATH="$HOME/.local/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/mikaelweiss/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Pyenv setup
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# opencode
export PATH=/Users/mikaelweiss/.opencode/bin:$PATH

export PATH="/opt/homebrew/opt/node/bin:$PATH"
export PATH=$HOME//opt/homebrew/bin:$PATH
export PATH=$HOME//opt/homebrew/Cellar/erlang/28.1/lib/erlang/erts-16.1/bin:$PATH

# Source Kit LSP
export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp:$PATH"

export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"

eval "$(zoxide init zsh)"

# Enable shell history with iex
export ERL_AFLAGS="-kernel shell_history enabled"

# Direnv stuff
eval "$(direnv hook zsh)"
eval "$(atuin init zsh)"

# Set up term
export TERM=xterm-256color

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/mikaelweiss/.lmstudio/bin"
# End of LM Studio CLI section

alias st='pnpm -F web electron:dev'
alias s='pnpm run start'
alias home='cd /Users/mikaelweiss/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/Home'
alias claude='claude --dangerously-skip-permissions'
alias c='claude'
alias st='bun run dev:desktop'
alias s='bunx convex dev'
