{ ... }:
{
  # Actual Budget sync server. All state (SQLite account DB plus the
  # per-budget user files, which are SQLite too) lives in /var/lib/actual
  # and is backed up by the 'actual' restic jobs in restic-backup.nix.
  # No secrets: the server password is set in-app on first visit.
  services.actual = {
    enable = true;
    settings = {
      # Bind loopback only; nginx terminates TLS and, being reachable just
      # via tailscale0, is the only way in (see nginx.nix / networking.nix).
      hostname = "127.0.0.1";
      port = 5006;
    };
  };
}
