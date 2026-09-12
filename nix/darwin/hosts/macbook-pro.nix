# Work machine.
{ pkgs, ... }:

{
  # surestake CI runs node 22, and the Analog vitest pool aborts under nix node 24.
  node.package = pkgs.nodejs_22;

  programs.zsh.interactiveShellInit = ''
    # Android SDK
    export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
    # Gradle needs a JDK; openjdk@21 is keg-only so brew leaves it off PATH.
    export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$JAVA_HOME/bin:$PATH"
  '';

  homebrew.brews = [
    "helix"
    "opencode"
    {
      name = "php@8.2"; # keg-only: brew won't put it on PATH without link
      link = true;
    }
    "tailscale"
  ];

  homebrew.casks = [
    "opencode-desktop"
    "docker-desktop"
    "harvest"
    "cursor"
  ];
}
