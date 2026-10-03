{ pkgs, ... }:

let
  rotatePython = pkgs.python3.withPackages (ps: [ ps.fastapi ps.httpx ps.uvicorn ]);
  rotateDir = "/Users/mikaelweiss/.local/share/claude-rotate";
in
{
  environment.systemPackages = with pkgs; [
    python311
  ];

  # Every machine's claude talks to this proxy, which rotates across the
  # subscription tokens in rotateDir/tokens. Kept out of ~/code so mutagen
  # never copies the tokens to other machines. It listens on localhost only:
  # the macOS firewall drops inbound connections to unsigned nix binaries, so
  # `tailscale serve --tcp 8484 tcp://127.0.0.1:8484` exposes it to the tailnet.
  launchd.daemons.claude-rotate = {
    serviceConfig = {
      UserName = "mikaelweiss";
      EnvironmentVariables.HOME = "/Users/mikaelweiss";
      WorkingDirectory = rotateDir;
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${rotatePython}/bin/python3 ${rotateDir}/rotator.py"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 15;
      StandardOutPath = "/tmp/claude-rotate.log";
      StandardErrorPath = "/tmp/claude-rotate.log";
    };
  };

  programs.zsh.interactiveShellInit = ''
    # LM Studio CLI
    export PATH="$PATH:/Users/mikaelweiss/.lmstudio/bin"
  '';

  homebrew.brews = [
    "tailscale"
  ];
}
