{ pkgs, inputs, ... }:

let
  makemkv = (import inputs.nixpkgs-makemkv {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  }).makemkv;
in
{
  # MakeMKV talks to the drive through the SCSI generic device.
  boot.kernelModules = [ "sg" ];
  users.users.mikaelweiss.extraGroups = [ "cdrom" ];

  environment.systemPackages = with pkgs; [
    ffmpeg
    libdvdcss
    dvdbackup
    handbrake
    makemkv
  ];
}
