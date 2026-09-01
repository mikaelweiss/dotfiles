{ config, pkgs, lib, ... }:

let
  cfg = config.minecraft;
  dataRoot = cfg.dataRoot;
  names = lib.optional cfg.private "minecraft-server"
    ++ lib.optionals cfg.public [ "rexburg-friends" "skyblock" ];
in
{
  options.minecraft = {
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/minecraft";
    };
    rexburgPort = lib.mkOption {
      type = lib.types.port;
      default = 25565;
    };
    private = lib.mkEnableOption "the tailnet-only minecraft-server";
    public = lib.mkEnableOption "the port-forwarded rexburg-friends and skyblock servers";
  };

  config = {
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";

    containers = lib.mkMerge [
    (lib.mkIf cfg.private {
    # Tailnet-only. Not port-forwarded on purpose.
    minecraft-server = {
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
    })
    (lib.mkIf cfg.public {
    # Public, on the default Java and Bedrock ports so players need no port.
    rexburg-friends = {
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

    skyblock = {
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
    })
    ];
  };

  # Podman pulls the image on first start, which raced DNS at boot.
  systemd.services = lib.genAttrs (map (n: "podman-${n}") names) (_: {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  });

  systemd.tmpfiles.rules = map (n: "d ${dataRoot}/${n}/data 0755 1000 100 -") names;

  networking.firewall.allowedTCPPorts = lib.optionals cfg.public [ cfg.rexburgPort 25566 ];
  networking.firewall.allowedUDPPorts = lib.optionals cfg.public [ 19132 19133 ];
  };
}
