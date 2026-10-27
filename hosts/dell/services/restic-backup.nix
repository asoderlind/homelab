{ config, lib, pkgs, ... }:
let
  # ---------------------------------------------------------------------
  # Hetzner Object Storage (S3-compatible) holding the off-site copy.
  # Both values must match the bucket created in the Hetzner console;
  # the endpoint is location-specific (fsn1 / nbg1 / hel1).
  # ---------------------------------------------------------------------
  offsiteEndpoint = "hel1.your-objectstorage.com";
  offsiteBucket = "nextcloud-backup-dell";

  # Both repos back up the same thing; keep one definition so they can't
  # drift apart.
  backupPaths = [
    "/var/lib/nextcloud" # data + config
    "/var/backup/postgresql" # nextcloud + miniflux .sql.gz from the prepare hook
  ];
  backupExclude = [
    # Regenerable thumbnails; can be many GB and churn constantly.
    "/var/lib/nextcloud/data/appdata_*/preview"
  ];
  # Up to 17 snapshots (~6 months of coverage): a week of dailies for
  # recent mistakes, then thinning out for slow-burn problems noticed
  # late. Dedup makes the overlap cheap.
  retention = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];

  # Fresh DB dumps; systemctl blocks until the oneshots finish and
  # propagates failure, so the dumps are always complete before the
  # snapshot. Miniflux's entire state is its database, so its dump riding
  # along in the nextcloud jobs is the whole miniflux backup.
  dumpDatabase = "systemctl start postgresqlBackup-nextcloud.service postgresqlBackup-miniflux.service";

  # Freshness metric for the textfile collector, feeding the
  # ResticBackupStale alert; postStop also runs on failure, hence the
  # SERVICE_RESULT gate.
  freshnessMetric = name: ''
    if [ "$SERVICE_RESULT" = "success" ]; then
      printf 'restic_backup_last_success_timestamp_seconds{backup="%s"} %s\n' \
        "${name}" "$(date +%s)" \
        > /var/lib/prometheus-node-exporter/textfiles/restic-${name}.prom.tmp
      mv /var/lib/prometheus-node-exporter/textfiles/restic-${name}.prom.tmp \
        /var/lib/prometheus-node-exporter/textfiles/restic-${name}.prom
    fi
  '';
