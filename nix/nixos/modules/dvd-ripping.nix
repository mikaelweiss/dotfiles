{ pkgs, ... }:

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
