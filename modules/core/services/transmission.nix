{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Torrent client for freely licensed media (Internet Archive, Blender open
  # movies, Linux ISOs, public-domain film). Downloads land in the Jellyfin
  # library on the external drive. Web UI at https://transmission.soderlind.dev
  # via the nginx vhost - RPC binds to localhost only, so like the other
  # services it is reachable solely over Tailscale.
  services.transmission = {
    enable = true;
    # Peer port (51413) open on all interfaces so public swarms can reach us;
    # the RPC port stays closed and is only proxied by nginx.
    openPeerPorts = true;
    openRPCPort = false;

    # The exfat mount forces uid=1000/gid=100 with umask=0022 (see
    # filesystems.nix), so only axel can write there - run the daemon as axel
    # instead of the default transmission user.
    user = "axel";
    group = "users";

    # Have transmission-setup.service create download/incomplete/watch dirs
    # before the daemon starts: the unit's sandbox bind-mounts them, so a
    # missing directory fails the whole service at namespace setup (the
    # default null skips creation entirely). 755 matches what the exfat
    # dmask yields anyway; a different mode would make chmod fail there.
    downloadDirPermissions = "755";

    settings = {
      download-dir = "/mnt/backup/media/torrents";
      # Keep in-progress downloads on the internal disk: torrents do heavy
      # random writes that exfat-over-USB handles poorly; the finished file
      # is moved to the media drive in one sequential pass.
      incomplete-dir = "/var/lib/transmission/incomplete";
      incomplete-dir-enabled = true;

      # .torrent files dropped here (e.g. via the samba media share) start
      # automatically.
      watch-dir = "/mnt/backup/media/torrents/watch";
      watch-dir-enabled = true;

      rpc-bind-address = "127.0.0.1";
      # nginx proxies with Host: transmission.soderlind.dev, which is not in
      # transmission's default host whitelist (localhost only).
      rpc-host-whitelist = "transmission.soderlind.dev";
      rpc-host-whitelist-enabled = true;

      # Seed back to the swarms we take from, but not forever.
      ratio-limit = 2.0;
      ratio-limit-enabled = true;
    };
  };

  # /mnt/backup is nofail: without this the daemon would start against an
  # empty /mnt/backup directory and download onto the root filesystem.
  systemd.services.transmission.unitConfig.RequiresMountsFor = [ "/mnt/backup" ];

  # Upstream gives transmission-setup only before=/partOf=, so nothing ever
  # pulls it in; require it from the daemon so it actually runs. It must obey
  # the same mount guard, or it would create the directories on the root
  # filesystem whenever the drive is unplugged.
  systemd.services.transmission-setup = {
    requiredBy = [ "transmission.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/backup" ];
  };
}
