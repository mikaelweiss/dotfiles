#!/bin/bash

# git switch linux
# sudo apt install stow
# stow git -t $HOME
# stow terminal -t $HOME
# stow codex -t $HOME
# stow agents -t $HOME
# stow claude -t $HOME

# zsh
sudo apt install -y zsh
sudo chsh -s $(which zsh) $USER

# oh-my-zsh (unattended)
RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# powerlevel10k via oh-my-zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# zoxide
sudo apt install zoxide -y

# Nodejs
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs

# claude code
curl -fsSL https://claude.ai/install.sh | sh

# pi.dev
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# codex (needs node 18+)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g @openai/codex
