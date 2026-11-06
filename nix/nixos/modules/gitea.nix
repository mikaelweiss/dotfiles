{ config, pkgs, inputs, ... }:

let
  domain = "gitri.weissfamily.us";
  httpPort = 3000;
in
{
  services.gitea = {
    enable = true;
    package = inputs.gitea.packages.${pkgs.stdenv.hostPlatform.system}.default;
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

  services.weiss-status.agent.units = [ "gitea" "postgresql" "nginx" ];
}
