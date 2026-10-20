# Internet-facing processes reach the internet but never open a connection
# into the home network or the tailnet, so a compromised one cannot pivot.
# The rules live in the mangle table because Tailscale and netavark insert
# ACCEPT rules at the top of the filter chains.
{ config, lib, ... }:

let
  privateV4 = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10" "169.254.0.0/16" ];
  privateV6 = [ "fc00::/7" "fe80::/10" ];

  fence = cmd: destinations: ''
    ${cmd} -t mangle -D PREROUTING -i podman+ -j dmz 2>/dev/null || true
    ${cmd} -t mangle -D OUTPUT -j dmz-users 2>/dev/null || true
    ${cmd} -t mangle -F dmz 2>/dev/null || ${cmd} -t mangle -N dmz
    ${cmd} -t mangle -F dmz-users 2>/dev/null || ${cmd} -t mangle -N dmz-users
    ${cmd} -t mangle -A dmz -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    ${lib.concatMapStrings (d: "${cmd} -t mangle -A dmz -d ${d} -j DROP\n") destinations}
    ${lib.concatMapStrings (u: "${cmd} -t mangle -A dmz-users -m owner --uid-owner ${u} -j dmz\n") config.dmz.users}
    ${cmd} -t mangle -A PREROUTING -i podman+ -j dmz
    ${cmd} -t mangle -A OUTPUT -j dmz-users
  '';
in
{
  options.dmz.users = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Users whose processes may not open connections to private networks. Containers are always fenced.";
  };

  config.networking.firewall.extraCommands = fence "iptables" privateV4 + fence "ip6tables" privateV6;
}
