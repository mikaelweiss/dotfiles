# [004] Unify Minecraft backup services

## Objective
Replace the two separate Minecraft backup systemd services and timers with a single service that backs up all three server data directories under `/mnt/nvme/minecraft/` to both remote (oak) and local (USB) restic repos.

## Context
- `configuration.nix:288-315` defines `minecraft-backup` (backs up `/home/mikaelweiss/.minecraft-server/data`).
- `configuration.nix:318-345` defines `rexburg-friends-backup` (backs up `/home/mikaelweiss/.rexburg-friends/data`).
- After the data migration, these paths become `/mnt/nvme/minecraft/minecraft-server/data` and `/mnt/nvme/minecraft/rexburg-friends/data`. The skyblock server adds `/mnt/nvme/minecraft/skyblock/data`.
- The `share-backup` service at `configuration.nix:258-285` is unrelated and stays unchanged.
- Existing backup pattern: restic to `sftp:mikaelweiss@oak:/home/mikaelweiss/backups/<name>-backup`, then forget+prune, then same to `/mnt/backup/<name>-backup` with `|| true` fallback.
- The unified service can back up the entire `/mnt/nvme/minecraft/` tree as a single restic snapshot. This is simpler and allows cross-server restores from one repo. The restic repo names become `minecraft-all-backup` (remote and local).
- Existing separate restic repos (`minecraft-backup`, `rexburg-friends-backup`) on oak and USB remain but will no longer receive new snapshots. Old data is preserved for historical restores.
- The password file at `/etc/restic/password` is shared across all backup services.

## Requirements
1. Remove the `systemd.services.minecraft-backup`, `systemd.timers.minecraft-backup`, `systemd.services.rexburg-friends-backup`, and `systemd.timers.rexburg-friends-backup` blocks from `configuration.nix`.
2. Add a single `systemd.services.minecraft-all-backup` service that:
   - Runs as `User = "mikaelweiss"`, `Nice = 19`, `IOSchedulingClass = "idle"`.
   - Uses `RESTIC_PASSWORD_FILE = "/etc/restic/password"`.
   - Has `pkgs.restic`, `pkgs.openssh`, and `pkgs.podman` on its path.
   - Backs up `/mnt/nvme/minecraft/` to `sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-all-backup`.
   - Runs `restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune` on the remote repo.
   - Backs up `/mnt/nvme/minecraft/` to `/mnt/backup/minecraft-all-backup` with `|| echo "local backup skipped (USB not mounted?)"` fallback.
   - Runs `restic forget` with the same retention policy on the local repo with `|| true` fallback.
3. Add a single `systemd.timers.minecraft-all-backup` timer with `OnCalendar = "daily"`, `RandomizedDelaySec = "15m"`, `Persistent = true`.
4. Initialize the new restic repos before the first backup run:
   - `restic init -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-all-backup`
   - `restic init -r /mnt/backup/minecraft-all-backup` (if USB is mounted)

## Files
- `nixos/configuration.nix` — Modify. Remove two backup services + two timers, add one unified service + timer.

## Test expectations
- `systemctl list-timers` shows `minecraft-all-backup.timer` and does NOT show `minecraft-backup.timer` or `rexburg-friends-backup.timer`.
- `systemctl cat minecraft-all-backup.service` shows the script backing up `/mnt/nvme/minecraft/`.
- Running `sudo systemctl start minecraft-all-backup.service` completes successfully and `restic -r sftp:mikaelweiss@oak:/home/mikaelweiss/backups/minecraft-all-backup snapshots` shows a snapshot containing all three server data dirs.

## Boundaries
- Does NOT delete old restic repos on oak or USB (historical snapshots preserved).
- Does NOT modify the `share-backup` service.
- Does NOT stop or restart any Minecraft containers (restic can back up live data; the servers handle chunk saves independently).
