{ config, pkgs, lib, ... }:

{
  imports = [
    ../../common.nix
    ./hardware.nix
    ../../modules/desktop.nix
    ../../modules/minecraft.nix
    ../../modules/backups.nix
  ];

  minecraft.private = true;
  minecraft.dataRoot = "/mnt/nvme/minecraft";
  # The public servers stay here until the sparrow cutover (port forwards + DNS).
  minecraft.public = true;
  resticBackups.minecraftPath = "/mnt/nvme/minecraft";
  minecraft.rexburgPort = 61658;
  systemd.services.tailscale-keepalive-pip = {
    description = "Keepalive ping to the pip relay to hold the tailscale NAT hole open";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.tailscale ];
    script = "tailscale ping --c 1 --timeout 3s 100.80.106.14 || true";
  };
  systemd.timers.tailscale-keepalive-pip = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "20s";
      AccuracySec = "1s";
    };
  };

  networking.hostName = "elm";
  networking.networkmanager.enable = true;

  boot.kernelModules = [ "sg" ];
  users.users.mikaelweiss.extraGroups = [ "cdrom" ];

  environment.systemPackages = with pkgs; [
    elixir
    erlang
    postgresql
    nodejs
    ffmpeg
    libdvdcss
    dvdbackup
    handbrake
    makemkv
    cockpit
  ];

  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/5E6F-A55B";
    fsType = "exfat";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "umask=0022" ];
  };

  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
      ARRAY /dev/md0 metadata=1.2 UUID=f1e05811:f63c3220:1dcb668e:8874e544
    '';
  };

  fileSystems."/mnt/raid" = {
    device = "/dev/md0";
    fsType = "exfat";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "umask=0022" ];
  };

  fileSystems."/mnt/nvme" = {
    device = "/dev/disk/by-uuid/088fdaee-9d60-47ea-b70c-dcd81d5264cd";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = true;
    settings.WebService = {
      AllowUnencrypted = true;
      Origins = lib.mkForce "https://localhost:9090 http://localhost:9090 https://elm:9090 http://elm:9090 https://100.81.131.90:9090 http://100.81.131.90:9090";
    };
  };

  users.users.ilovemywife = {
    isSystemUser = true;
    group = "ilovemywife";
    home = "/var/lib/ilovemywife";
    createHome = true;
    shell = pkgs.bash;
  };
  users.groups.ilovemywife = {};

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
  networking.firewall.allowedTCPPorts = [ 8096 ];

  system.stateVersion = "25.11";
}
