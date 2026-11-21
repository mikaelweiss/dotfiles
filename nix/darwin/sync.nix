# Every Mac runs its own mutagen daemon with sessions to elm, the hub
# (see terminal/bin/sync-setup). A system daemon rather than a user agent,
# so syncing starts before anyone logs in, and on headless wolf.
{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.mutagen ];

  launchd.daemons.mutagen = {
    serviceConfig = {
      UserName = "mikaelweiss";
      EnvironmentVariables.HOME = "/Users/mikaelweiss";
      # /nix is a separate volume, not yet mounted when launchd loads daemons.
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${pkgs.mutagen}/bin/mutagen daemon run"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/mutagen.log";
      StandardErrorPath = "/tmp/mutagen.err";
    };
  };

  launchd.daemons.sync-resolve = {
    serviceConfig = {
      UserName = "mikaelweiss";
      EnvironmentVariables = {
        HOME = "/Users/mikaelweiss";
        PATH = "${pkgs.mutagen}/bin:${pkgs.jq}/bin:/usr/bin:/bin";
      };
      ProgramArguments = [ "/Users/mikaelweiss/code/dotfiles/terminal/bin/sync-resolve" ];
      StartInterval = 300;
      StandardOutPath = "/tmp/sync-resolve.log";
      StandardErrorPath = "/tmp/sync-resolve.log";
    };
  };
}
