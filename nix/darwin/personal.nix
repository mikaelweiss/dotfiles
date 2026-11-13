# Personal Macs (Air and wolf), not the work MacBook Pro.
{ pkgs, ... }:

{
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

  # XcodeGen reads its setting presets from ../share/xcodegen beside the
  # binary on PATH. Without them a generated project has no Debug settings.
  environment.pathsToLink = [ "/share/xcodegen" ];
}
