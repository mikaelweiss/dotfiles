# [005] Public access and post-deploy server setup

## Objective
Configure VPS relay port forwarding for the skyblock server's public access, and provide the complete set of post-deploy in-game commands to set up the hub, permissions, and WorldGuard protection.

## Context
- The VPS relay (`pip`, Tailscale IP `100.80.106.14`) DNATs inbound public traffic to elm's Tailscale IP. Rexburg-friends uses this pattern: public TCP 61658 → elm:61658, public UDP 19132 → elm:19132.
- The skyblock container listens on elm host ports TCP 25566 (Java) and UDP 19133 (Bedrock/Geyser).
- Elm's Tailscale IP can be found in the keepalive timer target or via `tailscale ip -4`.
- The tailscale0 interface is already trusted (`configuration.nix:481`), so no firewall changes are needed on elm for Tailscale traffic.
- If the skyblock server should also accept direct connections from the local LAN or internet (not just via VPS relay), TCP 25566 must be added to `networking.firewall.allowedTCPPorts` in `configuration.nix`.
- BentoBox generates default configs on first load. Key config files after boot:
  - `plugins/BentoBox/config.yml` — main BentoBox config
  - `plugins/BentoBox/addons/BSkyBlock/config.yml` — island size, world settings
  - `plugins/Geyser-Spigot/config.yml` — Bedrock settings (auto-configured by itzg image)
- WorldGuard requires WorldEdit to define regions. Both are installed via MODRINTH_PROJECTS.
- The admin user is `Moroni56` (UUID `dbef463f-9fc5-4b8f-9976-3a4f1aa4b4af`, op level 4).

## Requirements
1. On the VPS (`pip`), add DNAT/forwarding rules for:
   - Inbound TCP on a chosen public port (e.g., 25566) → elm's Tailscale IP:25566
   - Inbound UDP on port 19133 → elm's Tailscale IP:19133
   The exact commands depend on pip's firewall setup (iptables, nftables, or ufw). Document the rules to add.
2. Verify Java players can connect via the VPS public IP on the chosen TCP port.
3. Verify Bedrock players can connect via the VPS public IP on UDP 19133.
4. Run the following in-game commands as Moroni56 (op) to set up the hub:
   - `/gamemode creative` — switch to creative mode for building.
   - Build a 50x50 grass platform at the world spawn (or use WorldEdit: `//pos1`, `//pos2`, `//set grass_block`).
   - `/setworldspawn` — set the server spawn point on the platform.
   - Select the hub area with WorldEdit: `//wand`, click two corners of the 50x50 area (extend 10 blocks above).
   - `/rg define hub` — create a WorldGuard region named `hub`.
   - `/rg flag hub build deny` — prevent building/breaking in the hub.
   - `/rg flag hub pvp deny` — prevent PvP in the hub.
   - `/rg flag hub mob-spawning deny` — prevent mob spawning in the hub.
   - `/rg flag hub interact allow` — allow interacting with signs/buttons in the hub.
   - `/gamemode survival` — switch back to survival.
5. Verify that a non-op player cannot break blocks in the hub region.
6. Verify that `/is` creates a new skyblock island for a player.
7. Verify that `/challenges` opens the challenges GUI.
8. Verify that `/is level` shows island level information.
9. Verify that `/visit` opens the island visit panel.
10. Set up a default LuckPerms group with basic permissions by running:
    - `/lp creategroup default` — create the default group (if not auto-created).
    - `/lp group default permission set essentials.home true`
    - `/lp group default permission set essentials.tpa true`
    - `/lp group default permission set essentials.spawn true`
    - `/lp group default permission set bskyblock.island true` — allows island creation and management.
    - `/lp group default permission set bskyblock.island.create true`

## Files
- `nixos/configuration.nix` — Modify. Add TCP 25566 to `networking.firewall.allowedTCPPorts` if direct LAN/internet access is desired (in addition to VPS relay).

## Test expectations
- Java client connects via VPS public IP on TCP port.
- Bedrock client connects via VPS public IP on UDP 19133.
- Non-op player spawns on the hub platform and cannot break blocks.
- Non-op player runs `/is` and gets a skyblock island with a tree, a chest, and lava/water.
- `/challenges`, `/is level`, `/visit` all function.
- Non-op player visiting another player's island cannot break blocks (visitor protection is BentoBox default).
- Friends added via `/is team invite` can build on the island owner's island.

## Boundaries
- Does NOT customize challenge definitions beyond BentoBox defaults (57 challenges across 5 levels).
- Does NOT customize island schematics beyond BentoBox defaults.
- Does NOT set up a custom scoreboard, tab list, or chat format.
- Does NOT configure an economy shop (EssentialsX provides basic `/worth` and `/sell` but no GUI shop).
