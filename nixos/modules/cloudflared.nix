{ config, pkgs, ... }:

let
  tunnelId = "a799dbbd-a209-44f5-a997-e4b90226ece9";
in
{
  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = "/etc/cloudflared/${tunnelId}.json";
      default = "http_status:404";
      ingress = {
        "mikaelweiss.dev" = "http://localhost:4000";
        "mikaelweiss.org" = "http://localhost:4000";
        "weisssolutions.org" = "http://localhost:4001";
        "pmgforrms.org" = "http://localhost:4003";
        "rachelweiss.org" = "http://localhost:4004";
        "rachelweiss.me" = "http://localhost:4004";
        "lunchninja.org" = "http://localhost:4005";
        "vault.mikaelweiss.dev" = "http://localhost:4006";
        "rubrixai.app" = "http://localhost:4007";
        "rubrixai.org" = "http://localhost:4007";
        "deploy.mikaelweiss.dev" = "http://localhost:9000";
      };
    };
  };
}
