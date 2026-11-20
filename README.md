# Dotfiles

This is a place for all things config.
From here I will be able run a script and set up my computer with everything I need.

To set up wolf, the Mac mini, run this on it. It checks every piece at the
end, and rerunning it repairs whatever failed:

```
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/MikaelWeiss/dotfiles/main/setup/wolf)"
```

On any other Mac, clone this repo to `~/code/dotfiles` and run
`mkdir -p ~/.gemini/config && stow agents claude codex gemini git terminal` from it.

## Nix

One flake in `nix/` covers every machine. `nix-config` opens
`nix/shared.nix`, the file for anything that should exist everywhere:
packages, and global npm packages under `npm.globalPackages`. Mac-only
things (homebrew) live in `nix/darwin/common.nix`, apps for the Macs
with a screen live in `nix/darwin/desktop.nix`, and one machine's
extras live in `nix/darwin/hosts/` or `nix/nixos/hosts/`. `nix-rebuild`
applies it.
