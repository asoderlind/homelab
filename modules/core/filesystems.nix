{
  config,
  lib,
  pkgs,
  ...
}:

{
  # In-kernel exfat driver + exfatprogs for fsck
  boot.supportedFilesystems.exfat = true;

  # External 1.8T USB drive (label "Backup"). Deliberately not using
  # x-systemd.automount: an automount unit appears in /proc/mounts as fstype
  # autofs, which node_exporter's filesystem collector excludes by default, so
  # the drive would drop off the storage dashboard until something touched it.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/676D-8169";
    fsType = "exfat";
    options = [
      "nofail" # never block boot if the drive is unplugged
      "x-systemd.device-timeout=10s"
      # exfat has no Unix permissions; ownership comes from the mount options
      "uid=1000" # axel
      "gid=100" # users
      "umask=0022"
    ];
  };
}
