{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/sites.nix
    ../../modules/cloudflared.nix
    ../../modules/minecraft.nix
    ../../modules/backups.nix
  ];

  resticBackups.sparrowState = true;
  minecraft.public = true;
  resticBackups.minecraftPath = "/var/lib/minecraft";

  networking.hostName = "sparrow";

  environment.systemPackages = with pkgs; [
    python3 # Claude Code hooks shell out to it
  ];

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
