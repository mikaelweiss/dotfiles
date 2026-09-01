{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-SK_hynix_PC601_HFS512GD9TNG-L2A0A_FN08N87031070940G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
