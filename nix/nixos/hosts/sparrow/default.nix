{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/sites.nix
    ../../modules/cloudflared.nix
    ../../modules/minecraft.nix
    ../../modules/backups.nix
    ../../modules/dvd-ripping.nix
  ];

  resticBackups.sparrowState = true;
  minecraft.public = true;
  minecraft.private = true;
  minecraft.shire = true;
  # Bedrock players cannot wake a sleeping server.
  minecraft.alwaysOn = [ "the-shire" ];
  resticBackups.minecraftPath = "/var/lib/minecraft";

  networking.hostName = "sparrow";

  # Sparrow faces the internet, so a foothold here must not become root for free.
  security.sudo.wheelNeedsPassword = lib.mkForce true;

  # Elm pulls disc rips from sparrow.
  users.users.mikaelweiss.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOblJ/RxhoeC0kmf1Q0WUK9AXoH9aY3ZMzGmaOctgy/S mikaelweiss@elm"
  ];

  # Agents run on the Macs and elm. Every npm global is supply chain exposure
  # on a server that never uses it.
  npm.globalPackages = lib.mkForce [ ];

  # The router's port forwards point here, so reserve this address on it.
  networking.networkmanager.enable = false;
  networking.useDHCP = true;

  # Tailscale on Linux sends to a peer's IPv6 link-local address without its
  # interface zone, so replies to LAN peers never arrive. Without IPv6 on eno1
  # Tailscale can only pick working paths.
  # https://github.com/tailscale/tailscale/issues/21411
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 1;

  zramSwap.enable = true;

  system.stateVersion = "25.11";
}
