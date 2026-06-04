# [001] Migrate Minecraft server data to /mnt/nvme

## Objective
Move both existing Minecraft server data directories from the root disk to `/mnt/nvme/minecraft/` and reduce rexburg-friends memory from 4G to 2G, freeing root disk space and RAM for the new skyblock server.

## Context
- Root disk is 93% full (`/dev/nvme1n1p2`, 468G, 36G free). `/mnt/nvme` has 445G free on a separate NVMe (`/dev/nvme0n1p1`, ext4).
- `configuration.nix:407-478` defines two `oci-containers`: `minecraft-server` (volume `/home/mikaelweiss/.minecraft-server/data:/data`) and `rexburg-friends` (volume `/home/mikaelweiss/.rexburg-friends/data:/data`).
- `configuration.nix:288-345` defines three separate backup services that reference the old paths.
- Both containers must be stopped before data moves. Podman containers are managed by systemd units `podman-minecraft-server.service` and `podman-rexburg-friends.service`.
- The rexburg-friends container currently has `MEMORY = "4G"` at `configuration.nix:453`.

## Requirements
1. Stop both Minecraft containers before any data is moved.
2. Create the directory structure `/mnt/nvme/minecraft/minecraft-server/data/` and `/mnt/nvme/minecraft/rexburg-friends/data/`.
3. Copy (rsync with `--archive --hard-links --partial`) the data from `/home/mikaelweiss/.minecraft-server/data/` to `/mnt/nvme/minecraft/minecraft-server/data/` and from `/home/mikaelweiss/.rexburg-friends/data/` to `/mnt/nvme/minecraft/rexburg-friends/data/`.
4. Update `configuration.nix` container `minecraft-server` volume to `"/mnt/nvme/minecraft/minecraft-server/data:/data"`.
5. Update `configuration.nix` container `rexburg-friends` volume to `"/mnt/nvme/minecraft/rexburg-friends/data:/data"`.
6. Change `rexburg-friends` `MEMORY` from `"4G"` to `"2G"`.
7. Update all three existing backup service scripts (`minecraft-backup`, `rexburg-friends-backup`) to reference the new `/mnt/nvme/minecraft/` paths. The `share-backup` service is unrelated and stays unchanged.
8. Run `sudo nixos-rebuild switch --flake /home/mikaelweiss/code/dotfiles/nixos#elm` and verify both containers start and are joinable.
9. After verifying both servers work with the new paths, remove the old data directories (`/home/mikaelweiss/.minecraft-server/` and `/home/mikaelweiss/.rexburg-friends/`).

## Files
- `nixos/configuration.nix` — Modify. Change volume paths for both containers, reduce rexburg-friends memory, update backup service script paths.

## Test expectations
- Both containers start successfully after rebuild.
- Players can join both servers and their worlds/inventory are intact.
- `ls /mnt/nvme/minecraft/minecraft-server/data/world/` and `ls /mnt/nvme/minecraft/rexburg-friends/data/world/` show world data.
- Backup services reference the new paths (inspect with `systemctl cat minecraft-backup.service`).

## Boundaries
- Does NOT add the skyblock container.
- Does NOT unify backup services into one (keeps them separate for now).
- Does NOT modify firewall rules or VPS relay configuration.
