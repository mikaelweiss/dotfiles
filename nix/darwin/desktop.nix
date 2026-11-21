# Macs with someone at the screen: the Air and the MacBook Pro.
{ ... }:

{
  homebrew.casks = [
    "thebrowsercompany-dia"
    "raycast"
    "sf-symbols"
    "font-sf-mono" # Obsidian's default monospace font, used in Ghostty
  ];

  system.activationScripts.postActivation.text = ''
    # Claude Code writes its browser extension host only for browsers it knows, and Dia is not one.
    launchctl asuser "$(id -u mikaelweiss)" sudo --set-home --user=mikaelweiss -- sh -c '
      hosts="/Users/mikaelweiss/Library/Application Support/Dia/User Data/NativeMessagingHosts"
      mkdir -p "$hosts"
      ln -sfn "/Users/mikaelweiss/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json" \
        "$hosts/com.anthropic.claude_code_browser_extension.json"
    ' || echo "Dia native host link failed"
  '';
}
