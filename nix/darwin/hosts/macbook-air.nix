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
    "ffmpeg"
    "flyctl"
  ];

  homebrew.casks = [
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
