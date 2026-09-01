{ config, pkgs, lib, ... }:

let
  cfg = config.minecraft;
  dataRoot = cfg.dataRoot;
in
{
  options.minecraft = {
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/minecraft";
    };
    rexburgPort = lib.mkOption {
      type = lib.types.port;
      default = 25571;
    };
  };

  config = {
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";

    # Tailnet-only. Not port-forwarded on purpose.
    containers.minecraft-server = {
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "25565:25565" ];
      volumes = [ "${dataRoot}/minecraft-server/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = "26.1.2";
        MODRINTH_PROJECTS = "fabric-api,fallingtree,journeymap,appleskin,x-to-xray";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        UID = "1000";
        GID = "100";
        REMOVE_OLD_MODS = "FALSE";
      };
    };

    # Public. Host ports match what players already have saved from the old
    # relay (25571 Java, 19132 Bedrock), so only the address changes.
    containers.rexburg-friends = {
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "${toString cfg.rexburgPort}:25565" "19132:19132/udp" ];
      volumes = [ "${dataRoot}/rexburg-friends/data:/data" ];
      autoStart = true;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = "26.1.2";
        MODRINTH_PROJECTS = "geyser,floodgate,fabric-api,fallingtree,journeymap,appleskin,x-to-xray";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        ENFORCE_SECURE_PROFILE = "false";
        UID = "1000";
        GID = "100";
        MOTD = "Rexburg Friends";
        PAUSE_WHEN_EMPTY_SECONDS = "0";
        ENABLE_WHITELIST = "TRUE";
      };
    };

    containers.skyblock = {
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "25566:25565" "19133:19132/udp" ];
      volumes = [ "${dataRoot}/skyblock/data:/data" ];
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

  # Podman pulls the image on first start, which raced DNS at boot.
  systemd.services = lib.genAttrs [ "podman-minecraft-server" "podman-rexburg-friends" "podman-skyblock" ] (_: {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  });

  systemd.tmpfiles.rules = map (n: "d ${dataRoot}/${n}/data 0755 1000 100 -") [ "minecraft-server" "rexburg-friends" "skyblock" ];

  networking.firewall.allowedTCPPorts = [ cfg.rexburgPort 25566 ];
  networking.firewall.allowedUDPPorts = [ 19132 19133 ];
  };
}
