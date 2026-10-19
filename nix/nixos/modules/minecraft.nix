{ config, pkgs, lib, ... }:

let
  cfg = config.minecraft;
  dataRoot = cfg.dataRoot;
  names = lib.optional cfg.private "minecraft-server"
    ++ lib.optionals cfg.public [ "rexburg-friends" "skyblock" ];

  version = "26.1.2";
  protocol = 775;
  publicPort = { minecraft-server = 25565; rexburg-friends = cfg.rexburgPort; skyblock = 25566; };
  internalPort = { minecraft-server = 35565; rexburg-friends = 35566; skyblock = 35567; };

  runContainer = n: pkgs.writeShellScript "run-${n}" ''
    systemctl start podman-${n}.service
    trap 'systemctl stop podman-${n}.service' TERM INT
    while systemctl is-active --quiet podman-${n}.service; do sleep 5 & wait $!; done
  '';

  lazymcConfig = n: (pkgs.formats.toml { }).generate "lazymc-${n}.toml" {
    public = {
      address = "0.0.0.0:${toString publicPort.${n}}";
      inherit version protocol;
    };
    server = {
      address = "127.0.0.1:${toString internalPort.${n}}";
      directory = "${dataRoot}/${n}/data";
      command = "${runContainer n}";
      freeze_process = false;
    };
    time.sleep_after = 900;
    advanced.rewrite_server_properties = false;
    config.version = pkgs.lazymc.version;
  };
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
      ports = [ "127.0.0.1:${toString internalPort.minecraft-server}:25565" "24454:24454/udp" ];
      volumes = [ "${dataRoot}/minecraft-server/data:/data" ];
      autoStart = false;
      # Podman's default 10s stop kills the server mid-save.
      extraOptions = [ "--stop-timeout=60" ];
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = version;
        MODRINTH_PROJECTS = "fabric-api,fallingtree,journeymap,appleskin,x-to-xray,lithium,krypton,simple-voice-chat";
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
      ports = [ "127.0.0.1:${toString internalPort.rexburg-friends}:25565" "19132:19132/udp" "24454:24454/udp" ];
      volumes = [ "${dataRoot}/rexburg-friends/data:/data" ];
      autoStart = false;
      # Podman's default 10s stop kills the server mid-save.
      extraOptions = [ "--stop-timeout=60" ];
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = version;
        MODRINTH_PROJECTS = "geyser,floodgate,fabric-api,fallingtree,journeymap,appleskin,x-to-xray,lithium,krypton,simple-voice-chat";
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
      ports = [ "127.0.0.1:${toString internalPort.skyblock}:25565" "19133:19132/udp" ];
      volumes = [ "${dataRoot}/skyblock/data:/data" ];
      autoStart = false;
      # Podman's default 10s stop kills the server mid-save.
      extraOptions = [ "--stop-timeout=60" ];
      environment = {
        EULA = "TRUE";
        TYPE = "PAPER";
        MEMORY = "2G";
        VERSION = version;
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
  })
  # lazymc holds the public port, starts the container when a player joins,
  # and stops it after 15 empty minutes.
  // lib.listToAttrs (map (n: lib.nameValuePair "lazymc-${n}" {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.systemd ];
    serviceConfig = {
      ExecStart = "${pkgs.lazymc}/bin/lazymc start --config ${lazymcConfig n}";
      Restart = "on-failure";
      TimeoutStopSec = 120;
    };
  }) names);

  systemd.tmpfiles.rules = map (n: "d ${dataRoot}/${n}/data 0755 1000 100 -") names;

  networking.firewall.allowedTCPPorts = lib.optionals cfg.public [ cfg.rexburgPort 25566 ];
  networking.firewall.allowedUDPPorts = lib.optionals cfg.public [ 19132 19133 24454 ];
  };
}
