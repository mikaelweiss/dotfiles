# Every Mac. Machine-wide shared config lives in ../shared.nix.
{ pkgs, self, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  environment.systemPackages = with pkgs; [
    mutagen
    # opencode
    # github-copilot-cli
    # bruno
    # bruno-cli
    llvm
    sqlite
    gh # GitHub CLI
    rsync # GNU rsync
    pass # Password manager, on PATH so GUI apps (Raycast) find it
    gnupg # GPG key manager (pass dependency)
    pinentry_mac # GPG passphrase prompt that saves to the macOS Keychain
    pandoc # Change files to other file types
    # For typescriptLSP Claude Code plugin
    typescript
    typescript-language-server
    ffmpeg
    dust # Du, but better
    tree # See the directories
    mas # CLI to manage Mac Apps from the App Store
  ];

  # Terminal font. Registers the family "MesloLGS Nerd Font Mono".
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];

  # HTML manual fails to build against current nixpkgs (nix-darwin#1817);
  # man pages are unaffected. The uninstaller embeds its own default-config
  # system, so it hits the same failure.
  documentation.doc.enable = false;
  system.tools.darwin-uninstaller.enable = false;

  # Lix binary cache (prebuilt Lix instead of compiling from source)
  nix.settings.extra-substituters = [ "https://cache.lix.systems" ];
  nix.settings.extra-trusted-public-keys = [ "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o=" ];

  # Garbage collection Sunday 2am, store dedup Sunday 3am
  nix.gc.interval = { Weekday = 0; Hour = 2; Minute = 0; };
  nix.optimise = {
    automatic = true;
    interval = { Weekday = 0; Hour = 3; Minute = 0; };
  };

  # Primary user for user-specific options like Homebrew
  system.primaryUser = "mikaelweiss";

  # Every Mac runs its own mutagen daemon with sessions to elm, the
  # always-on hub (see terminal/bin/sync-setup). A system daemon rather
  # than a user agent: user agents start only at GUI login, and wolf
  # runs headless.
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

  # Homebrew configuration
  homebrew = {
    enable = true;

    taps = [
      "modem-dev/tap"
      "getsentry/xcodebuildmcp"
    ];

    # CLI tools
    brews = [
      "elixir"
      "erlang@28" # Pin OTP 28; OTP 29 crashes reading macOS CA certs (no_cacerts_found). Keg-only; .zshrc puts it ahead of unversioned erlang.
      "postgresql@18"
      "xcode-build-server"
      "mole"
      "openjdk@21"
      # "mise" # node/python/etc version manager, per-project pinning
      "herdr"
      "pngpaste"
      "modem-dev/tap/hunk"
      "getsentry/xcodebuildmcp/mobilebuildmcp" # Lets agents build, run, and drive the iOS Simulator
    ];

    # GUI Applications
    casks = [
      # AI Tools
      "codexbar"
      "codex"
      # "cursor"
      # Android Development
      "android-commandlinetools"
      # "openmtp" # Android file transfer
      # Apps
      "arc"
      # "chatgpt"
      # "grandperspective"
      # "obs"
      # "obsidian"
      "raycast"
      "ollama-app"
      # "notion"
      # Dev tools
      "ghostty"
      "sf-symbols"
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
