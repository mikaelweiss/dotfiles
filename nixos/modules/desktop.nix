{ config, pkgs, noctalia, ... }:

{
  imports = [ noctalia.nixosModules.default ];

  programs.niri.enable = true;

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    recommendedServices.enable = true;
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
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
    ghostty
    firefox
    signal-desktop
    xwayland-satellite
    wl-clipboard
    nautilus
  ];
}
