{ config, pkgs, lib, ... }:

let
  siteUsers = [ "portfolio" "weisssolutions" "pmgforrms" "rachelportfolio" "lunchninja" "vault" "rubrix" ];

  buildTools = with pkgs; [ git openssh elixir_1_19 nodejs_22 pnpm coreutils bash gnused gawk gnutar gzip curl ];
  # The nix-store sudo is not setuid; only the wrapper works.
  sudo = "/run/wrappers/bin/sudo";

  mkService = name: attrs: lib.recursiveUpdate {
    description = name;
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = buildTools;
    serviceConfig = {
      Type = "simple";
      User = name;
      Group = name;
      WorkingDirectory = "/opt/${name}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  } attrs;

  phoenix = name: release: mkService name {
    serviceConfig = {
      EnvironmentFile = "/etc/${name}/env";
      ExecStart = "/opt/${name}/_build/prod/rel/${release}/bin/${release} start";
    };
  };

  static = name: port: mkService name {
    serviceConfig.ExecStart = "${pkgs.nodePackages.serve}/bin/serve dist -l ${toString port}";
  };

  deployPhoenix = pkgs.writeShellApplication {
    name = "deploy-phoenix";
    runtimeInputs = buildTools ++ [ pkgs.systemd ];
    text = ''
      site_user=$1 dir=$2 service=$3 env_file=$4 run_migrate=$5
      echo "Deploying $service..."
      ${sudo} -u "$site_user" env PATH="$PATH" bash -c "
        set -e
        cd $dir
        git pull origin main
        set -a && source $env_file && set +a
        MIX_ENV=prod mix deps.get
        MIX_ENV=prod mix compile
        MIX_ENV=prod mix assets.deploy
        MIX_ENV=prod mix release --overwrite
      "
      if [ "$run_migrate" = "true" ]; then
        ${sudo} -u "$site_user" env PATH="$PATH" bash -c "
          set -e
          cd $dir
          set -a && source $env_file && set +a
          MIX_ENV=prod mix ecto.migrate
        "
      fi
      ${sudo} systemctl restart "$service"
      echo "Deployed $service"
    '';
  };

  deployNode = pkgs.writeShellApplication {
    name = "deploy-node";
    runtimeInputs = buildTools ++ [ pkgs.systemd ];
    text = ''
      site_user=$1 dir=$2 service=$3
      echo "Deploying $service..."
      ${sudo} -u "$site_user" env PATH="$PATH" bash -c "
        set -e
        cd $dir
        git fetch origin main
        git reset --hard origin/main
        if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile && pnpm run build
        elif [ -f package-lock.json ]; then npm ci && npm run build
        else npm install && npm run build
        fi
      "
      ${sudo} systemctl restart "$service"
      echo "Deployed $service"
    '';
  };
  hookRule = ''
    {
      "and": [
        { "match": { "type": "payload-hmac-sha256", "secret": "@SECRET@",
                     "parameter": { "source": "header", "name": "X-Hub-Signature-256" } } },
        { "match": { "type": "value", "value": "refs/heads/main",
                     "parameter": { "source": "payload", "name": "ref" } } }
      ]
    }
  '';
  hook = id: command: args: {
    inherit id;
    execute-command = command;
    command-working-directory = "/opt/deploy";
    pass-arguments-to-command = map (a: { source = "string"; name = a; }) args;
    trigger-rule = builtins.fromJSON hookRule;
  };
  phoenixHook = name: migrate:
    hook name "${deployPhoenix}/bin/deploy-phoenix" [ name "/opt/${name}" name "/etc/${name}/env" migrate ];
  nodeHook = name:
    hook name "${deployNode}/bin/deploy-node" [ name "/opt/${name}" name ];
  hooksTemplate = pkgs.writeText "hooks.json" (builtins.toJSON [
    (phoenixHook "portfolio" "false")
    (phoenixHook "weisssolutions" "false")
    (phoenixHook "lunchninja" "false")
    (nodeHook "pmgforrms")
    (nodeHook "rachelportfolio")
    (nodeHook "vault")
    (nodeHook "rubrix")
  ]);
in
{
  users.users = lib.genAttrs siteUsers (name: {
    isSystemUser = true;
    group = name;
    home = "/opt/${name}";
    createHome = true;
    shell = pkgs.bash;
  });
  users.groups = lib.genAttrs siteUsers (_: {});

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
  };

  systemd.services = {
    portfolio = lib.recursiveUpdate (phoenix "portfolio" "portfolio_template") {
      after = [ "network.target" "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };
    weisssolutions = phoenix "weisssolutions" "weisssolutions";
    lunchninja = phoenix "lunchninja" "lunch_ninja";

    pmgforrms = mkService "pmgforrms" {
      environment = { NODE_ENV = "production"; PORT = "4003"; };
      serviceConfig.ExecStart = "${pkgs.nodejs_22}/bin/node build/index.js";
    };

    rachelportfolio = static "rachelportfolio" 4004;
    rubrix = static "rubrix" 4007;

    vault = mkService "vault" {
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 4006 --directory /opt/vault/dist";
    };

    webhook = {
      description = "GitHub webhook deploy receiver";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ deployPhoenix deployNode ];
      preStart = ''
        secret=$(cat /etc/webhook/secret)
        sed "s|@SECRET@|$secret|g" ${hooksTemplate} > /run/webhook/hooks.json
      '';
      serviceConfig = {
        User = "mikaelweiss";
        RuntimeDirectory = "webhook";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "/opt/deploy";
        ExecStart = "${pkgs.webhook}/bin/webhook -hooks /run/webhook/hooks.json -port 9000 -verbose";
        Restart = "on-failure";
      };
    };
  };

  systemd.tmpfiles.rules = [ "d /opt/deploy 0755 mikaelweiss users -" ];

  environment.systemPackages = [ deployPhoenix deployNode pkgs.elixir_1_19 pkgs.nodejs_22 ];
}
