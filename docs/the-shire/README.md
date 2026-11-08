# The Shire

Two mods on the Shire do not come from Modrinth: a patched Geyser and Requisition.

## Restarting the Shire

The Shire is always on and friends play on it. Restart it, or `nix-rebuild` sparrow when the Shire's config changed, only when nobody is online:

```bash
ssh sparrow 'sudo podman exec the-shire rcon-cli list'
```

From a non-interactive shell, run `zsh -ic nix-rebuild` on sparrow and keep that ssh session open until it ends. Killing it mid-switch aborts the switch.

The server runs in a container, `podman-the-shire`. Its log is `journalctl -u podman-the-shire`, and its files are in `/var/lib/minecraft/the-shire/data`.

## Geyser with split screen

Upstream Geyser kicks a whole console when a second split-screen player joins. The log shows `Client tried to send unused packet SubClientLoginPacket!`. `nix/nixos/modules/geyser-splitscreen.patch` adds split screen to one pinned Geyser commit. It is [GeyserMC/Geyser#6689](https://github.com/GeyserMC/Geyser/pull/6689), moved onto Geyser's newer login code, plus two fixes a Switch needs that #6689 lacks:

- **Guest ID.** A Switch sends the host's own xuid for the guest. Taken as is, Geyser sees the host joining twice and kicks the guest. The patch treats the host's xuid like a missing one (`resolveSubClientAuthData` in `LoginEncryptionUtils`).
- **Kick message.** #6689 drops a kicked guest without telling the console, so the guest's screen hangs on "building terrain" whatever the reason. The patch sends the guest a disconnect first (`GeyserSession#disconnect`). It sends nothing when the guest left on its own.

The patch's own tests are `LoginPacketHandlerTest`, `SplitScreenIdentityTest` and `UpstreamSessionTest`.

How it reaches the server, all in `nix/nixos/modules/minecraft.nix`:

- `geyserSource` pins the Geyser commit and applies the patch.
- The `geyser-splitscreen` service builds the jar on sparrow into `/var/lib/geyser-splitscreen/`, once per commit and patch. Gradle downloads Minecraft while it builds, so it cannot run in the Nix sandbox.
- The Shire's `preStart` copies the jar to `mods/Geyser-Fabric-splitscreen.jar`. `geyser` stays out of `MODRINTH_PROJECTS`.

### Updating

Update when Bedrock or the Shire's Minecraft `version` changes. Switches update Bedrock on their own. Until the server's Geyser supports the new version, Bedrock players get an "outdated server" kick and nobody on Bedrock can join. The jar is also built for one Minecraft version. Once [Geyser](https://geysermc.org/download) supports both:

1. Apply the patch to the latest Geyser:
   ```bash
   git clone --recurse-submodules https://github.com/GeyserMC/Geyser && cd Geyser
   git apply --3way ~/code/dotfiles/nix/nixos/modules/geyser-splitscreen.patch
   ```
2. Resolve any conflicts, then run `./gradlew :core:test`.
3. Save the patch: `git add -A && git diff --cached > ~/code/dotfiles/nix/nixos/modules/geyser-splitscreen.patch`
4. In `minecraft.nix`, set `rev` to `git rev-parse HEAD` and `hash` to `lib.fakeHash`. The first rebuild fails and prints the right hash after `got:`. Paste it in.
5. Commit, push, and `git pull` on sparrow.
6. Build the jar while people still play, so the restart takes a minute instead of five. Run it under its own unit name: units in `/etc` outrank `/run`, so a copy named `geyser-splitscreen` would run the old unit.
   ```bash
   T=$(nix build --no-link --print-out-paths ~/code/dotfiles/nix#nixosConfigurations.sparrow.config.system.build.toplevel)
   sudo cp $(readlink -f $T/etc/systemd/system/geyser-splitscreen.service) /run/systemd/system/geyser-splitscreen-prebuild.service
   sudo systemctl daemon-reload && sudo systemctl restart geyser-splitscreen-prebuild
   ```
   Wait for it to finish, then delete `/run/systemd/system/geyser-splitscreen-prebuild.service` and `daemon-reload`.
7. `nix-rebuild` on sparrow while nobody is online.

### When Geyser merges split screen

Watch [#6689](https://github.com/GeyserMC/Geyser/pull/6689) and the issue [#750](https://github.com/GeyserMC/Geyser/issues/750). Check that the merged version has both Switch fixes above, or Switch guests break again. Once a Geyser release does:

1. Add `geyser` back to the Shire's `MODRINTH_PROJECTS`.
2. Delete `geyserSource`, `geyserJar`, the `geyser-splitscreen` service, the Shire's `wants` and `after` on it, the jar line in its `preStart`, and the patch file.
3. `nix-rebuild`, then delete `mods/Geyser-Fabric-splitscreen.jar` on sparrow. Nothing else removes it, and two Geysers will not start.

### New split-screen players

The log shows what the console sent for each guest:

```
Split-screen: sub-client joining in slot 1 behind <host> - xuid=..., displayName=...
```

When the console sends no xuid, or the host's, the patch makes a stable one from the host's xuid and the controller slot, and names the guest after the host, such as `fussypenny388_P2`. That guest is new to the whitelist and gets kicked with "You are not white-listed". The log then shows Floodgate's UUID and name for them:

```
Floodgate player who is logged in as .fussypenny388_P 00000000-0000-0000-1b29-d45066c09e32 joined
```

`/fwhitelist add` cannot find a guest, since it looks the name up on Xbox. Add the UUID and name to `/var/lib/minecraft/the-shire/data/whitelist.json`, then run `sudo podman exec the-shire rcon-cli whitelist reload`. No restart is needed.

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
