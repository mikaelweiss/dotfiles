{ config, pkgs, lib, ... }:

{
  imports = [
    ../../common.nix
    ./hardware.nix
    ./disko.nix
    ../../modules/sites.nix
    ../../modules/cloudflared.nix
    ../../modules/minecraft.nix
    ../../modules/backups.nix
    ../../modules/ddns.nix
  ];

  networking.hostName = "sparrow";

  # Static address: the port forwards on the gateway point here, and the
  # gateway sees this box through an extender that rewrites its MAC, so a
  # DHCP reservation cannot be trusted to stick.
  networking.networkmanager.enable = false;
  networking.useDHCP = false;
  networking.interfaces.eno1.ipv4.addresses = [{
    address = "10.0.0.214";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.0.0.1";

  zramSwap.enable = true;

  system.stateVersion = "25.11";
}
