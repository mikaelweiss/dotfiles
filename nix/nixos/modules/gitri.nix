{ config, pkgs, ... }:

let
  domain = "gitri.weissfamily.us";
  httpPort = 3000;
  # Each push to main builds the fork from origin and points this link at it, so a deploy needs no system rebuild.
  current = "/var/lib/gitri/current";
in
{
  services.gitea = {
    enable = true;
    package = pkgs.writeShellScriptBin "gitea" ''exec ${current}/bin/gitea "$@"'';
    database.type = "postgres";
    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = httpPort;
        # The system sshd admits only wheel, so Gitea serves git over its own SSH server.
        START_SSH_SERVER = true;
        SSH_PORT = 2222;
        BUILTIN_SSH_SERVER_USER = "git";
        SSH_CREATE_AUTHORIZED_KEYS_FILE = false;
        STATIC_ROOT_PATH = "${current}-data";
      };
      service.DISABLE_REGISTRATION = true;
      # The fork reports a commit hash as its version, which the checker cannot compare against releases.
      "cron.update_checker".ENABLED = false;
    };
  };

  # The public DNS record points at this host's Tailscale address, and the firewall trusts only
  # tailscale0, so the site and SSH port are reachable from the tailnet alone.
  security.acme = {
    acceptTerms = true;
    certs.${domain} = {
      dnsProvider = "cloudflare";
      credentialFiles.CF_DNS_API_TOKEN_FILE = "/etc/pika/cloudflare-token";
      group = config.services.nginx.group;
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts.${domain} = {
      useACMEHost = domain;
      forceSSL = true;
      # Pi-hole's dashboard owns port 80.
      listen = [{ addr = "0.0.0.0"; port = 443; ssl = true; }];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString httpPort}";
        # Pushes over HTTPS and release uploads exceed nginx's 1 MB default.
        extraConfig = "client_max_body_size 512M;";
      };
    };
  };

  systemd.services."gitri-deploy@" = {
    description = "Deploy gitri at commit %i";
    path = [ config.nix.package pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "gitri";
    };
    scriptArgs = "%i";
    script = ''
      nix build "git+https://${domain}/mikaelweiss/gitri?rev=$1&shallow=1" --out-link ${current}
      systemctl restart gitea
    '';
  };

  # Workflows run as the runner user, so it may start a deploy but cannot choose what gets built.
  services.gitea-actions-runner.instances.pika = {
    enable = true;
    name = "pika";
    url = "http://127.0.0.1:${toString httpPort}";
    # TOKEN=<registration token from `gitea actions generate-runner-token`>
    tokenFile = "/etc/pika/gitea-runner-token";
    labels = [ "pika:host" ];
    hostPackages = with pkgs; [ bash coreutils gitMinimal config.nix.package config.systemd.package ];
  };

  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "gitea-runner" &&
          action.lookup("verb") == "start" &&
          action.lookup("unit").indexOf("gitri-deploy@") == 0) {
        return polkit.Result.YES;
      }
    });
  '';

  services.weiss-status.agent.units = [ "gitea" "gitea-runner-pika" "postgresql" "nginx" ];
}
