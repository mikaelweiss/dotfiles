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
  boot.kernelModules = [ "sg" ];
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

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mikaelweiss = {
    isNormalUser = true;
    description = "Mikael Weiss";
    extraGroups = [ "networkmanager" "wheel" "cdrom" ];
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
   jq # JSON CLI (used by the bedrock-whitelist helper script)
   unzip #Neovim dependancy
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
   ffmpeg
   libdvdcss
   dvdbackup
   handbrake
   makemkv
   stow
   atuin
   mise
   direnv
   nodejs
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
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" ];
    dnsovertls = "opportunistic";
  };

  networking.nameservers = [ "1.1.1.1" ];

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
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/share-backup backup /home/mikaelweiss/share
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/share-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
      restic -r /mnt/backup/share-backup backup /home/mikaelweiss/share || echo "local backup skipped (USB not mounted?)"
      restic -r /mnt/backup/share-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune || true
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

  # Unified Minecraft backup service (all servers under /mnt/nvme/minecraft/)
  systemd.services.minecraft-all-backup = {
    description = "Restic backup of all Minecraft server data";
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
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-all-backup backup /mnt/nvme/minecraft
      restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-all-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
      restic -r /mnt/backup/minecraft-all-backup backup /mnt/nvme/minecraft || echo "local backup skipped (USB not mounted?)"
      restic -r /mnt/backup/minecraft-all-backup forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune || true
    '';
  };

  systemd.timers.minecraft-all-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  # Keep the tailscale NAT hole to the pip relay punched open. elm is behind
  # double-NAT/CGNAT, so without steady outbound traffic the direct path to pip
  # lapses to idle and inbound Java (TCP) forwarded from pip black-holes until
  # something re-punches it. Bedrock's constant UDP stream masks this for itself;
  # this heartbeat does it for the whole tunnel. A tailscaled restart (e.g. on
  # nixos-rebuild) drops the established path, which is what broke Java today.
  systemd.services.tailscale-keepalive-pip = {
    description = "Keepalive ping to the pip relay to hold the tailscale NAT hole open";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.tailscale ];
    script = ''
      tailscale ping --c 1 --timeout 3s 100.80.106.14 || true
    '';
  };

  systemd.timers.tailscale-keepalive-pip = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "20s";
      AccuracySec = "1s";
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

  # Jellyfin
  
  services.jellyfin.enable = true;
  services.jellyfin.user = "mikaelweiss";
  
  # Required so podman containers on the bridge network can reach the
  # internet (NAT/forwarding). Without this, containers can't reach
  # Mojang's auth servers and online-mode joins fail with "Authentication
  # servers are down". `ip_forward` and `conf.all.forwarding` are kernel
  # aliases; set both so neither overrides the other at boot.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  # Virtualisations

  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers.minecraft-server = {
      # java25 image (matches rexburg-friends): MC 26.1.x needs a current JDK.
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "25565:25565" ];
      volumes = [ "/mnt/nvme/minecraft/minecraft-server/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        # Pinned (not LATEST): mods track one MC version at a time, so an auto-bump
        # would break them. Bump deliberately once the mods below ship the next build.
        VERSION = "26.1.2";
        # Auto-download server-relevant mods from Modrinth on each start (always latest
        # compatible build). Client-only mods (Sodium, BetterF3, Mod Menu, MouseTweaks,
        # MidnightControls, FullBrightnessToggle) were dropped: they do nothing on a
        # dedicated server. fabric-api = base lib; fallingtree = server-required;
        # journeymap/appleskin kept for their optional server-side features.
        MODRINTH_PROJECTS = "fabric-api,fallingtree,journeymap,appleskin,x-to-xray";
        # JourneyMap only ships a beta build for 26.1.2; beta also accepts release mods.
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        UID = "1000";
        GID = "100";
        REMOVE_OLD_MODS = "FALSE";
      };
    };

    containers.rexburg-friends = {
      image = "docker.io/itzg/minecraft-server:java25";
      # Published on host port 61658; the VPS Tailscale relay DNATs inbound
      # public traffic to <home-tailscale-ip>:61658. Kept off 25565 because the
      # minecraft-server container above already uses that host port.
      #
      # UDP 19132 is Geyser's Bedrock listener. The VPS relay must ALSO DNAT inbound
      # public UDP 19132 -> <home-tailscale-ip>:19132 for Bedrock players to connect.
      ports = [ "61658:25565" "19132:19132/udp" ];
      volumes = [ "/mnt/nvme/minecraft/rexburg-friends/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        # Fabric loader so Geyser + Floodgate can run as mods (Bedrock crossplay).
        TYPE = "FABRIC";
        MEMORY = "2G";
        # Pinned (not LATEST): Geyser-Fabric and Fabric API track one MC version at a
        # time, so an auto-bump to a newer MC than Geyser supports would break the
        # server. Bump deliberately once Geyser-Fabric ships a build for the next version.
        VERSION = "26.1.2";
        # Auto-download these mods from Modrinth on each start. Required deps (e.g.
        # fabric-api) are resolved automatically; fabric-api also listed to be explicit.
        # geyser/floodgate = Bedrock crossplay; fallingtree/journeymap/appleskin mirror
        # the normal minecraft-server so both worlds run the same server-side mod set.
        # All three are server-side-compatible and do NOT force Java clients to install
        # them, so vanilla (non-Fabric) and Bedrock players can still connect.
        MODRINTH_PROJECTS = "geyser,floodgate,fabric-api,fallingtree,journeymap,appleskin,x-to-xray";
        # Geyser publishes its Fabric builds on the beta channel, so allow beta. This
        # setting still accepts release-channel mods (Floodgate, fabric-api) too.
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        # Required for Bedrock players to chat (they can't sign Java 1.19+ secure chat).
        # Server stays online-mode=true; Floodgate authenticates Bedrock (hybrid mode).
        ENFORCE_SECURE_PROFILE = "false";
        UID = "1000";
        GID = "100";
        MOTD = "Rexburg Friends";
        # Disable Minecraft 26.x's auto-pause: tunneled connections (via the VPS
        # relay) don't wake a paused server, so joins hang at "Connecting to server".
        PAUSE_WHEN_EMPTY_SECONDS = "0";
        ENABLE_WHITELIST = "TRUE";
      };
    };

    containers.skyblock = {
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "25566:25565" "19133:19132/udp" ];
      volumes = [ "/mnt/nvme/minecraft/skyblock/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        TYPE = "PAPER";
        MEMORY = "2G";
        VERSION = "26.1.2";
        MODRINTH_PROJECTS = "luckperms,vaultunlocked,placeholderapi,worldedit,worldguard,geyser,journeymap";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        ENFORCE_SECURE_PROFILE = "false";
        PAUSE_WHEN_EMPTY_SECONDS = "0";
        UID = "1000";
        GID = "100";
        MOTD = "SkyBlock";
        MAX_PLAYERS = "50";
        DIFFICULTY = "normal";
        SPAWN_PROTECTION = "0";
        ALLOW_FLIGHT = "true";
      };
    };
  };

  # Trust tailscale interface
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
  networking.firewall.allowedTCPPorts = [ 8096 25566 ];

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
