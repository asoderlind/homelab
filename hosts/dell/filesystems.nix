{
  config,
  lib,
  pkgs,
  ...
}:

{
  # In-kernel exfat driver + exfatprogs for fsck
  boot.supportedFilesystems.exfat = true;

  boot.supportedFilesystems.cifs = true;
  environment.systemPackages = [ pkgs.cifs-utils ];

  age.secrets.ugreen-media = {
    file = ./secrets/ugreen-media.age;
    mode = "0400";
  };

  # Mount alongside the HDD for migration; connect on first access without
  # blocking boot when the NAS is unavailable. Match the HDD's ownership.
  fileSystems."/mnt/media" = {
    device = "//192.168.1.224/media";
    fsType = "cifs";
    options = [
      "credentials=${config.age.secrets.ugreen-media.path}"
      "vers=3.1.1"
      "_netdev"
      "nofail"
      "x-systemd.automount"
      "x-systemd.mount-timeout=30s"
      "uid=1000" # axel
      "gid=100" # users
      "forceuid"
      "forcegid"
      "file_mode=0644"
      "dir_mode=0755"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };

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

  # systemd pulls fstab mounts in exactly once, from local-fs.target at boot;
  # nothing retriggers a nofail mount when its device turns up later. So
  # plugging the drive in after boot does nothing, and a slow spin-up that
  # misses the device-timeout above is permanent until the next reboot. Have
  # udev start the mount unit when the partition appears. Unlike
  # x-systemd.automount this leaves /proc/mounts showing a real exfat mount,
  # so node_exporter keeps reporting it.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="676D-8169", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-backup.mount"
  '';

  # With the drive absent, /mnt/backup is a plain directory on the root
  # filesystem: writes there fill the SSD and are then silently shadowed once
  # the drive mounts (this is how a stray media/torrents tree ends up on /).
  # Set the immutable bit on the underlying directory so such writes fail
  # loudly instead of succeeding in the wrong place. The bit lives on the
  # root-fs inode - mounting over it still works, and the drive's own root is
  # untouched. To write there deliberately: chattr -i /mnt/backup.
  systemd.services.backup-mountpoint-lock = {
    description = "Lock /mnt/backup against writes while the drive is unmounted";
    # Before the mount, so it always sees the bare directory. wantedBy rather
    # than requiredBy: a failure here must never stop the drive mounting.
    wantedBy = [ "mnt-backup.mount" ];
    before = [ "mnt-backup.mount" ];
    # The default dependencies order services after sysinit.target, which is
    # itself after the mounts - that would be a cycle.
    unitConfig.DefaultDependencies = false;
    after = [ "local-fs-pre.target" ];
    path = [ pkgs.e2fsprogs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /mnt/backup
      if [ -n "$(ls -A /mnt/backup)" ]; then
        echo "/mnt/backup is not empty on the root filesystem: something wrote there while the drive was unplugged" >&2
      fi
      chattr +i /mnt/backup
    '';
  };

  # RequiresMountsFor gives these a Requires= on the mount, which propagates
  # the stop when the drive goes away but never starts them again when it
  # comes back. Let the mount pull them in, so replugging restores the stack
  # without a reboot. Their own After= on the mount keeps the ordering right.
  systemd.services.jellyfin.wantedBy = [ "mnt-backup.mount" ];
  systemd.services.kavita.wantedBy = [ "mnt-backup.mount" ];
  systemd.services.navidrome = lib.mkIf config.services.navidrome.enable {
    wantedBy = [ "mnt-backup.mount" ];
  };
  systemd.services.samba-smbd.wantedBy = [ "mnt-backup.mount" ];
  systemd.services.transmission.wantedBy = [ "mnt-backup.mount" ];
}
