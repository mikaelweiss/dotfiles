{ config, pkgs, noctalia, ... }:

let
  noctalia-shell = noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Noctalia's flake pins its own nixpkgs; its cachix serves those builds.
  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  programs.niri.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --cmd niri-session";
      user = "greeter";
    };
  };

  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  fonts.packages = with pkgs; [
    meslo-lgs-nf
    nerd-fonts.jetbrains-mono
  ];

  environment.systemPackages = with pkgs; [
    noctalia-shell
    xwayland-satellite
    ghostty
    firefox
    signal-desktop
    nautilus
    wl-clipboard
    brightnessctl
    pavucontrol
    libnotify
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
