# Moving Dell media to the UGREEN NAS

Use a dedicated SMB share mounted at `/mnt/media`. Keep `/mnt/backup` for
the HDD's restic repositories until those have been migrated separately.
Mounting the NAS over `/mnt/backup` would hide the existing backups and media.

## NAS and credentials

Reserve the NAS's LAN address in DHCP. Enable SMB, create a `media` share,
and give a dedicated `dell-media` NAS account read/write access to that share.
Use the NAS directly for desktop SMB access instead of re-exporting the mount
through Dell's Samba server.

Store the following as an agenix secret, encrypted for Dell and the existing
administrator keys (follow `hosts/dell/secrets/secrets.nix`):

```ini
username=dell-media
password=YOUR_NAS_PASSWORD
```

Never put the plaintext credentials in the repository or the Nix store.

## NixOS configuration

The following mount is configured in `hosts/dell/filesystems.nix`, using the
existing encrypted secret. It takes effect after deploying Dell. Media
services still use the HDD until the migration steps below are completed.

```nix
boot.supportedFilesystems.cifs = true;
environment.systemPackages = [ pkgs.cifs-utils ];

age.secrets.ugreen-media = {
  file = ./secrets/ugreen-media.age;
  mode = "0400";
};

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
    "uid=1000"
    "gid=100"
    "forceuid"
    "forcegid"
    "file_mode=0644"
    "dir_mode=0755"
    "nosuid"
    "nodev"
    "noexec"
  ];
};
```

These ownership settings preserve the current arrangement: Axel (and
Transmission, which runs as Axel) can write; other local users, including
the media services, can read. The NAS account must independently have the
corresponding server-side permissions. Confirm SMB 3.1.1 support on the NAS.

Systemd activates the automount at boot and connects on first access. There
is deliberately no idle-unmount timeout for this service-backed share.
`nofail` lets the host boot with the NAS unavailable; it does not make media
services safe to start without their mount.

## Service integration and migration

1. Initially mount the NAS alongside the HDD. Verify `findmnt -T /mnt/media`
   reports `cifs` after accessing it, test a write as Axel and reads as
   Jellyfin, Kavita, and Navidrome, and verify Transmission's setup succeeds.
2. Copy `/mnt/backup/media/` into `/mnt/media/`. For example, use
   `rsync -rt --info=progress2 /mnt/backup/media/ /mnt/media/`; do not use
   `--delete`. Inspect any errors, including unsupported filenames or links.
3. Stop media writers and library scanners for a final sync. Verify contents
   with a checksum dry run, such as
   `rsync -rcn --itemize-changes /mnt/backup/media/ /mnt/media/`.
4. Change Transmission's download and watch directories and Navidrome's
   `MusicFolder` to the matching paths under `/mnt/media`. Update Jellyfin
   and Kavita library paths through their UIs. Keep databases, application
   state, and Transmission's incomplete downloads on Dell's internal disk.
5. Change `RequiresMountsFor` to `[ "/mnt/media" ]` for `jellyfin`, `kavita`,
   `navidrome`, `transmission`, and `transmission-setup`. Remove those services'
   `wantedBy = [ "mnt-backup.mount" ]` hooks in `filesystems.nix`; optionally
   replace them with `mnt-media.mount` hooks to start services when that
   mount is subsequently started. Keep the HDD's mountpoint lock and udev
   rule while the HDD still stores backups.
6. Disable Dell's media Samba share once clients use the NAS directly, and
   remove its HDD mount dependency/start hook if Samba is disabled entirely.
7. Reboot-test with the NAS available and unavailable. Confirm a failed mount
   prevents media services from starting and cannot send writes to the root
   filesystem. After a boot-time mount failure, restoring NAS connectivity
   may require explicitly restarting the mount and dependent services;
   automount alone does not retry failed service startup. A running SMB
   connection may reconnect after an outage, but reads/writes can still fail.

Keep the old media intact until playback, scans, downloads, and reboot tests
pass. The media tree is currently excluded from restic backups; configure
NAS protection separately. Retiring the HDD also requires migrating all
local restic repositories and their mount checks.

An idle automount may not appear as CIFS in node_exporter's filesystem
metrics until accessed. SMB capacity metrics describe the share/filesystem;
monitor NAS disk health separately.

References: [systemd mount options](https://www.man7.org/linux/man-pages/man5/systemd.mount.5.html)
and [CIFS mount options](https://www.man7.org/linux/man-pages/man8/mount.cifs.8.html).
