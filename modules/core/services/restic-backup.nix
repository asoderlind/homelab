{ config, pkgs, ... }:
{
  # Interactive point-in-time restore (`sudo nextcloud-restore` on the host):
  # snapshot selection, typed confirmation, then stop services -> restic
  # restore --delete -> reload DB dump -> clear redis -> restart + files:scan.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "nextcloud-restore";
      text = builtins.readFile ../../../scripts/nextcloud-restore.sh;
    })
  ];

  # Repo encryption password; root-owned (restic runs as root). A copy must
  # also live off-host (password manager) - without it the repo is unreadable.
  age.secrets.restic-password.file = ../../../secrets/restic-password.age;

  # pg_dump of the nextcloud DB -> /var/backup/postgresql/nextcloud.sql.gz
  # (atomic rename, previous copy kept as .prev). startAt = [] means no timer
  # of its own: it only runs synchronously from the restic prepare hook, so
  # the dump is always fresh and complete before the snapshot. The dump also
  # doubles as a local plaintext copy if the backup drive dies.
  services.postgresqlBackup = {
    enable = true;
    databases = [ "nextcloud" ];
    startAt = [ ];
  };

  services.restic.backups.nextcloud = {
    repository = "/mnt/backup/restic/nextcloud";
    passwordFile = config.age.secrets.restic-password.path;
    initialize = true; # first run creates the repo (guarded by mount check below)

    paths = [
      "/var/lib/nextcloud" # data + config
      "/var/backup/postgresql" # nextcloud.sql.gz from the prepare hook
    ];
    exclude = [
      # Regenerable thumbnails; can be many GB and churn constantly.
      "/var/lib/nextcloud/data/appdata_*/preview"
    ];

    timerConfig = {
      OnCalendar = "Sun *-*-* 03:00:00";
      Persistent = true; # catch up if the host was off on Sunday
    };

    pruneOpts = [
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    # Structural repo check after every backup (runCheck auto-enables since
    # checkOpts is non-empty).
    checkOpts = [ "--with-cache" ];

    backupPrepareCommand = ''
      set -eu
      # /mnt/backup is nofail: if the drive is absent we would otherwise write
      # into the empty mountpoint on the root fs. Fail loudly instead (unit
      # 'failed' -> SystemdUnitFailed alert). Runs before 'restic init', so a
      # repo can never be created on /.
      if ! mountpoint -q /mnt/backup; then
        echo "backup drive not mounted at /mnt/backup, refusing to run" >&2
        exit 1
      fi
      # Fresh DB dump; systemctl blocks until the oneshot finishes and
      # propagates failure.
      systemctl start postgresqlBackup-nextcloud.service
    '';

    # Freshness metric for the textfile collector, feeding the
    # ResticBackupStale alert; postStop also runs on failure, hence the
    # SERVICE_RESULT gate.
    backupCleanupCommand = ''
      if [ "$SERVICE_RESULT" = "success" ]; then
        printf 'restic_backup_last_success_timestamp_seconds{backup="nextcloud"} %s\n' "$(date +%s)" \
          > /var/lib/prometheus-node-exporter/textfiles/restic-nextcloud.prom.tmp
        mv /var/lib/prometheus-node-exporter/textfiles/restic-nextcloud.prom.tmp \
          /var/lib/prometheus-node-exporter/textfiles/restic-nextcloud.prom
      fi
    '';
  };

  systemd.tmpfiles.rules = [ "d /var/lib/prometheus-node-exporter/textfiles 0755 root root -" ];

  # Attempt the mount when the backup starts (nofail means nothing auto-mounts
  # after a replug). Deliberately Wants, not Requires/RequiresMountsFor: a
  # failed Requires dependency cancels the start job and leaves the unit
  # 'inactive' (silent, no alert); with Wants the unit still starts and the
  # mountpoint check above fails it loudly.
  systemd.services.restic-backups-nextcloud = {
    # mountpoint(1) for the prepare hook: util-linux is not in the default
    # unit PATH, and 'command not found' (127) would read as 'not mounted'.
    path = [ pkgs.util-linux ];
    wants = [ "mnt-backup.mount" ];
    after = [ "mnt-backup.mount" ];
  };
}
