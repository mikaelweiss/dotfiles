{ config, lib, pkgs, inputs, nixos-raspberrypi, ... }:

let
  router = "192.168.0.1";
  # Reserved on the router, which hands the ethernet address out as the house's DNS server.
  ethernetAddress = "192.168.0.53";
  wifiAddress = "192.168.0.54";
in
{
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    sd-image
    ../../modules/gitri.nix
    ../../modules/backups.nix
    ../../modules/pihole.nix
  ];

  networking.hostName = "pika";

  resticBackups.gitea = true;
  # Pi-hole owns DNS here, so tailnet names do not resolve without Tailscale DNS.
  networking.hosts."100.91.63.11" = [ "oak" ];

  # The SD card reports no SMART data.
  services.weiss-status.sensor.smart = false;
  services.weiss-status.agent = {
    enable = true;
    units = [ "pihole-ftl" "cloudflare-dyndns" ];
    logUnits = [ "pihole-ftl" ];
    throttle = true;
    # Oak lives on another network, so the house's internet is watched from here.
    internet = true;
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # The SD image's base profile pulls in ZFS, which would compile against the vendor kernel.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  sdImage.firmwarePartitionName = "PIKA";
  sdImage.rootVolumeLabel = "pika";

  npm.globalPackages = lib.mkForce [ ];

  networking.networkmanager.enable = true;
  networking.networkmanager.settings.main.no-auto-default = "*";
  # brcmfmac power saving drops the Pi's Wi-Fi link when idle.
  networking.networkmanager.wifi.powersave = false;
  # Both links stay up. The lower route metric keeps traffic on ethernet while it is plugged in.
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/etc/pika/wifi.env" ];
    profiles = {
      ethernet = {
        connection = {
          id = "ethernet";
          type = "ethernet";
        };
        ipv4 = {
          method = "manual";
          address1 = "${ethernetAddress}/24,${router}";
          route-metric = 100;
        };
      };
      wifi = {
        connection = {
          id = "wifi";
          type = "wifi";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$WIFI_SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4 = {
          method = "manual";
          address1 = "${wifiAddress}/24,${router}";
          route-metric = 600;
        };
      };
    };
  };
  # Replies to LAN hosts route out ethernet, so the strict check drops every query sent to the Wi-Fi address.
  networking.firewall.checkReversePath = "loose";
  # The Wi-Fi password stays out of this public repo. The "-" lets ethernet come up before the file exists.
  systemd.services.NetworkManager-ensure-profiles.serviceConfig.EnvironmentFile =
    lib.mkForce "-/etc/pika/wifi.env";

  # Pi-hole owns port 53, so resolved's stub listener cannot run here.
  # Pika resolves through its own Pi-hole and falls back to Cloudflare when FTL is down.
  services.resolved.enable = lib.mkForce false;
  networking.nameservers = lib.mkBefore [ "127.0.0.1" ];
  # openresolv drops every other server when a local one is listed. Without the fallback, a boot
  # deadlocks: NTP needs DNS to find its servers, and FTL waits on time sync.
  networking.resolvconf.extraConfig = "resolv_conf_local_only=NO";
  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

  # The LAN reaches pika directly. Oak serves the tailnet only.
  services.pihole-ftl.openFirewallDNS = true;

  # The Pi has no RTC battery and boots with a stale clock, so list downloads fail TLS until NTP syncs.
  systemd.additionalUpstreamSystemUnits = [ "systemd-time-wait-sync.service" ];
  systemd.services.systemd-time-wait-sync.wantedBy = [ "sysinit.target" ];

  # The Q1000K modem's firmware hides its Dynamic DNS page, so pika tracks the dynamic WAN address.
  # The token stays out of this public repo.
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/etc/pika/cloudflare-token";
    domains = [ "home.weissfamily.us" ];
  };

  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
