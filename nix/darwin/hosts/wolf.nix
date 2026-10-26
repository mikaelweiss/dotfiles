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

  # pip pushes its Postgres dumps to /private/var/pip/pg-backup over sftp. The
  # chroot keeps its unattended key away from every other file on wolf.
  users.knownUsers = [ "pip" ];
  users.users.pip = {
    uid = 550;
    home = "/var/empty";
    # Login fails PAM's account check unless the shell is in /etc/shells. The
    # chroot has no binaries and ForceCommand runs internal-sftp, so it never runs.
    shell = "/bin/sh";
    openssh.authorizedKeys.keys = [ "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFQ1CCxRjR9eT2fh51oqbrV6lrcnaAhphAJBRkQC9Qy pg-backup@pip" ];
  };
  # The included file ends inside this Match unless Match all closes it.
  services.openssh.extraConfig = ''
    Match User pip
      ChrootDirectory /private/var/pip
      ForceCommand internal-sftp
    Match all
  '';
  system.activationScripts.postActivation.text = ''
    install -d -m 0755 -o root -g wheel /private/var/pip
    install -d -m 0700 -o pip -g staff /private/var/pip/pg-backup
    # Remote Login admits admins only, so pip joins its access group.
    dseditgroup -o edit -a pip -t user com.apple.access_ssh
  '';

  programs.zsh.interactiveShellInit = ''
    # LM Studio CLI
    export PATH="$PATH:/Users/mikaelweiss/.lmstudio/bin"
  '';

  homebrew.brews = [
    "tailscale"
    "flyctl"
  ];

  homebrew.casks = [
    "docker-desktop"
  ];
}
