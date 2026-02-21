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
          export ANDROID_HOME="$HOME/Library/Android/sdk"
          export NDK_HOME="$ANDROID_HOME/ndk/$(ls -1 $ANDROID_HOME/ndk 2>/dev/null | head -1)"
          export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
          export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
        '';
      };
    };

    # Host-specific configuration for Wolf
    wolfConfig = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
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
          export PATH="/usr/local/opt/node@24/bin:$PATH"
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
        zellij # Multiplexer
        stow # Dotfiles manager
        flyctl # CLI for Fly.io
        fzf # Fuzy find files
        imagemagick # Not sure
        lazygit # Git, but Lazy
        neovim # Vim, but epic
        nushell # Cool concept
        pandoc # Change files to other file types
        pyenv # Py environment manager
        restic # Backup manager
        ripgrep # Better grep
        rustup # For Rust
        tldr # Read docs faster
        cloudflared # Cloudflare daemon
        cmake # Build system generator
        cocoapods # Manage dependancies for your Xcode projects
        dust # Du, but better
        ffmpeg
        swiftformat # Swift formatter
        swiftlint # Swift linter
        tree # See the directories
        wget # wget files from http, https, and ftp
        xcbeautify # Beautifier tool for Xcode
        xcodegen # Swift CLI for generating Xcode projects
        zoxide # Better cd
        mas # CLI to manage Mac Apps from the App Store
        # Load Nix environment when you open a directory with .envrc file
        direnv
        nix-direnv
        pass # Password management cli
        gnupg # GPG key manager
        btop # See whats up
        atuin # Shell history search
        pipx # Ash graphql dependancy
        python313Packages.pip # Pip for python
        # For typescriptLSP Claude Code plugin
        nodePackages.typescript
        nodePackages.typescript-language-server
        # javaPackages.compiler.openjdk21 # Java
        cbonsai # Generates ascii bonsai
        cmatrix # Generates ascii matrix
        asciiquarium # Generates an ascii aquarium
        # asciinema # Record and play back a terminal session, can turn it into a gif
        # croc # File sharing
        # ttyd # open a terminal from another computer
        # jrnl # Light weight journaling app
        lolcat
        # faker # Fake names, emails, ids, datas etc. Good for automation.
        grex # Generates a regex based on an input you give it.
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
          "elixir"
          "python3"
          "llvm"
          "postgresql@18"
          "python@3.14"
          "sqlite"
          "xcode-build-server"
          "node@24"
          # "watchman" # React Native dependancy
          "oven-sh/bun/bun"
          "mole"
          # "firebase-cli"
          "pnpm"
          "python@3.12"
          "pyenv"
          # "bruno-cli"
          "gh" # GitHub CLI
          "openjdk@21"
        ];

        # GUI Applications
        casks = [
          # "steipete/tap/codexbar" # Keep track of AI usage
          # "bruno"
          "docker-desktop"
          "1password"
          # "rapidapi"
          # "android-commandlinetools"
          # "android-ndk"
          # "android-platform-tools"
          "android-studio"
          "arc"
          "chatgpt"
          # "claude"
          # "cursor"
          "codex"
          "ghostty"
          "grandperspective"
          # "notion"
          "obs"
          "obsidian"
          # "openmtp" # Android file transfer
          # "prusaslicer"
          "raycast"
          "sf-symbols"
          # "void"
          # "zed"
          "zoom"
          "docker-desktop"
          # "opencode-desktop"
          "superwhisper"
          "utm"
          "signal"
          "mikaelweiss-open-chat"
        ];

        # Mac App Store apps by ID
        masApps = {
          # "DaVinci Resolve" = 571213070;
          # "DevCleaner" = 1388020431;
          "Developer" = 640199958;
          "Harvest" = 506189836;
          # "iMovie" = 408981434;
          "Magnet" = 441258766;
          "Numbers" = 409203825;
          # "Obsidian Web Clipper" = 6720708363;
          "Pages" = 409201541;
          "RocketSim" = 1504940162;
          "Slack" = 803453959;
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
    darwinConfigurations."Mikaels-MacBook-Air" = nix-darwin.lib.darwinSystem {
      modules = [ configuration macbookAirConfig ];
    };
    darwinConfigurations."wolf" = nix-darwin.lib.darwinSystem {
      modules = [ configuration wolfConfig ];
    };
  };
}
