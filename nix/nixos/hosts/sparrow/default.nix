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
