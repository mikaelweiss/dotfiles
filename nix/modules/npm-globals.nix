# Declarative `npm install -g`. On each rebuild the listed packages are
# installed or upgraded under ~/.npm-global and anything else there is
# removed. Symlinks (npm link) are left alone. Skipped when offline.
{ config, lib, pkgs, ... }:

let
  cfg = config.npm;
  isDarwin = pkgs.stdenv.isDarwin;

  packageName = spec:
    let
      scoped = lib.hasPrefix "@" spec;
      body = if scoped then lib.removePrefix "@" spec else spec;
      name = lib.head (lib.splitString "@" body);
    in
    (if scoped then "@" else "") + name;

  names = lib.concatStringsSep " " (map packageName cfg.globalPackages);
  specs = lib.escapeShellArgs cfg.globalPackages;

  sync = pkgs.writeShellScript "npm-globals" (''
    set -eu
    export PATH="${pkgs.nodejs}/bin:${pkgs.bash}/bin:$PATH"
    prefix="$HOME/.npm-global"
    modules="$prefix/lib/node_modules"
    mkdir -p "$modules" "$prefix/bin"

    if ! ${pkgs.curl}/bin/curl --silent --head --max-time 5 https://registry.npmjs.org/ >/dev/null; then
      echo "npm globals: registry unreachable, skipping"
      exit 0
    fi

  '' + lib.optionalString (cfg.globalPackages != [ ]) ''
    echo "npm globals: installing ${names}"
    ${pkgs.coreutils}/bin/timeout 10m \
      npm install -g --prefix "$prefix" --no-fund --no-audit --loglevel error ${specs} \
      || echo "npm globals: install failed or timed out, keeping what is there"
  '' + ''

    for dir in "$modules"/*/ "$modules"/@*/*/; do
      dir="''${dir%/}"
      [ -L "$dir" ] && continue
      [ -e "$dir/package.json" ] || continue
      name="''${dir#"$modules/"}"
      case " ${names} " in
        *" $name "*) continue ;;
      esac
      echo "npm globals: removing $name"
      npm uninstall -g --prefix "$prefix" --loglevel error "$name" \
        || echo "npm globals: could not remove $name"
    done
  '');

  runAsUser =
    if isDarwin
    then "/usr/bin/sudo --user=${cfg.user} --set-home ${sync}"
    else "${pkgs.util-linux}/bin/runuser -u ${cfg.user} -- ${pkgs.coreutils}/bin/env HOME=${config.users.users.${cfg.user}.home} ${sync}";
in
{
  options.npm = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "mikaelweiss";
    };
    globalPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "npm package specs, e.g. \"wrangler\" or \"nx@23\".";
    };
  };

  config = {
    programs.zsh.interactiveShellInit = ''
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.npm-global/bin:$PATH"
    '';

    system.activationScripts = lib.mkMerge [
      (lib.mkIf isDarwin { postActivation.text = runAsUser; })
      (lib.mkIf (!isDarwin) { npmGlobals = { deps = [ "users" ]; text = runAsUser; }; })
    ];
  };
}
