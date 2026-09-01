{ config, pkgs, lib, ... }:

let
  cfg = config.resticBackups;
  oak = "sftp:mikaelweiss@oak:/home/mikaelweiss/backups";
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
    } // lib.optionalAttrs (preStart != null) { ExecStartPre = "+${preStart}"; };
    environment.RESTIC_PASSWORD_FILE = "/etc/restic/password";
    path = [ pkgs.restic pkgs.openssh ] ++ extraPath;
    script = scriptBody;
  };

  # A remote (oak) repo, plus an optional local USB mirror that is skipped when
  # the drive is not mounted.
  resticTo = { repo, path, localRepo ? null }: ''
    restic -r ${oak}/${repo} cat config >/dev/null 2>&1 || restic -r ${oak}/${repo} init
    restic -r ${oak}/${repo} backup ${path}
    restic -r ${oak}/${repo} forget ${keep} --prune
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
    for d in portfolio weisssolutions lunchninja cloudflared cloudflare restic webhook; do
      [ -d /etc/$d ] && cp -a /etc/$d ${stateDir}/etc/
    done
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
  };

  config = {
    systemd.services = lib.mkMerge [
      (lib.mkIf (cfg.minecraftPath != null) {
        minecraft-all-backup = baseService {
          description = "Restic backup of all Minecraft server data";
          extraPath = [ pkgs.util-linux ];
          scriptBody = resticTo {
            repo = "minecraft-all-backup";
            path = cfg.minecraftPath;
            localRepo = "/mnt/backup/minecraft-all-backup";
          };
        };
      })
      (lib.mkIf cfg.sparrowState {
        sparrow-state-backup = baseService {
          description = "Restic backup of Postgres dump and site secrets";
          preStart = stageState;
          scriptBody = resticTo { repo = "sparrow-state"; path = stateDir; };
        };
      })
    ];

    systemd.timers = lib.mkMerge [
      (lib.mkIf (cfg.minecraftPath != null) { minecraft-all-backup = dailyTimer; })
      (lib.mkIf cfg.sparrowState { sparrow-state-backup = dailyTimer; })
    ];
  };
}
