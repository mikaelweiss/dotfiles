{ pkgs, ... }:

{
  imports = [ ../youtube-blocker ];

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
