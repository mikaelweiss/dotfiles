# Everything in here lands on every machine, Mac and Linux alike.
# Only options that exist in both nix-darwin and NixOS belong here.
{ pkgs, ... }:

{
  imports = [ ./modules/node.nix ./modules/npm-globals.nix ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 30d";

  environment.systemPackages = with pkgs; [
    neovim
    vim
    wget
    ripgrep
    ast-grep
    fzf
    zoxide
    atuin
    btop
    yazi
    lazygit
    tmux
    tldr
    stow
  ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.zsh.enable = true;

  # A worktree inherits the .envrc of a checkout that was already approved, so
  # whitelisting the worktree root saves a `direnv allow` on every new branch.
  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv.enable = true;
    settings.whitelist.prefix = [
      "/Users/mikaelweiss/code"
      "/Users/mikaelweiss/.worktrees"
      "/Users/mikaelweiss/.penguin/worktrees"
      "/home/mikaelweiss/code"
      "/home/mikaelweiss/.worktrees"
      "/home/mikaelweiss/.penguin/worktrees"
    ];
  };

  # Global npm packages, installed and pruned on every rebuild the way
  # homebrew.brews is. Add a host-only package in that host's file.
  npm.globalPackages = [
    "wrangler"
    "nx"
    "@earendil-works/pi-coding-agent"
    "opencode-ai"
  ];
}
