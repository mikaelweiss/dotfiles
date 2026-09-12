{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    javaPackages.compiler.openjdk25 # Java
    rubyPackages_4_0.cocoapods
  ];

  programs.zsh.interactiveShellInit = ''
    # Android SDK
    export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
    # export NDK_HOME="$ANDROID_HOME/ndk/$(ls -1 $ANDROID_HOME/ndk 2>/dev/null | head -1)"
    # export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
  '';

  homebrew.brews = [
    "deno"
  ];

  homebrew.casks = [
    "grok-bot"
    "modrinth"
    "obsidian"
    "shottr"
    "signal"
    "conductor"
    "tailscale-app"
    "moonlight"
  ];
}
