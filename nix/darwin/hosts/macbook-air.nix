{ ... }:

{
  imports = [ ../youtube-blocker ];

  homebrew.brews = [
    "deno"
    "yt-dlp"
    "python@3.15" # yt-dlp needs it. Without it, cleanup tries to remove it and fails.
    "yutu"
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
