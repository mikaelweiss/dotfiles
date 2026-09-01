{ config, pkgs, inputs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/Boise";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true;

  networking.nameservers = [ "1.1.1.1" ];
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" ];
    dnsovertls = "opportunistic";
  };

  # Home lives at the macOS path so synced git worktrees and Claude Code
  # session keys resolve identically on every machine.
  users.users.mikaelweiss = {
    isNormalUser = true;
    description = "Mikael Weiss";
    home = "/Users/mikaelweiss";
    createHome = true;
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICglGGyl2P6zOGxx8jH7kYBfCiWd2252i+w6t8MMvR7j campingmikael@icloud.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP8ixesNuSiP95u1o7ob0m0B42onRNaMB+Rgfzn8Pka2 mikaelweiss@Mikaels-Mac-mini.local"
    ];
  };
  users.defaultUserShell = pkgs.zsh;
  systemd.tmpfiles.rules = [ "L /home/mikaelweiss - - - - /Users/mikaelweiss" ];
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    wget
    neovim
    gcc
    vim
    git
    lazygit
    zoxide
    fzf
    btop
    yazi
    restic
    ripgrep
    jq
    unzip
    tmux
    tldr
    stow
    atuin
    mise
    direnv
    tailscale
    zsh-powerlevel10k
    meslo-lgs-nf
  ];

  programs.nix-ld.enable = true;

  programs.git = {
    enable = true;
    config.user = {
      email = "campingmikael@icloud.com";
      name = "Mikael Weiss";
    };
  };

  programs.zsh = {
    enable = true;
    promptInit = "source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "sudo" "rsync" "systemd" ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Tailscale tracks upstream faster than the stable channel; pull it from unstable.
  nixpkgs.overlays = [
    (final: prev: {
      tailscale = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.tailscale;
    })
  ];
  # Trust oak's host key so restic sftp backups verify non-interactively.
  programs.ssh.knownHosts.oak = {
    hostNames = [ "oak" "100.91.63.11" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInXxQTbkaN/w43UcmNdZ6M4GoAONrfQBUKNP/6mXScW";
  };

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

  hardware.cpu.intel.updateMicrocode = true;
}
