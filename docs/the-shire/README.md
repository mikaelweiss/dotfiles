# The Shire

Two mods on the Shire do not come from Modrinth: a patched Geyser and Requisition.

## Geyser with split screen

Upstream Geyser kicks a whole console when a second split-screen player joins. The log shows `Client tried to send unused packet SubClientLoginPacket!`. `nix/nixos/modules/geyser-splitscreen.patch` adds split screen to one pinned Geyser commit. It is [GeyserMC/Geyser#6689](https://github.com/GeyserMC/Geyser/pull/6689), moved onto Geyser's newer login code.

How it reaches the server, all in `nix/nixos/modules/minecraft.nix`:

- `geyserSource` pins the Geyser commit and applies the patch.
- The `geyser-splitscreen` service builds the jar on sparrow into `/var/lib/geyser-splitscreen/`, once per commit and patch. Gradle downloads Minecraft while it builds, so it cannot run in the Nix sandbox.
- The Shire's `preStart` copies the jar to `mods/Geyser-Fabric-splitscreen.jar`. `geyser` stays out of `MODRINTH_PROJECTS`.

### Updating

Switches update Bedrock on their own. Until the server's Geyser supports the new version, Bedrock players get an "outdated server" kick and nobody on Bedrock can join. Once [Geyser](https://geysermc.org/download) supports it:

1. Apply the patch to the latest Geyser:
   ```bash
   git clone --recurse-submodules https://github.com/GeyserMC/Geyser && cd Geyser
   git apply --3way ~/code/dotfiles/nix/nixos/modules/geyser-splitscreen.patch
   ```
2. Resolve any conflicts, then run `./gradlew :core:test`.
3. Save the patch: `git add -A && git diff --cached > ~/code/dotfiles/nix/nixos/modules/geyser-splitscreen.patch`
4. In `minecraft.nix`, set `rev` to `git rev-parse HEAD` and `hash` to `lib.fakeHash`. The first rebuild fails and prints the right hash after `got:`. Paste it in.
5. Commit, push, `git pull` on sparrow, then `nix-rebuild` there while nobody is online. That start builds Geyser for a few minutes before the server comes up.

### When Geyser merges split screen

Watch [#6689](https://github.com/GeyserMC/Geyser/pull/6689) and the issue [#750](https://github.com/GeyserMC/Geyser/issues/750). Once a Geyser release supports split screen:

1. Add `geyser` back to the Shire's `MODRINTH_PROJECTS`.
2. Delete `geyserSource`, `geyserJar`, the `geyser-splitscreen` service, the Shire's `requires` and `after` on it, the jar line in its `preStart`, and the patch file.
3. `nix-rebuild`, then delete `mods/Geyser-Fabric-splitscreen.jar` on sparrow. Nothing else removes it, and two Geysers will not start.

### New split-screen players

The log shows what the console sent for each guest:

```
Split-screen: sub-client joining in slot 1 behind <host> - xuid=..., displayName=...
```

When the console sends no xuid, the patch makes a stable one from the host's xuid and the controller slot. That guest is new to the whitelist. Floodgate's UUID for them is `00000000-0000-0000-` plus the xuid in hex, padded to 16 digits. Add it with the name to `data/whitelist.json`, then run `podman exec the-shire rcon-cli whitelist reload`.

## Requisition

Mikael's own mod, built from `~/code/minecraft-mods/requisition` and not published anywhere. The jar is copied into `mods/` by hand. Nix does not manage it and the Modrinth sync ignores it, so it survives restarts and rebuilds.

It must match the Shire's Minecraft `version` in `minecraft.nix`. To update it, build on the Mac, then install on sparrow while nobody is online:

```bash
cd ~/code/minecraft-mods/requisition && ./gradlew build
scp build/libs/requisition-<new>.jar sparrow:/tmp/
ssh sparrow
sudo install -m 0644 -o minecraft -g minecraft /tmp/requisition-<new>.jar /var/lib/minecraft/the-shire/data/mods/
sudo rm /var/lib/minecraft/the-shire/data/mods/requisition-<old>.jar
sudo systemctl restart podman-the-shire
```
