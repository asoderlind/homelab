#!/usr/bin/env bash
# Interactive point-in-time restore of Nextcloud from either restic repo
# (local USB drive or off-site object storage). Deployed as
# `nextcloud-restore` on the host via
# modules/core/services/restic-backup.nix (writeShellApplication).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo nextcloud-restore" >&2
  exit 1
fi

echo "Which repository?"
echo "  1) local    - /mnt/backup on the USB drive (fast)"
echo "  2) offsite  - Hetzner object storage (slower; use when the drive is gone)"
read -r -p "Choice [1]: " repo_choice
case "${repo_choice:-1}" in
  1 | local)
    restic="restic-nextcloud"
    # Only the local repo needs the drive; the off-site one must stay
    # usable precisely when that drive is unavailable.
    if ! mountpoint -q /mnt/backup; then
      echo "backup drive not mounted at /mnt/backup" >&2
      exit 1
    fi
    ;;
  2 | offsite)
    restic="restic-nextcloud-offsite"
    ;;
  *)
    echo "invalid choice" >&2
    exit 1
    ;;
esac

echo
echo "Available snapshots:"
"$restic" snapshots --compact
echo

read -r -p "Snapshot ID to restore [latest]: " snapshot
snapshot=${snapshot:-latest}

# Fails (and aborts, set -e) if the ID doesn't exist in the repo.
"$restic" snapshots "$snapshot" >/dev/null

cat <<EOF

This will:
  1. stop php-fpm and background jobs (Nextcloud goes offline)
  2. restore /var/lib/nextcloud and /var/backup/postgresql from '$snapshot'
     - files not present in the snapshot are DELETED (true point-in-time;
       excluded previews vanish too and regenerate on demand)
  3. drop the current 'nextcloud' database and load the dump from the snapshot
  4. clear the Redis cache (stale after a DB rollback)
  5. restart services and re-scan files

Everything created since the snapshot will be LOST.
EOF
read -r -p "Type 'restore' to proceed: " confirm
if [ "$confirm" != "restore" ]; then
  echo "aborted, nothing changed"
  exit 1
fi

on_error() {
  echo "restore FAILED - services may still be stopped." >&2
  echo "After fixing manually, bring things back with:" >&2
  echo "  systemctl start redis-nextcloud phpfpm-nextcloud nextcloud-cron.timer" >&2
}
trap on_error ERR

echo "[1/5] stopping services..."
systemctl stop phpfpm-nextcloud nextcloud-cron.timer nextcloud-cron.service

echo "[2/5] restoring files from '$snapshot'..."
# restic refuses '--target / --delete' without an explicit filter; the
# includes also scope what --delete is allowed to remove.
"$restic" restore "$snapshot" --target / --delete \
  --include /var/lib/nextcloud --include /var/backup/postgresql
chown -R nextcloud:nextcloud /var/lib/nextcloud

echo "[3/5] restoring database from the snapshot's dump..."
# The dump was restored in step 2, so it matches the files. It was made with
# pg_dump -C: drop, then recreate by loading it against the postgres DB.
sudo -u postgres dropdb --force --if-exists nextcloud
zcat /var/backup/postgresql/nextcloud.sql.gz | sudo -u postgres psql -q -d postgres

echo "[4/5] clearing redis cache..."
# Redis persists an RDB dump, so a plain restart would reload the stale cache.
systemctl stop redis-nextcloud
rm -f /var/lib/redis-nextcloud/dump.rdb
systemctl start redis-nextcloud

echo "[5/5] starting services and re-scanning files..."
systemctl start phpfpm-nextcloud nextcloud-cron.timer
nextcloud-occ files:scan --all
nextcloud-occ status

echo
echo "Restore complete - verify in the browser at https://drive.soderlind.dev"
