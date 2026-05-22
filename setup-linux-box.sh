#!/bin/bash
set -e

# ─── System ───────────────────────────────────────────────────
sudo apt update && sudo apt upgrade -y

# ─── Deploy user ──────────────────────────────────────────────
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy

# allow deploy to sudo without password (remove later if you want)
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy

# copy SSH keys
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# ─── SSH hardening ────────────────────────────────────────────
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# ─── PPAs / repos ────────────────────────────────────────────
sudo add-apt-repository -y ppa:neovim-ppa/unstable

# cloudflared (using noble codename — 26.04 not yet in their repo)
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt update

# ─── Apt packages ────────────────────────────────────────────
sudo apt install -y \
  zsh zoxide neovim stow \
  fail2ban unattended-upgrades \
  postgresql postgresql-contrib \
  cloudflared

# ─── Lazygit (PPA is dead, use GitHub binary) ────────────────
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin/
rm -f lazygit lazygit.tar.gz

# ─── Node 24 ─────────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
sudo apt-get install -y nodejs

# ─── Elixir & Erlang (official install script) ───────────────
sudo -u deploy bash -c '
  curl -fsSO https://elixir-lang.org/install.sh
  sh install.sh elixir@1.19.5 otp@28.1 installs_dir=$HOME/.elixir-install/installs
  rm -f install.sh
'

# ─── PostgreSQL (peer auth — no password needed) ─────────────
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo -u postgres createuser deploy --createdb

# ─── Dotfiles (as deploy, HTTPS clone) ───────────────────────
sudo -u deploy bash -c '
  mkdir -p ~/code
  git clone https://github.com/MikaelWeiss/dotfiles.git ~/code/dotfiles
  cd ~/code/dotfiles
  git switch linux
  stow git -t $HOME
  stow terminal -t $HOME
  stow codex -t $HOME
  stow agents -t $HOME
  stow claude -t $HOME
'

# ─── Zsh as default for deploy ───────────────────────────────
sudo chsh -s $(which zsh) deploy

# oh-my-zsh for deploy
sudo -u deploy bash -c 'RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'

# powerlevel10k
sudo -u deploy bash -c 'git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k'

# ─── CLI tools (as deploy) ───────────────────────────────────
# claude code
sudo -u deploy bash -c 'curl -fsSL https://claude.ai/install.sh | sh'

# pi.dev
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# codex
npm install -g @openai/codex

# ─── Elixir setup (as deploy) ────────────────────────────────
sudo -u deploy bash -c '
  export PATH=$HOME/.elixir-install/installs/otp/28.1/bin:$PATH
  export PATH=$HOME/.elixir-install/installs/elixir/1.19.5-otp-28/bin:$PATH
  mix local.hex --force
  mix local.rebar --force
  mix archive.install hex phx_new --force
'

echo ""
echo "✅ Done! SSH in as 'deploy' from now on."
echo ""
echo "⚠️  Remember to:"
echo "   - Add elixir/otp PATH exports to deploy's .zshrc"
echo "   - Set up your Cloudflare tunnel: cloudflared tunnel login"
echo "   - Create your app database: createdb your_app_prod"
