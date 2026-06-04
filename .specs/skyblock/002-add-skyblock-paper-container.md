# [002] Add skyblock Paper server container

## Objective
Add a new Paper-based Minecraft server container to `configuration.nix` with BentoBox, Geyser/Floodgate, and all core infrastructure plugins auto-downloaded via `MODRINTH_PROJECTS`.

## Context
- The `itzg/minecraft-server` image supports `TYPE=PAPER` natively — same image, different env var. For Paper servers, `MODRINTH_PROJECTS` downloads plugins to `/data/plugins/`.
- Existing containers use `docker.io/itzg/minecraft-server:java25` at `configuration.nix:407-478`.
- Host port 25565 is taken by `minecraft-server`, 61658 by `rexburg-friends`, UDP 19132 by rexburg-friends Geyser. Skyblock uses TCP 25566 (Java) and UDP 19133 mapped to container's 19132 (Geyser default Bedrock port).
- Data lives at `/mnt/nvme/minecraft/skyblock/data`. The parent `/mnt/nvme/minecraft/` must exist (created during the data migration).
- The existing ops from `rexburg-friends` (`Moroni56`, UUID `dbef463f-9fc5-4b8f-9976-3a4f1aa4b4af`) should be opped on this server too for admin access.
- EssentialsX has no downloadable versions on Modrinth and blocks Spiget automated downloads. It must be downloaded manually from `essentialsx.net/downloads` and placed in the data volume at `plugins/EssentialsX-*.jar`. A separate setup script handles this.
- VaultUnlocked (Modrinth slug `vaultunlocked`) is the maintained Vault fork with 26.1 support — it replaces the original Vault.
- `ENFORCE_SECURE_PROFILE = "false"` is required for Bedrock players (they cannot sign Java secure chat messages).
- `PAUSE_WHEN_EMPTY_SECONDS = "0"` is required because tunneled connections through the VPS relay do not wake a paused server.

## Requirements
1. Create the directory `/mnt/nvme/minecraft/skyblock/data/` (owned by UID 1000, GID 100).
2. Add a new container `skyblock` to `virtualisation.oci-containers.containers` in `configuration.nix` with:
   - `image = "docker.io/itzg/minecraft-server:java25"`
   - `ports = [ "25566:25565" "19133:19132/udp" ]`
   - `volumes = [ "/mnt/nvme/minecraft/skyblock/data:/data" ]`
   - `autoStart = true`
3. Set the following environment variables on the container:
   - `EULA = "TRUE"`
   - `TYPE = "PAPER"`
   - `MEMORY = "2G"`
   - `VERSION = "26.1.2"`
   - `MODRINTH_PROJECTS = "bentobox,luckperms,vaultunlocked,placeholderapi,worldedit,worldguard,coreprotect,geyser,floodgate"`
   - `MODRINTH_ALLOWED_VERSION_TYPE = "beta"` (some plugins only have beta builds for 26.1)
   - `ENFORCE_SECURE_PROFILE = "false"`
   - `PAUSE_WHEN_EMPTY_SECONDS = "0"`
   - `UID = "1000"`
   - `GID = "100"`
   - `MOTD = "SkyBlock"`
   - `ENABLE_WHITELIST = "FALSE"` (public server)
   - `MAX_PLAYERS = "50"`
   - `DIFFICULTY = "normal"`
   - `SPAWN_PROTECTION = "0"` (WorldGuard handles spawn protection instead)
   - `ALLOW_FLIGHT = "true"` (BentoBox IslandFly and creative mode need this)
4. Run `sudo nixos-rebuild switch --flake /home/mikaelweiss/code/dotfiles/nixos#elm`.
5. Verify the container starts and all Modrinth plugins download successfully by checking container logs (`podman logs skyblock`).
6. After first successful boot, stop the container and place an `ops.json` file in `/mnt/nvme/minecraft/skyblock/data/` granting op level 4 to `Moroni56` (UUID `dbef463f-9fc5-4b8f-9976-3a4f1aa4b4af`).
7. Restart the container and verify op status works by joining and running `/gamemode creative`.

## Files
- `nixos/configuration.nix` — Modify. Add the `skyblock` container definition inside `virtualisation.oci-containers.containers`.

## Test expectations
- Container starts and stays running (`podman ps` shows `skyblock`).
- Container logs show all 9 Modrinth plugins downloading and loading.
- Paper server binds on port 25565 inside the container (mapped to host 25566).
- Geyser starts and binds Bedrock on port 19132 inside the container (mapped to host 19133).
- A Java client can connect to `localhost:25566` (or `elm:25566` over Tailscale).
- Admin user Moroni56 can join and use `/gamemode creative`.

## Boundaries
- Does NOT install BentoBox addons (they require a subdirectory, not `plugins/`).
- Does NOT install EssentialsX (requires manual download).
- Does NOT configure VPS relay port forwarding.
- Does NOT configure WorldGuard regions or LuckPerms groups (done post-deploy).
