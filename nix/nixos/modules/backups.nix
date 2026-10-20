{ config, pkgs, lib, ... }:

let
  cfg = config.resticBackups;
  oak = "rest:http://oak:8000";
  keep = "--keep-daily 7 --keep-weekly 4 --keep-monthly 6";
  stateDir = "/var/backup/sparrow-state";

  dailyTimer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  baseService = { description, extraPath ? [ ], preStart ? null, scriptBody }: {
    inherit description;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mikaelweiss";
      Nice = 19;
      IOSchedulingClass = "idle";
      # RESTIC_REST_USERNAME and RESTIC_REST_PASSWORD for this host's login on oak.
      EnvironmentFile = "/etc/restic/rest-env";
    } // lib.optionalAttrs (preStart != null) { ExecStartPre = "+${preStart}"; };
    environment.RESTIC_PASSWORD_FILE = "/etc/restic/password";
    path = [ pkgs.restic ] ++ extraPath;
    script = scriptBody;
  };

  # A remote (oak) repo, plus an optional local USB mirror that is skipped when
  # the drive is not mounted. oak is append-only, so a hacked client can add
  # snapshots but never delete them, and oak prunes its repos itself.
  resticTo = { repo, path, localRepo ? null }: ''
    restic -r ${oak}/${repo} cat config >/dev/null 2>&1 || restic -r ${oak}/${repo} init
    restic -r ${oak}/${repo} backup --retry-lock 2h ${path}
  '' + lib.optionalString (localRepo != null) ''
    if mountpoint -q /mnt/backup; then
      restic -r ${localRepo} cat config >/dev/null 2>&1 || restic -r ${localRepo} init
      restic -r ${localRepo} backup ${path}
      restic -r ${localRepo} forget ${keep} --prune
    fi
  '';

  stageState = pkgs.writeShellScript "stage-sparrow-state" ''
    set -euo pipefail
    rm -rf ${stateDir}
    install -d -m 700 -o mikaelweiss ${stateDir} ${stateDir}/etc
    ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/pg_dumpall > ${stateDir}/pg_dumpall.sql
    for d in portfolio weisssolutions lunchninja asher parlance cloudflared cloudflare restic webhook; do
      [ -d /etc/$d ] && cp -a /etc/$d ${stateDir}/etc/
    done
    [ -d /var/lib/parlance/backups ] && cp -a /var/lib/parlance/backups ${stateDir}/parlance
    chown -R mikaelweiss ${stateDir}
  '';
in
{
  options.resticBackups = {
    minecraftPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Minecraft data dir to back up, or null to skip.";
    };
    sparrowState = lib.mkEnableOption "Postgres + site-secret backup";
    server = lib.mkEnableOption "the append-only repo server the other hosts back up to";
  };

  config = lib.mkMerge [
  (lib.mkIf cfg.server {
    services.restic.server = {
      enable = true;
      appendOnly = true;
    };

    systemd.services.restic-prune = {
      description = "Prune the append-only repos";
      serviceConfig = {
        Type = "oneshot";
        User = "restic";
        Nice = 19;
        IOSchedulingClass = "idle";
        LoadCredential = "password:/etc/restic/password";
      };
      path = [ pkgs.restic ];
      script = ''
        export RESTIC_PASSWORD_FILE=$CREDENTIALS_DIRECTORY/password
        for repo in ${config.services.restic.server.dataDir}/*/; do
          if [ -f "$repo/config" ]; then
            restic -r "$repo" --no-cache forget ${keep} --prune
          fi
        done
      '';
    };
    systemd.timers.restic-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 04:00";
        Persistent = true;
      };
    };
  })
  {
    systemd.services = lib.mkMerge [
      (lib.mkIf (cfg.minecraftPath != null) {
        minecraft-all-backup = lib.recursiveUpdate (baseService {
          description = "Restic backup of all Minecraft server data";
          extraPath = [ pkgs.util-linux ];
          scriptBody = resticTo {
            repo = "minecraft-all-backup";
            path = cfg.minecraftPath;
            localRepo = "/mnt/backup/minecraft-all-backup";
          };
        }) {
          # The servers write some world files readable only by the minecraft user.
          serviceConfig.AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
        };
      })
      (lib.mkIf cfg.sparrowState {
        sparrow-state-backup = baseService {
          description = "Restic backup of Postgres dump and site secrets";
          preStart = stageState;
          scriptBody = resticTo { repo = "sparrow-state"; path = "${stateDir} /var/lib/asher/uploads"; };
        };
      })
    ];

    systemd.timers = lib.mkMerge [
      (lib.mkIf (cfg.minecraftPath != null) { minecraft-all-backup = dailyTimer; })
      (lib.mkIf cfg.sparrowState { sparrow-state-backup = dailyTimer; })
    ];
  }
  ];
}
