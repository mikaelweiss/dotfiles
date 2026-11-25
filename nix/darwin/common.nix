# Every Mac. Machine-wide shared config lives in ../shared.nix.
{ pkgs, self, inputs, ... }:

let
  stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  # 26.05 carries Node security releases ahead of unstable.
  node.pkgs = stable;

  environment.systemPackages = with pkgs; [
    jdk25
    # opencode
    # github-copilot-cli
    # bruno
    # bruno-cli
    llvm
    sqlite
    rsync # GNU rsync
    pass # Password manager, on PATH so GUI apps (Raycast) find it
    gnupg # GPG key manager (pass dependency)
    pandoc # Change files to other file types
    # For typescriptLSP Claude Code plugin
    stable.typescript
    stable.typescript-language-server
    ffmpeg
    dust # Du, but better
    tree # See the directories
    mas # CLI to manage Mac Apps from the App Store
    awscli2
    uv
  ];

  # Terminal font. Registers the family "MesloLGS Nerd Font Mono".
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];

  # HTML manual fails to build against current nixpkgs (nix-darwin#1817);
  # man pages are unaffected. The uninstaller embeds its own default-config
  # system, so it hits the same failure.
  documentation.doc.enable = false;
  system.tools.darwin-uninstaller.enable = false;

  # Garbage collection Sunday 2am, store dedup Sunday 3am
  nix.gc.interval = { Weekday = 0; Hour = 2; Minute = 0; };
  nix.optimise = {
    automatic = true;
    interval = { Weekday = 0; Hour = 3; Minute = 0; };
  };

  # Primary user for user-specific options like Homebrew
  system.primaryUser = "mikaelweiss";

  # Key-only SSH. Loads before /etc/ssh/sshd_config, and sshd keeps the first value it reads.
  services.openssh.extraConfig = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  # Passwordless Sudo
  security.sudo.extraConfig = ''
    mikaelweiss ALL=(ALL) NOPASSWD: ALL
  '';

  # Remap right Command key to Escape at login
  launchd.user.agents.remap-escape = {
    serviceConfig = {
      ProgramArguments = [
        "/usr/bin/hidutil"
        "property"
        "--set"
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x7000000E7,\"HIDKeyboardModifierMappingDst\":0x700000029}]}"
      ];
      RunAtLoad = true;
    };
  };

  # Variables reach non-interactive shells too.
  environment.variables = {
    ANDROID_HOME = "/opt/homebrew/share/android-commandlinetools";
    JAVA_HOME = "${pkgs.jdk25.home}";
    # A command run over ssh gets no login shell, and without a UTF-8 locale
    # terminal UIs draw every icon as an underscore.
    LANG = "en_US.UTF-8";
  };
  programs.zsh.interactiveShellInit = ''
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
  '';

  # Homebrew configuration
  homebrew = {
    enable = true;

    taps = [
      "modem-dev/tap"
      "getsentry/xcodebuildmcp"
    ];

    # CLI tools
    brews = [
      "atuin" # nixpkgs atuin 18.24.4 fails to build for aarch64-darwin on Hydra, so it compiles locally.
      "elixir"
      "erlang@28" # Pin OTP 28; OTP 29 crashes reading macOS CA certs (no_cacerts_found). Keg-only; .zshrc puts it ahead of unversioned erlang.
      "postgresql@18"
      "xcode-build-server"
      "mole"
      # "mise" # node/python/etc version manager, per-project pinning
      "herdr"
      "modem-dev/tap/hunk"
      "getsentry/xcodebuildmcp/mobilebuildmcp" # Lets agents build, run, and drive the iOS Simulator
      "python@3.13" # gcloud-cli needs it. Without it, cleanup tries to remove mpdecimal and sqlite and fails.
      "quint"
    ];

    # GUI Applications
    casks = [
      # AI Tools
      "codex"
      "antigravity-cli"
      # "cursor"
      # Android Development
      "android-commandlinetools"
      "gcloud-cli" # Play Developer API tokens without key files
      # "openmtp" # Android file transfer
      # Apps
      # "chatgpt"
      # "grandperspective"
      # "obs"
      # "obsidian"
      # "notion"
      # Dev tools
      "ghostty"
      # "cmux" #fork of Ghostty, built agents first
      # "bruno"
      # "rapidapi"
      # "void"
      # "zed"
      #
      # "prusaslicer"
      # "opencode-desktop"
      # "superwhisper" # STT/TTS app
      # "utm" # vm app
      # "dockdoor" # Prityfication of cmd + tab
      # "handy" # Local Open Source STT app
      # "warp"
    ];

    # Mac App Store apps by ID
    masApps = {
      # "DaVinci Resolve" = 571213070;
      # "DevCleaner" = 1388020431;
      # "Developer" = 640199958;
      # "Harvest" = 506189836;
      # "iMovie" = 408981434;
      # "Magnet" = 441258766;
      # "Numbers" = 409203825;
      # "Obsidian Web Clipper" = 6720708363;
      # "Pages" = 409201541;
      # "RocketSim" = 1504940162;
      # "Slack" = 803453959;
      # "Transporter" = 1450874784
    };

    # Automatically uninstall things in Homebrew not listed in this flake
    onActivation.cleanup = "zap";

    # Auto-update Homebrew
    onActivation.autoUpdate = true;

    # Upgrade outdated packages
    onActivation.upgrade = true;
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;
}
