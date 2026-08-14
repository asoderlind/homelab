{ config, ... }:
{
  # Navidrome - music streaming server with a web player and a
  # Subsonic-compatible API (mobile apps like Symfonium/substreamer point
  # at the same URL). The library is /mnt/backup/media/music; state
  # (SQLite DB, image/transcode cache) lives in /var/lib/navidrome and is
  # backed up by the 'navidrome' restic jobs in restic-backup.nix. The
  # admin account is created on first visit.
  services.navidrome = {
    enable = true;
    settings = {
      # Bind loopback only; nginx terminates TLS and, being reachable just
      # via tailscale0, is the only way in (see nginx.nix / networking.nix).
      Address = "127.0.0.1";
      Port = 4533;
      MusicFolder = "/mnt/backup/media/torrents/music";
      # No anonymous usage reporting from the homelab.
      EnableInsightsCollector = false;
    };
  };

  # The library lives on the nofail media mount: without this the service
  # would start against an empty /mnt/backup and a scan would mark the
  # whole library as missing.
  systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/mnt/backup" ];
}
