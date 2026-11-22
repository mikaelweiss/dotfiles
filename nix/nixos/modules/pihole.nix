# Pika and oak both serve the tailnet. Tailscale sends every query to both and takes the first answer,
# so their lists and records must match.
{ config, lib, pkgs, inputs, ... }:

{
  services.pihole-ftl = {
    enable = true;
    queryLogDeleter.enable = true;
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts";
        description = "Steven Black: ads, malware, porn";
      }
    ]
    ++ map (name: {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/${name}.txt";
      description = "HaGeZi ${name}";
    }) [
      "pro"
      "tif"
      # Without it, browsers with their own encrypted DNS route around every list here.
      "doh-vpn-proxy-bypass"
      "gambling"
      "native.apple"
      "native.amazon"
      "native.samsung"
      "native.tiktok"
      "native.winoffice"
    ]
    ++ [
      {
        url = "file://${pkgs.writeText "pihole-allow.txt" ''
          @@||sentry.io^
          @@||sentry-cdn.com^
          @@||tailscale.com^
        ''}";
        type = "allow";
        description = "Domains needed for work";
      }
    ];
    settings.dns = {
      upstreams = [ "1.1.1.1" "1.0.0.1" ];
      # The default answers only directly connected subnets, which shuts out tailnet peers.
      listeningMode = "ALL";
      # The Q1000K drops LAN connections to its own WAN address, so the house reaches sparrow directly.
      # Device names come from these records, since the router keeps its DHCP hostnames to itself.
      hosts = [
        "192.168.0.5 mikaels-iphone"
        "192.168.0.7 mikaels-macbook-pro"
        "192.168.0.9 mikaels-macbook-air"
        "192.168.0.50 wolf"
        "192.168.0.14 hannahs-iphone"
        "192.168.0.16 epson-printer"
        "192.168.0.23 roku"
      ]
      ++ lib.concatMap (domain: map (name: "192.168.0.11 ${name}.${domain}") [ "play" "skyblock" "shire" ])
        [ "mikaelmc.com" "mikaelmc.net" ];
    };
  };

  # 26.05's list setup fails on every run after the first, so reboots and weekly refreshes report failure.
  # Master's whole module expects master's Pi-hole packages, so only its setup script comes from there.
  systemd.services.pihole-ftl-setup.script = lib.mkForce (import
    "${inputs.nixpkgs-master}/nixos/modules/services/networking/pihole-ftl-setup-script.nix" {
      inherit config lib pkgs;
      cfg = config.services.pihole-ftl;
    });

  systemd.services.pihole-ftl-setup = {
    after = [ "time-sync.target" ];
    wants = [ "time-sync.target" ];
    startAt = "weekly";
  };

  # The dashboard has no password, so it is reached over Tailscale only.
  services.pihole-web = {
    enable = true;
    ports = [ 80 ];
  };
}
