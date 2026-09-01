{ config, pkgs, ... }:

let
  update = pkgs.writeShellApplication {
    name = "cloudflare-ddns";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      # Expects /etc/cloudflare/ddns.env with CF_API_TOKEN, CF_ZONE, CF_RECORD.
      api=https://api.cloudflare.com/client/v4
      auth=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

      ip=$(curl -fsS https://cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p')
      [ -n "$ip" ] || { echo "no public ip"; exit 1; }

      zone_id=$(curl -fsS "''${auth[@]}" "$api/zones?name=$CF_ZONE" | jq -r '.result[0].id')
      record=$(curl -fsS "''${auth[@]}" "$api/zones/$zone_id/dns_records?type=A&name=$CF_RECORD")
      record_id=$(jq -r '.result[0].id // empty' <<<"$record")
      current=$(jq -r '.result[0].content // empty' <<<"$record")

      body=$(jq -n --arg n "$CF_RECORD" --arg ip "$ip" '{type:"A",name:$n,content:$ip,ttl:60,proxied:false}')
      if [ -z "$record_id" ]; then
        curl -fsS "''${auth[@]}" -X POST "$api/zones/$zone_id/dns_records" --data "$body" >/dev/null
        echo "created $CF_RECORD -> $ip"
      elif [ "$current" != "$ip" ]; then
        curl -fsS "''${auth[@]}" -X PATCH "$api/zones/$zone_id/dns_records/$record_id" --data "$body" >/dev/null
        echo "updated $CF_RECORD $current -> $ip"
      fi
    '';
  };
in
{
  systemd.services.cloudflare-ddns = {
    description = "Point the Minecraft hostname at the current WAN address";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/cloudflare/ddns.env";
      ExecStart = "${update}/bin/cloudflare-ddns";
      DynamicUser = true;
    };
  };

  systemd.timers.cloudflare-ddns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
    };
  };
}
