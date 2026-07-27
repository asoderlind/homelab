{ config, ... }:
{
  # JWT signing key; random, nothing else depends on it. Rotating it just
  # logs everyone out.
  age.secrets.kavita-token.file = ../../../secrets/kavita-token.age;

  # Kavita - manga/comic server with a proper web reader (RTL, webtoon
  # mode, per-user progress). Libraries are configured in-app; point them
  # at /mnt/backup/media/manga. State (SQLite DB, covers, bookmarks) lives
  # in /var/lib/kavita and is backed up by the 'kavita' restic jobs in
  # restic-backup.nix. The admin account is created on first visit.
  services.kavita = {
    enable = true;
    tokenKeyFile = config.age.secrets.kavita-token.path;
    settings = {
      # Bind loopback only; nginx terminates TLS and, being reachable just
      # via tailscale0, is the only way in (see nginx.nix / networking.nix).
      IpAddresses = "127.0.0.1";
      Port = 5000;
    };
  };

  # The library lives on the nofail media mount: without this the service
  # would start against an empty /mnt/backup and a library scan would mark
  # everything as removed.
  systemd.services.kavita.unitConfig.RequiresMountsFor = [ "/mnt/backup" ];
}
