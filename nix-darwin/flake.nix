{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-clawdbot.url = "github:clawdbot/nix-clawdbot";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nixpkgs-unstable, nix-clawdbot }:
  let
    system = "aarch64-darwin";
    unstable = import nixpkgs-unstable { inherit system; };
    clawdbot = nix-clawdbot.packages.${system}.default;
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
        gh # GitHub CLI
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
        nodejs_22
        javaPackages.compiler.openjdk21 # Java
        javaPackages.compiler.openjdk17 # Java
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
        python313Packages.pip # Pip for python
        # For typescriptLSP Claude Code plugin
        nodePackages.typescript
        nodePackages.typescript-language-server
        rubyPackages_4_0.cocoapods
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
          "watchman" # React Native dependancy
          # "oven-sh/bun"
          "mole"
          "firebase-cli"
        ];

        # GUI Applications
        casks = [
          "steipete/tap/codexbar"
          "1password"
          "rapidapi"
          # "android-commandlinetools"
          "android-ndk"
          "android-platform-tools"
          "android-studio"
          "arc"
          "chatgpt"
          "claude"
          "cursor"
          "codex"
          "ghostty"
          "grandperspective"
          "notion"
          "obs"
          "obsidian"
          # "openmtp" # Android file transfer
          "prusaslicer"
          "raycast"
          "sf-symbols"
          # "void"
          "zed"
          "zoom"
          "opencode-desktop"
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
      modules = [ configuration ];
    };
    darwinConfigurations."Mikaels-Mac-mini" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        {
          environment.systemPackages = [ clawdbot ];
        }
      ];
    };
  };
}
