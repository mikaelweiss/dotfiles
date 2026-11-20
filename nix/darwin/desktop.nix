# Macs with someone at the screen: the Air and the MacBook Pro.
{ pkgs, ... }:

{
  homebrew.casks = [
    "thebrowsercompany-dia"
    "raycast"
    "sf-symbols"
    "font-sf-mono" # Obsidian's default monospace font, used in Ghostty
  ];

  environment.systemPackages = [ pkgs.mutagen ];

  # Each of these Macs runs its own mutagen daemon with sessions to elm
  # (see terminal/bin/sync-setup). A system daemon rather than a user agent,
  # so syncing starts before anyone logs in.
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

  system.activationScripts.postActivation.text = ''
    # Claude Code writes its browser extension host only for browsers it knows, and Dia is not one.
    launchctl asuser "$(id -u mikaelweiss)" sudo --set-home --user=mikaelweiss -- sh -c '
      hosts="/Users/mikaelweiss/Library/Application Support/Dia/User Data/NativeMessagingHosts"
      mkdir -p "$hosts"
      ln -sfn "/Users/mikaelweiss/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json" \
        "$hosts/com.anthropic.claude_code_browser_extension.json"
    ' || echo "Dia native host link failed"
  '';
}
