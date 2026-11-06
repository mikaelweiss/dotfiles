{ config, pkgs, inputs, ... }:

{
  services.gitea = {
    enable = true;
    package = inputs.gitea.packages.${pkgs.stdenv.hostPlatform.system}.default;
    database.type = "postgres";
    settings = {
      # Ports 3000 and 2222 are reached over Tailscale only, since the firewall trusts just tailscale0.
      server = {
        DOMAIN = config.networking.hostName;
        ROOT_URL = "http://${config.networking.hostName}:3000/";
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

  services.weiss-status.agent.units = [ "gitea" "postgresql" ];
}
