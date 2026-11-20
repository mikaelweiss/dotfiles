# Claude Code asks to trust the home folder on every launch there, because
# answering Yes never saves for home. It does honor the saved flag, so each
# rebuild sets it in ~/.claude.json.
{ lib, pkgs, ... }:

let
  user = "mikaelweiss";
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  trustHome = pkgs.writeShellScript "claude-home-trust" ''
    set -eu
    config="$HOME/.claude.json"
    [ -s "$config" ] || echo '{}' > "$config"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$config.XXXXXX")"
    ${pkgs.jq}/bin/jq --arg home "$HOME" \
      '.projects[$home].hasTrustDialogAccepted = true' "$config" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  '';

  runAsUser =
    if isDarwin
    then "/usr/bin/sudo --user=${user} --set-home ${trustHome} || echo 'claude home trust failed'"
    else "${pkgs.util-linux}/bin/runuser -u ${user} -- ${pkgs.coreutils}/bin/env HOME=/home/${user} ${trustHome} || echo 'claude home trust failed'";
in
{
  system.activationScripts = lib.mkMerge [
    (lib.mkIf isDarwin { postActivation.text = runAsUser; })
    (lib.mkIf (!isDarwin) { claudeHomeTrust = { deps = [ "users" ]; text = runAsUser; }; })
  ];
}
