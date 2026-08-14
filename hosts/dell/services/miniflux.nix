{
  config,
  lib,
  pkgs,
  ...
}:
{
  # First-run admin credentials (ADMIN_USERNAME / ADMIN_PASSWORD). Only
  # consulted while the user table is empty; change the password in-app.
  age.secrets.miniflux-admin-creds.file = ../secrets/miniflux-admin-creds.age;

  # Miniflux - RSS reader (adapted from the poseidon repo). All state
  # lives in the local 'miniflux' postgres database, which the module
  # creates itself; its dump rides along in the nextcloud restic jobs
  # (see restic-backup.nix). No files on disk worth backing up.
  services.miniflux = {
    enable = true;
    adminCredentialsFile = config.age.secrets.miniflux-admin-creds.path;
    config = {
      BASE_URL = "https://rss.soderlind.dev";
      # Bind loopback only; nginx terminates TLS and, being reachable just
      # via tailscale0, is the only way in (see nginx.nix / networking.nix).
      # 18069 because beaverhabits already owns miniflux's default 8080.
      LISTEN_ADDR = "127.0.0.1:18069";
    };
  };

  # The miniflux module ships an AppArmor profile, and apparmor is enabled
  # on this host (security.nix) - unlike on poseidon. Two problems with
  # the shipped profile when postgres is reached over its unix socket:
  # the socket path isn't in the rule set, and - because the unit runs in
  # a private mount namespace (PrivateUsers etc.) - the kernel sees the
  # socket as a *disconnected path* ("Failed name lookup" in the audit
  # log), which no path rule can ever match. attach_disconnected re-roots
  # such paths at /, and the extra rule then allows the socket. Same
  # profile as upstream otherwise; drop this override when nixpkgs fixes
  # the profile.
  security.apparmor.policies."bin.miniflux".profile =
    let
      miniflux = lib.getExe config.services.miniflux.package;
    in
    lib.mkForce ''
      abi <abi/4.0>,
      include <tunables/global>

      profile ${miniflux} flags=(attach_disconnected) {
        include <abstractions/base>
        include <abstractions/nameservice>
        include <abstractions/ssl_certs>
        include <abstractions/golang>
        include "${pkgs.apparmorRulesFromClosure { name = "miniflux"; } config.services.miniflux.package}"
        ${miniflux} r,
        /run/miniflux/** rw,
        /run/postgresql/.s.PGSQL.5432 rw,
        include if exists <local/bin.miniflux>
      }
    '';
}
