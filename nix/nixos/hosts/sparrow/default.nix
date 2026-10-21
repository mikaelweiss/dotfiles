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
  resticBackups.minecraftPath = "/var/lib/minecraft";

  networking.hostName = "sparrow";

  # Elm pulls disc rips from sparrow.
  users.users.mikaelweiss.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOblJ/RxhoeC0kmf1Q0WUK9AXoH9aY3ZMzGmaOctgy/S mikaelweiss@elm"
  ];

  # Agents run on the Macs and elm. Every npm global is supply chain exposure
  # on a server that never uses it.
  npm.globalPackages = lib.mkForce [ ];

  # Static address: the port forwards on the gateway point here and must
  # survive the gateway losing its reservation table.
  networking.networkmanager.enable = false;
  networking.useDHCP = false;
  networking.interfaces.eno1.ipv4.addresses = [{
    address = "10.0.0.215";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.0.0.1";

  # Tailscale on Linux sends to a peer's IPv6 link-local address without its
  # interface zone, so replies to LAN peers never arrive. Without IPv6 on eno1
  # Tailscale can only pick working paths.
  # https://github.com/tailscale/tailscale/issues/21411
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 1;

  zramSwap.enable = true;

  system.stateVersion = "25.11";
}
