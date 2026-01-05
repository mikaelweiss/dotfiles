# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "elm"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Boise";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mikaelweiss = {
    isNormalUser = true;
    description = "Mikael Weiss";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
    shell = pkgs.zsh;
  };

  users.users.ilovemywife = {
    isSystemUser = true;
    group = "ilovemywife";
    home = "/var/lib/ilovemywife";
    createHome = true;
    shell = pkgs.bash;
  };
  users.groups.ilovemywife = {};

  # Passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
   wget
   neovim
   gcc # Dependancy of LazyVim
   vim
   git
   oh-my-zsh # Better zsh
   lazygit # Better git
   zoxide # Better cd
   zsh-powerlevel10k # ZSH theme
   meslo-lgs-nf # Nerd font
   fzf # Fuzy find files
   btop # Visualization of hardware status
   yazi # File browser
   restic # Backup software
   elixir
   erlang
   postgresql
   ripgrep
   unzip #Neovim dependancy
   claude-code
   tmux # Split screen and windows in the terminal
   tldr # Run tldr tmux to see the tldr for the tmux docs
   # Hyprland tools
   hyprland
   wofi
   waybar
   hyprpaper
   # Apps
   ghostty
   signal-desktop
   tailscale
   cockpit
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Enable nix-ld to run generic Linux binaries
  # Needed for mix assets.deploy
  programs.nix-ld.enable = true;

  programs.git = {
    enable = true;
    config = {
      user = {
        email = "campingmikael@icloud.com";
        name = "Mikael Weiss";
      };
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

  # Make it so that if you make new users, they default to zsh
  users.defaultUserShell = pkgs.zsh;

  # Filesystem stuff
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/5E6F-A55B";
    fsType = "exfat";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "umask=0022" ];
  };

  # Enable software RAID support
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
      ARRAY /dev/md0 metadata=1.2 UUID=f1e05811:f63c3220:1dcb668e:8874e544
    '';
  };

  # Mount the RAID array
  fileSystems."/mnt/raid" = {
    device = "/dev/md0";
    fsType = "exfat";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "umask=0022" ];
  };

  # Mount the NVME
  fileSystems."/mnt/nvme" = {
    device = "/dev/disk/by-uuid/088fdaee-9d60-47ea-b70c-dcd81d5264cd";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Cockpit
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = true;
    settings = {
      WebService = {
        AllowUnencrypted = true;
        Origins = lib.mkForce "https://localhost:9090 http://localhost:9090 https://elm:9090 http://elm:9090 https://100.81.131.90:9090 http://100.81.131.90:9090";
      };
    };
  };

  # Set up tailscale
  services.tailscale.enable = true;

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "SAMBA";
        security = "user";
        "passdb backend" = "tdbsam";
        "server min protocol" = "SMB3";
        "smb encrypt" = "required";
        "hosts allow" = "192.168.0.0/24 100.64.0.0/10 EXCEPT 192.168.0.103 100.105.253.35";
        "hosts deny" = "ALL";
        "load printers" = "no";
        printing = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
      };
      share = {
        comment = "My Share";
        path = "/home/mikaelweiss/share";
        writeable = "yes";
        browseable = "yes";
        public = "no";
        "valid users" = "mikaelweiss";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # Share backup service
  systemd.services.share-backup = {
    description = "Restic backup of share folder";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mikaelweiss";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    environment.RESTIC_PASSWORD_FILE = "/etc/restic/password";
    path = [ pkgs.restic pkgs.openssh ];
    script = ''
      restic -r /mnt/backup/share-backup backup /home/mikaelweiss/share
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/share-backup backup /home/mikaelweiss/share
      restic -r /mnt/backup/share-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/share-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    '';
  };

  systemd.timers.share-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  # Minecraft backup service
  systemd.services.minecraft-backup = {
    description = "Restic backup of minecraft server data";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mikaelweiss";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    environment.RESTIC_PASSWORD_FILE = "/etc/restic/password";
    path = [ pkgs.restic pkgs.openssh pkgs.podman ];
    script = ''
      restic -r /mnt/backup/minecraft-backup backup /home/mikaelweiss/.minecraft-server/data
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-backup backup /home/mikaelweiss/.minecraft-server/data
      restic -r /mnt/backup/minecraft-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    '';
  };

  systemd.timers.minecraft-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  systemd.services.ilovemywife = {
    description = "Website for Hannah";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = "ilovemywife";
      Group = "ilovemywife";
      WorkingDirectory = "/var/lib/ilovemywife";
      EnvironmentFile = "/etc/ilovemywife/env";
      ExecStart = "/var/lib/ilovemywife/i_love_my_wife/_build/prod/rel/i_love_my_wife/bin/i_love_my_wife start";
    };
  };
  services.jellyfin.enable = true;
  services.jellyfin.user = "mikaelweiss";
  
  # Virtualisations
  
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers.minecraft-server = {
      image = "docker.io/itzg/minecraft-server:latest";
      ports = [ "25565:25565" ];
      volumes = [ "/home/mikaelweiss/.minecraft-server/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = "1.21.10";
        UID = "1000";
        GID = "100";
        REMOVE_OLD_MODS = "FALSE";
      };
    };
  };

  # Trust tailscale interface
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 4000 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
