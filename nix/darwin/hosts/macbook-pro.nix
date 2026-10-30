# Work machine.
{ pkgs, ... }:

{
  imports = [ ../youtube-blocker ];

  homebrew.brews = [
    "helix"
    "opencode"
    {
      name = "php@8.2"; # keg-only: brew won't put it on PATH without link
      link = true;
    }
    "tailscale"
    "flyctl"
  ];

  homebrew.casks = [
    "codexbar"
    "opencode-desktop"
    "docker-desktop"
    "harvest"
    "cursor"
    "obsidian"
  ];
}
