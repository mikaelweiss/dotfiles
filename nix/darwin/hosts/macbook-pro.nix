# Work machine.
{ pkgs, ... }:

{
  # surestake CI runs node 22, and the Analog vitest pool aborts under nix node 24.
  node.package = pkgs.nodejs_22;

  homebrew.brews = [
    "helix"
    "opencode"
    {
      name = "php@8.2"; # keg-only: brew won't put it on PATH without link
      link = true;
    }
    "tailscale"
  ];

  homebrew.casks = [
    "opencode-desktop"
    "docker-desktop"
    "harvest"
    "cursor"
    "obsidian"
  ];
}
