{ config, pkgs, lib, ... }:

let
  cfg = config.minecraft;
  dataRoot = cfg.dataRoot;
  names = lib.optional cfg.private "minecraft-server"
    ++ lib.optionals cfg.public [ "rexburg-friends" "skyblock" ]
    ++ lib.optional cfg.shire "the-shire";

  version = "26.1.2";
  protocol = 775;
  publicPort = { minecraft-server = 25565; rexburg-friends = cfg.rexburgPort; skyblock = 25566; the-shire = 25567; };
  internalPort = { minecraft-server = 35565; rexburg-friends = 35566; skyblock = 35567; the-shire = 35568; };
  uid = 25565;
  units = map (n: "podman-${n}.service") names;

  runContainer = n: pkgs.writeShellScript "run-${n}" ''
    systemctl start podman-${n}.service
    trap 'systemctl stop podman-${n}.service' TERM INT
    while systemctl is-active --quiet podman-${n}.service; do sleep 5 & wait $!; done
  '';

  # Nothing in the container runs as root, so an escape lands on an account
  # with no sudo. Podman's default 10s stop kills the server mid-save.
  containerOptions = [ "--stop-timeout=60" "--cap-drop=ALL" "--security-opt=no-new-privileges" ];

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
    shire = lib.mkEnableOption "the port-forwarded the-shire server";
  };

  imports = [ ./dmz.nix ];

  config = {
  users.users.minecraft = {
    isSystemUser = true;
    inherit uid;
    group = "minecraft";
  };
  users.groups.minecraft.gid = uid;
  dmz.users = [ "minecraft" ];

  # lazymc runs as minecraft and may only start and stop its own containers.
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "minecraft"
          && ${builtins.toJSON units}.indexOf(action.lookup("unit")) >= 0
          && ["start", "stop"].indexOf(action.lookup("verb")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

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
      user = "${toString uid}:${toString uid}";
      extraOptions = containerOptions;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = version;
        MODRINTH_PROJECTS = "fabric-api,fallingtree,journeymap,appleskin,x-to-xray,lithium,krypton,simple-voice-chat";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
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
      user = "${toString uid}:${toString uid}";
      extraOptions = containerOptions;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "2G";
        VERSION = version;
        MODRINTH_PROJECTS = "geyser,floodgate,fabric-api,fallingtree,journeymap,appleskin,x-to-xray,lithium,krypton,simple-voice-chat";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        ENFORCE_SECURE_PROFILE = "false";
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
      user = "${toString uid}:${toString uid}";
      extraOptions = containerOptions;
      environment = {
        EULA = "TRUE";
        TYPE = "PAPER";
        MEMORY = "2G";
        VERSION = version;
        MODRINTH_PROJECTS = "luckperms,vaultunlocked,placeholderapi,worldedit,worldguard,geyser,journeymap";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        ENFORCE_SECURE_PROFILE = "false";
        PAUSE_WHEN_EMPTY_SECONDS = "0";
        MOTD = "SkyBlock";
        MAX_PLAYERS = "50";
        DIFFICULTY = "normal";
        SPAWN_PROTECTION = "0";
        ALLOW_FLIGHT = "true";
      };
    };
    })
    (lib.mkIf cfg.shire {
    the-shire = {
      image = "docker.io/itzg/minecraft-server:java25";
      ports = [ "127.0.0.1:${toString internalPort.the-shire}:25565" "19134:19132/udp" "24455:24454/udp" ];
      volumes = [ "${dataRoot}/the-shire/data:/data" ];
      autoStart = false;
      user = "${toString uid}:${toString uid}";
      extraOptions = containerOptions;
      environment = {
        EULA = "TRUE";
        TYPE = "FABRIC";
        MEMORY = "4G";
        VERSION = version;
        MODRINTH_PROJECTS = "geyser,floodgate,fabric-api,fallingtree,journeymap,appleskin,x-to-xray,lithium,krypton,simple-voice-chat";
        MODRINTH_ALLOWED_VERSION_TYPE = "beta";
        ENFORCE_SECURE_PROFILE = "false";
        MOTD = "The Shire";
        PAUSE_WHEN_EMPTY_SECONDS = "0";
        ENABLE_WHITELIST = "TRUE";
        WHITELIST = "Moroni56,hogtide";
        OPS = "Moroni56";
      };
    };
    })
    ];
  };

  systemd.services = lib.mkMerge [
  # Podman pulls the image on first start, which raced DNS at boot.
  (lib.genAttrs (map (n: "podman-${n}") names) (_: {
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
      User = "minecraft";
      Group = "minecraft";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };
  }) names))
  # elm's private server holds voice chat's 24454, so clients must be told the
  # forwarded port. The mod rewrites its config, so this sets it on every start.
  (lib.mkIf cfg.shire {
    podman-the-shire.preStart = ''
      conf=${dataRoot}/the-shire/data/config/voicechat/voicechat-server.properties
      if [ -f "$conf" ]; then
        ${pkgs.gnused}/bin/sed -i 's/^voice_host=.*/voice_host=shire.mikaelmc.com:24455/' "$conf"
      fi
    '';
  })
  ];

  systemd.tmpfiles.rules = map (n: "d ${dataRoot}/${n}/data 0770 minecraft minecraft -") names;

  networking.firewall.allowedTCPPorts = lib.optionals cfg.public [ cfg.rexburgPort 25566 ]
    ++ lib.optional cfg.shire 25567;
  networking.firewall.allowedUDPPorts = lib.optionals cfg.public [ 19132 19133 24454 ]
    ++ lib.optionals cfg.shire [ 19134 24455 ];
  };
}
