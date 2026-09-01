{ config, pkgs, lib, ... }:

let
  oak = "sftp:mikaelweiss@oak:/home/mikaelweiss/backups";
  keep = "--keep-daily 7 --keep-weekly 4 --keep-monthly 6";
  stateDir = "/var/backup/sparrow-state";

  backupUnit = { description, repo, path, preStart ? null }: {
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
    path = [ pkgs.restic pkgs.openssh ];
    script = ''
      restic -r ${repo} cat config >/dev/null 2>&1 || restic -r ${repo} init
      restic -r ${repo} backup ${path}
      restic -r ${repo} forget ${keep} --prune
    '';
  };

  dailyTimer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

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
  systemd.services.minecraft-all-backup = backupUnit {
    description = "Restic backup of all Minecraft server data";
    repo = "${oak}/minecraft-all-backup";
    path = "/var/lib/minecraft";
  };
  systemd.timers.minecraft-all-backup = dailyTimer;

  systemd.services.sparrow-state-backup = backupUnit {
    description = "Restic backup of Postgres dump and site secrets";
    repo = "${oak}/sparrow-state";
    path = stateDir;
    preStart = stageState;
  };
  systemd.timers.sparrow-state-backup = dailyTimer;
}
