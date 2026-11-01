{ pkgs, ... }:

{
  imports = [ ../youtube-blocker ];

  # Builds pika's SD image. The cache serves pika's vendor kernel so the VM never compiles it.
  nix.linux-builder = {
    enable = true;
    ephemeral = true;
    maxJobs = 4;
    config.virtualisation = {
      cores = 4;
      darwin-builder = {
        memorySize = 6 * 1024;
        diskSize = 40 * 1024;
      };
    };
  };
  nix.settings.extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [ "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" ];

  environment.systemPackages = with pkgs; [
    javaPackages.compiler.openjdk25 # Java
    rubyPackages_4_0.cocoapods
  ];

  homebrew.brews = [
    "deno"
    "yt-dlp"
    "python@3.15" # yt-dlp needs it. Without it, cleanup tries to remove it and fails.
    "ffmpeg"
    "flyctl"
  ];

  homebrew.casks = [
    "codexbar"
    "grok-bot"
    "modrinth"
    "obsidian"
    "shottr"
    "signal"
    "conductor"
    "tailscale-app"
    "obs"
  ];
}
