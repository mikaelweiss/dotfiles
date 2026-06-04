# [003] BentoBox addons and EssentialsX setup script

## Objective
Create a shell script that downloads all 13 BentoBox addons and EssentialsX into the correct locations within the skyblock server data volume, so a single run fully provisions the plugin stack.

## Context
- BentoBox addons are jar files that go in `plugins/BentoBox/addons/`, NOT `plugins/`. The itzg image's `MODRINTH_PROJECTS` only downloads to `plugins/`, so addons must be placed separately.
- BentoBox creates the `plugins/BentoBox/addons/` directory on first boot. The server must be booted once before running this script, so this directory exists at `/mnt/nvme/minecraft/skyblock/data/plugins/BentoBox/addons/`.
- EssentialsX has no Modrinth downloads and blocks Spiget. The latest version (2.22.0 with 26.1.2 support) is at `essentialsx.net/downloads`. The direct download URL is on GitHub releases: `https://github.com/EssentialsX/Essentials/releases`.
- Addon availability by source:

  | Addon | Modrinth slug | GitHub releases fallback |
  |-------|--------------|------------------------|
  | BSkyBlock | `bskyblock` | `BentoBoxWorld/BSkyBlock` |
  | Challenges | `challenges-for-bentobox` | `BentoBoxWorld/Challenges` |
  | Level | `level` | `BentoBoxWorld/Level` |
  | Warps | `warps-for-bentobox` | `BentoBoxWorld/Warps` |
  | Visit | not on Modrinth | `BentoBoxWorld/Visit` |
  | Border | `border` | `BentoBoxWorld/Border` |
  | MagicCobblestoneGenerator | `magic-cobblestone-generator` | `BentoBoxWorld/MagicCobblestoneGenerator` |
  | ExtraMobs | not on Modrinth | `BentoBoxWorld/ExtraMobs` |
  | Bank | `bank-for-bentobox` | `BentoBoxWorld/Bank` |
  | Biomes | `biomes-for-bentobox` | `BentoBoxWorld/Biomes` |
  | Greenhouses | `greenhouses-for-bentobox` | `BentoBoxWorld/Greenhouses` |
  | Likes | not on Modrinth | `BentoBoxWorld/Likes` |
  | Chat | not on Modrinth | `BentoBoxWorld/Chat` |

- TopBlock is only for AOneBlock, not BSkyBlock — it is excluded. The Level addon already provides leaderboard/top-ten for BSkyBlock.
- The Modrinth API can download the latest version of a project: `https://api.modrinth.com/v2/project/{slug}/version?game_versions=["26.1.2"]&loaders=["paper"]` returns version metadata including download URLs.
- The GitHub API returns latest release assets: `https://api.github.com/repos/BentoBoxWorld/{addon}/releases/latest`.
- The script uses `curl` and `jq` (both available on the host via system packages at `configuration.nix:81-124`).

## Requirements
1. Create a shell script at `/mnt/nvme/minecraft/skyblock/setup-addons.sh`.
2. The script accepts no arguments. It is idempotent — running it again overwrites existing addon jars with the latest versions.
3. The script sets two target directories:
   - `ADDONS_DIR="/mnt/nvme/minecraft/skyblock/data/plugins/BentoBox/addons"`
   - `PLUGINS_DIR="/mnt/nvme/minecraft/skyblock/data/plugins"`
4. The script verifies both directories exist and exits with an error if they do not (meaning the server has not been booted once yet).
5. For each Modrinth-hosted addon (BSkyBlock, Challenges, Level, Warps, Border, MagicCobblestoneGenerator, Bank, Biomes, Greenhouses), the script:
   - Queries the Modrinth API for the latest compatible version.
   - Downloads the jar file to `$ADDONS_DIR`.
6. For each GitHub-only addon (Visit, ExtraMobs, Likes, Chat), the script:
   - Queries the GitHub releases API for the latest release.
   - Downloads the first `.jar` asset to `$ADDONS_DIR`.
7. For EssentialsX, the script:
   - Queries `https://api.github.com/repos/EssentialsX/Essentials/releases/latest`.
   - Downloads the `EssentialsX-*.jar` asset (not EssentialsXChat, EssentialsXSpawn, etc. — only the core jar) to `$PLUGINS_DIR`.
8. The script prints a summary of all downloaded files with their versions.
9. After running the script, the skyblock container is restarted and logs are checked to verify all addons load.

## Files
- `/mnt/nvme/minecraft/skyblock/setup-addons.sh` — Create. Shell script that downloads all BentoBox addons and EssentialsX.

## Test expectations
- Running `bash /mnt/nvme/minecraft/skyblock/setup-addons.sh` completes without errors.
- `ls /mnt/nvme/minecraft/skyblock/data/plugins/BentoBox/addons/` shows 13 addon jars.
- `ls /mnt/nvme/minecraft/skyblock/data/plugins/EssentialsX*.jar` shows the EssentialsX core jar.
- After container restart, `podman logs skyblock` shows BentoBox loading all 13 addons and EssentialsX loading.
- In-game, `/challenges` opens the challenges GUI, `/is level` shows island level, `/visit` opens the visit panel.

## Boundaries
- Does NOT configure addon settings (default configs are generated on first load and work out of the box).
- Does NOT set up LuckPerms groups or WorldGuard regions.
- Does NOT modify `configuration.nix`.
