{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nixpkgs-unstable }:
  let
    system = "aarch64-darwin";
    unstable = import nixpkgs-unstable { inherit system; };

    # Personal computers, not work computer
    personalConfig = { pkgs, ... }: {
        environment.systemPackages = with pkgs; [
        restic # Backup manager
        rustup # For Rust
        # flyctl # CLI for Fly.io
        # imagemagick # Not sure
        # nushell # Cool concept
        # pyenv # Py environment manager (USE MISE INSTEAD)
        cloudflared # Cloudflare daemon
        cmake # Build system generator
        cocoapods # Manage dependancies for your Xcode projects
        swiftformat # Swift formatter
        swiftlint # Swift linter
        xcbeautify # Beautifier tool for Xcode
        xcodegen # Swift CLI for generating Xcode projects
        cbonsai # Generates ascii bonsai
        cmatrix # Generates ascii matrix
        asciiquarium # Generates an ascii aquarium
        asciinema # Record and play back a terminal session, can turn it into a gif
        # croc # File sharing
        # ttyd # open a terminal from another computer
        # jrnl # Light weight journaling app
        # lolcat
        # faker # Fake names, emails, ids, datas etc. Good for automation.
        # grex # Generates a regex based on an input you give it.
        jujutsu
        lazyjj
        ];
      };

    # Host-specific configuration for MacBook Air
    macbookAirConfig = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        javaPackages.compiler.openjdk25 # Java
        rubyPackages_4_0.cocoapods
      ];

      programs.zsh = {
        enable = true;
        interactiveShellInit = ''
          # Android SDK
          export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
          # export NDK_HOME="$ANDROID_HOME/ndk/$(ls -1 $ANDROID_HOME/ndk 2>/dev/null | head -1)"
          # export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
          export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
        '';
      };
    };

    # Host-specific configuration for Wolf
    wolfConfig = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        nodejs_24
        # Wolf-only packages here
      ];

      programs.zsh = {
        enable = true;
        interactiveShellInit = ''
          # Tailscale
          alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

          # LM Studio CLI
          export PATH="$PATH:/Users/mikaelweiss/.lmstudio/bin"

          # Clawd Bot Stuff
          export PATH="$HOME/.npm-global/bin:$PATH"
          export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
          export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
        '';
      };
    };

    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      nixpkgs.config.allowUnfree = true;
      environment.systemPackages = with pkgs;
        [
        vim # Vim
        yazi # File browser
        tmux # Multiplexer
        stow # Dotfiles manager
        fzf # Fuzy find files
        lazygit # Git, but Lazy
        neovim # Vim, but epic
        pandoc # Change files to other file types
        mise # Node/Python/etc version manager
        ripgrep # Better grep
        tldr # Read docs faster
        # For typescriptLSP Claude Code plugin
        nodePackages.typescript
        nodePackages.typescript-language-server
        ffmpeg
        dust # Du, but better
        tree # See the directories
        wget # wget files from http, https, and ftp
        zoxide # Better cd
        mas # CLI to manage Mac Apps from the App Store
        # Load Nix environment when you open a directory with .envrc file
        direnv
        nix-direnv
        btop # See whats up
        atuin # Shell history search
        # javaPackages.compiler.openjdk21 # Java
        ];

      # Set nvim as default editor
      environment.variables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };

      programs.direnv = {
        enable = true;
        silent = true;
        nix-direnv.enable = true;
      };

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Automatic garbage collection (Sunday 2am)
      nix.gc = {
        automatic = true;
        interval = { Weekday = 0; Hour = 2; Minute = 0; };
        options = "--delete-older-than 30d";
      };

      # Automatic store deduplication (Sunday 3am)
      nix.optimise = {
        automatic = true;
        interval = { Weekday = 0; Hour = 3; Minute = 0; };
      };

      # Primary user for user-specific options like Homebrew
      system.primaryUser = "mikaelweiss";

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

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Homebrew configuration
      homebrew = {
        enable = true;

        # Taps (third-party repositories)
        taps = [
          "mikaelweiss/openchat"
        ];

        # CLI tools
        brews = [
          "ast-grep"
          # "opencode"
          # "elixir"
          # "python3"
          "llvm"
          "postgresql@18"
          "python@3.14"
          "sqlite"
          "xcode-build-server"
          # "watchman" # React Native dependancy
          "oven-sh/bun/bun"
          "mole"
          # "firebase-cli"
          # "pnpm"
          "python@3.12"
          "pyenv"
          # "bruno-cli"
          "gh" # GitHub CLI
          "openjdk@21"
          "rsync" # GNU rsync
          "pass" # Password manager — installed via brew so GUI apps (Raycast) find it on PATH
          "gnupg" # GPG key manager (pass dependency)
          "worktrunk" # Manage git worktrees
        ];

        # GUI Applications
        casks = [
          # AI Tools
          "codexbar"
          "copilot-cli"
          "codex"
          # "claude"
          # "cursor"
          # Android Development
          "android-commandlinetools"
          # "android-ndk"
          # "android-platform-tools"
          # "android-studio"
          # "openmtp" # Android file transfer
          # Apps
          "arc"
          # "chatgpt"
          # "grandperspective"
          # "obs"
          # "obsidian"
          "raycast"
          # "signal"
          # "mikaelweiss-open-chat"
          "tailscale-app"
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
          # "Tailscale" = 1475387142;
          # "Transporter" = 1450874784
        };

        # Automatically uninstall things in Homebrew not listed in this flake
        # onActivation.cleanup = "zap";

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

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Mikaels-MacBook-Air
    darwinConfigurations."Mikaels-MacBook-Air-2" = nix-darwin.lib.darwinSystem {
      modules = [ configuration macbookAirConfig personalConfig ];
    };
    darwinConfigurations."wolf" = nix-darwin.lib.darwinSystem {
      modules = [ configuration wolfConfig personalConfig ];
    };
  };
}
