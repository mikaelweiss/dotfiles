# Google's Antigravity CLI (agy). It updates itself, so this only installs it when
# missing. Google's installer would also run `agy install`, which edits shell config
# that .zshrc already covers. nix-ld runs the downloaded binary.
{ config, pkgs, lib, ... }:

let
  user = "mikaelweiss";
  home = config.users.users.${user}.home;
  platform = {
    x86_64-linux = "linux_amd64";
    aarch64-linux = "linux_arm64";
  }.${pkgs.stdenv.hostPlatform.system};

  install = pkgs.writeShellScript "antigravity-cli" ''
    set -eu
    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnutar pkgs.gzip ]}"
    bin="$HOME/.local/bin/agy"
    [ -e "$bin" ] && exit 0

    manifest=$(curl -fsSL --max-time 15 \
      "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${platform}.json") \
      || { echo "antigravity-cli: release server unreachable, skipping"; exit 0; }
    url=$(printf '%s' "$manifest" | jq -r .url)
    sha512=$(printf '%s' "$manifest" | jq -r .sha512)

    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' EXIT
    curl -fsSL --max-time 600 -o "$staging/agy.tar.gz" "$url"
    echo "$sha512  $staging/agy.tar.gz" | sha512sum --check --quiet
    tar -xzf "$staging/agy.tar.gz" -C "$staging" antigravity
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$staging/antigravity" "$bin"
    echo "antigravity-cli: installed $(printf '%s' "$manifest" | jq -r .version)"
  '';
in
{
  system.activationScripts.antigravityCli = {
    deps = [ "users" ];
    text = "${pkgs.util-linux}/bin/runuser -u ${user} -- ${pkgs.coreutils}/bin/env HOME=${home} ${install} || echo 'antigravity-cli: install failed'";
  };
}
