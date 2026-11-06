{ config, pkgs, inputs, ... }:

{
  services.gitea = {
    enable = true;
    package = inputs.gitea.packages.${pkgs.stdenv.hostPlatform.system}.default;
    database.type = "postgres";
    settings = {
      # Port 3000 is reached over Tailscale only, since the firewall trusts just tailscale0.
      server = {
        DOMAIN = config.networking.hostName;
        ROOT_URL = "http://${config.networking.hostName}:3000/";
      };
      service.DISABLE_REGISTRATION = true;
      # The fork reports a commit hash as its version, which the checker cannot compare against releases.
      "cron.update_checker".ENABLED = false;
    };
  };

  services.weiss-status.agent.units = [ "gitea" "postgresql" ];
}
