{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  networking.hostName = "oak";
  networking.networkmanager.enable = false;

  # Tailscale on Linux sends to a peer's IPv6 link-local address without its
  # interface zone, so replies to LAN peers never arrive. Without IPv6 on eno1
  # Tailscale can only pick working paths.
  # https://github.com/tailscale/tailscale/issues/21411
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 1;

  # Every client pins oak's host keys, including the ECDSA one NixOS skips by default.
  services.openssh.hostKeys = [
    { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
    { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
    { type = "ecdsa"; path = "/etc/ssh/ssh_host_ecdsa_key"; }
  ];

  # Restic clients that push to ~/backups and ~/pg-backup over sftp.
  users.users.mikaelweiss.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOblJ/RxhoeC0kmf1Q0WUK9AXoH9aY3ZMzGmaOctgy/S mikaelweiss@elm"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvnGvSvnLqfQzfxIoSGA0AdjPRyQGiNC2vVywkFg/pa mikaelweiss@sparrow"
    ''restrict,command="internal-sftp" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFQ1CCxRjR9eT2fh51oqbrV6lrcnaAhphAJBRkQC9Qy pg-backup@pip''
  ];

  hardware.cpu.amd.updateMicrocode = true;
  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