in
{
  # Interactive point-in-time restore (`sudo nextcloud-restore` on the host):
  # repo + snapshot selection, typed confirmation, then stop services ->
  # restore --delete -> reload DB dump -> clear redis -> restart + files:scan.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "nextcloud-restore";
      text = builtins.readFile ../scripts/nextcloud-restore.sh;
    })
  ];

  # Repo encryption password, shared by both repos; root-owned (restic runs
  # as root). A copy must also live off-host (password manager) - without it
  # neither repo is readable, which is exactly the disaster-recovery case.
  age.secrets.restic-password.file = ../secrets/restic-password.age;
  # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for the off-site S3 repo.
  age.secrets.restic-offsite-env.file = ../secrets/restic-offsite-env.age;

  # pg_dump of the nextcloud + miniflux DBs -> /var/backup/postgresql/
  # <db>.sql.gz (atomic rename, previous copy kept as .prev). startAt = []
  # means no timer of its own: they only run synchronously from the restic
  # prepare hooks. The dumps also double as a local plaintext copy if the
  # backup drive dies.
  services.postgresqlBackup = {
    enable = true;
    databases = [
      "nextcloud"
      "miniflux"
    ];
    startAt = [ ];
  };

  # Local copy: fast to restore from, but shares a building with the server.
  services.restic.backups.nextcloud = {
    repository = "/mnt/backup/restic/nextcloud";
    passwordFile = config.age.secrets.restic-password.path;
    initialize = true; # first run creates the repo (guarded by mount check below)

    paths = backupPaths;
    exclude = backupExclude;
    pruneOpts = retention;
    # Structural repo check after every backup (runCheck auto-enables since
    # checkOpts is non-empty).
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true; # catch up if the host was off at 03:00
    };

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
      ${dumpDatabase}
    '';
    backupCleanupCommand = freshnessMetric "nextcloud";
  };

  # Off-site copy in Hetzner Object Storage: survives fire/theft/surge at
  # home. Deliberately independent of the local job and of /mnt/backup, so
  # an unplugged or dead backup drive doesn't stop off-site backups. Runs an
  # hour after the local one, which takes minutes - they never overlap.
  services.restic.backups.nextcloud-offsite = {
    repository = "s3:https://${offsiteEndpoint}/${offsiteBucket}/nextcloud";
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-offsite-env.path;
    initialize = true;

    paths = backupPaths;
    exclude = backupExclude;
    pruneOpts = retention;
    # --with-cache reuses the local metadata cache, so the daily check costs
    # very little traffic. Integrity of the off-site copy is the one thing
    # nothing else would catch.
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };

    backupPrepareCommand = ''
      set -eu
      ${dumpDatabase}
    '';
    backupCleanupCommand = freshnessMetric "nextcloud-offsite";
  };

  # Actual Budget state is all SQLite; a live-file copy is only guaranteed
  # crash-consistent if nothing is writing, so both jobs stop the service
  # for the duration. The dataset is tiny, so that's seconds of downtime at
  # night. Cleanup (which also runs on failure) restarts it unconditionally
  # before touching the freshness metric, so the app always comes back even
  # when the backup itself failed.
  services.restic.backups.actual = {
    repository = "/mnt/backup/restic/actual";
    passwordFile = config.age.secrets.restic-password.path;
    initialize = true;

    paths = [ "/var/lib/actual" ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      # 03:30: the nextcloud local job (03:00) takes minutes; stay clear of it.
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
    };

    backupPrepareCommand = ''
      set -eu
      # Same nofail-mountpoint guard as the nextcloud job: never write into
      # an empty /mnt/backup on the root fs.
      if ! mountpoint -q /mnt/backup; then
        echo "backup drive not mounted at /mnt/backup, refusing to run" >&2
        exit 1
      fi
      systemctl stop actual.service
    '';
    backupCleanupCommand = ''
      systemctl start actual.service
      ${freshnessMetric "actual"}
    '';
  };

  services.restic.backups.actual-offsite = {
    repository = "s3:https://${offsiteEndpoint}/${offsiteBucket}/actual";
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-offsite-env.path;
    initialize = true;

    paths = [ "/var/lib/actual" ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
    };

    # No mount guard: like nextcloud-offsite, this job is deliberately
    # independent of /mnt/backup.
    backupPrepareCommand = ''
      set -eu
      systemctl stop actual.service
    '';
    backupCleanupCommand = ''
      systemctl start actual.service
      ${freshnessMetric "actual-offsite"}
    '';
  };

  # Kavita follows the actual pattern exactly (SQLite state, stop the
  # service for the seconds the snapshot takes). Only the DB, covers and
  # bookmarks are worth keeping - cache/ and temp/ are regenerated reader
  # scratch space; the manga files themselves live on /mnt/backup/media
  # like the rest of the media tree and are not backed up.
  services.restic.backups.kavita = {
    repository = "/mnt/backup/restic/kavita";
    passwordFile = config.age.secrets.restic-password.path;
    initialize = true;

    paths = [ "/var/lib/kavita" ];
    exclude = [
      "/var/lib/kavita/config/cache"
      "/var/lib/kavita/config/temp"
    ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      # 03:45: clear of nextcloud (03:00) and actual (03:30).
      OnCalendar = "*-*-* 03:45:00";
      Persistent = true;
    };

    backupPrepareCommand = ''
      set -eu
      # Same nofail-mountpoint guard as the other local jobs: never write
      # into an empty /mnt/backup on the root fs.
      if ! mountpoint -q /mnt/backup; then
        echo "backup drive not mounted at /mnt/backup, refusing to run" >&2
        exit 1
      fi
      systemctl stop kavita.service
    '';
    backupCleanupCommand = ''
      systemctl start kavita.service
      ${freshnessMetric "kavita"}
    '';
  };

  services.restic.backups.kavita-offsite = {
    repository = "s3:https://${offsiteEndpoint}/${offsiteBucket}/kavita";
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-offsite-env.path;
    initialize = true;

    paths = [ "/var/lib/kavita" ];
    exclude = [
      "/var/lib/kavita/config/cache"
      "/var/lib/kavita/config/temp"
    ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      OnCalendar = "*-*-* 04:45:00";
      Persistent = true;
    };

    # No mount guard: like the other offsite jobs, deliberately independent
    # of /mnt/backup.
    backupPrepareCommand = ''
      set -eu
      systemctl stop kavita.service
    '';
    backupCleanupCommand = ''
      systemctl start kavita.service
      ${freshnessMetric "kavita-offsite"}
    '';
  };

  # Navidrome too (SQLite state, stop the service for the seconds the
  # snapshot takes). Only the DB is worth keeping - cache/ is regenerable
  # image/transcode scratch; the music files themselves live on
  # /mnt/backup/media like the rest of the media tree and are not backed up.
  services.restic.backups.navidrome = lib.mkIf config.services.navidrome.enable {
    repository = "/mnt/backup/restic/navidrome";
    passwordFile = config.age.secrets.restic-password.path;
    initialize = true;

    paths = [ "/var/lib/navidrome" ];
    exclude = [ "/var/lib/navidrome/cache" ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      # 03:15: clear of nextcloud (03:00), actual (03:30) and kavita (03:45).
      OnCalendar = "*-*-* 03:15:00";
      Persistent = true;
    };

    backupPrepareCommand = ''
      set -eu
      # Same nofail-mountpoint guard as the other local jobs: never write
      # into an empty /mnt/backup on the root fs.
      if ! mountpoint -q /mnt/backup; then
        echo "backup drive not mounted at /mnt/backup, refusing to run" >&2
        exit 1
      fi
      systemctl stop navidrome.service
    '';
    backupCleanupCommand = ''
      systemctl start navidrome.service
      ${freshnessMetric "navidrome"}
    '';
  };

  services.restic.backups.navidrome-offsite = lib.mkIf config.services.navidrome.enable {
    repository = "s3:https://${offsiteEndpoint}/${offsiteBucket}/navidrome";
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-offsite-env.path;
    initialize = true;

    paths = [ "/var/lib/navidrome" ];
    exclude = [ "/var/lib/navidrome/cache" ];
    pruneOpts = retention;
    checkOpts = [ "--with-cache" ];

    timerConfig = {
      OnCalendar = "*-*-* 04:15:00";
      Persistent = true;
    };

    # No mount guard: like the other offsite jobs, deliberately independent
    # of /mnt/backup.
    backupPrepareCommand = ''
      set -eu
      systemctl stop navidrome.service
    '';
    backupCleanupCommand = ''
      systemctl start navidrome.service
      ${freshnessMetric "navidrome-offsite"}
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

  # Same mount handling for the local actual job (see comment above).
  systemd.services.restic-backups-actual = {
    path = [ pkgs.util-linux ];
    wants = [ "mnt-backup.mount" ];
    after = [ "mnt-backup.mount" ];
  };

  # And for the local kavita job.
  systemd.services.restic-backups-kavita = {
    path = [ pkgs.util-linux ];
    wants = [ "mnt-backup.mount" ];
    after = [ "mnt-backup.mount" ];
  };

  # And for the local navidrome job.
  systemd.services.restic-backups-navidrome = lib.mkIf config.services.navidrome.enable {
    path = [ pkgs.util-linux ];
    wants = [ "mnt-backup.mount" ];
    after = [ "mnt-backup.mount" ];
  };
}
