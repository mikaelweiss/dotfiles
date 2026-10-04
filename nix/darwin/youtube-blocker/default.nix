# Blocks YouTube and social media after 30 minutes of combined use per day.
# The user agent counts time. The root daemon enforces the limit in /etc/hosts.
{ pkgs, ... }:

let
  youtubeUnblock = builtins.replaceStrings [ "@enforce@" ] [ "${./enforce.sh}" ]
    (builtins.readFile ./youtube-unblock);
in
{
  environment.systemPackages = [
    (pkgs.writeScriptBin "youtube-time" (builtins.readFile ./youtube-time))
    (pkgs.writeScriptBin "youtube-unblock" youtubeUnblock)
  ];

  # Run through /bin/bash: macOS grants the Automation permission to control
  # the browsers to /bin/bash, and a nix bash would need a fresh grant after
  # every update.
  launchd.user.agents.youtube-blocker-agent.serviceConfig = {
    ProgramArguments = [ "/bin/bash" "${./check-youtube.sh}" ];
    StartInterval = 15;
    RunAtLoad = true;
    StandardErrorPath = "/Users/mikaelweiss/Library/Logs/YouTubeBlocker-agent.log";
  };

  launchd.daemons.youtube-blocker-enforce.serviceConfig = {
    ProgramArguments = [ "/bin/bash" "${./enforce.sh}" ];
    StartInterval = 30;
    RunAtLoad = true;
    StandardErrorPath = "/Library/Logs/YouTubeBlocker-daemon.log";
  };
}
