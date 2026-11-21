# Backups and recovery

[← Overview](../README.md)

## Backups (restic → /mnt/backup)

Daily (03:00, `Persistent` so missed runs catch up) restic backup of
`/var/lib/nextcloud` plus fresh pg_dumps of the nextcloud **and miniflux**
databases (`/var/backup/postgresql/*.sql.gz`) into the encrypted repo
`/mnt/backup/restic/nextcloud` on the external USB drive. Miniflux's
entire state is its database, so the dump riding along here is the whole
miniflux backup. Retention:
7 daily + 4 weekly + 6 monthly snapshots (up to 17, ~6 months of
coverage), pruned and checked after each run.

A second job (`nextcloud-offsite`, 04:00 daily, same paths and retention)
pushes an encrypted copy to Hetzner Object Storage, because the USB drive
shares a building with the server and would not survive fire, theft, or a
power surge. It is deliberately independent of `/mnt/backup`, so off-site
backups keep running when the drive is unplugged or dead.

Actual Budget gets the same treatment: an `actual` job pair (local 03:30,
off-site 04:30, same retention) for `/var/lib/actual`. Its state is all
SQLite, so both jobs stop `actual.service` for the seconds the snapshot
takes and restart it afterwards, even when the backup fails.

Kavita likewise: a `kavita` job pair (local 03:45, off-site 04:45) for
`/var/lib/kavita` (SQLite DB, covers, bookmarks — `cache/` and `temp/`
excluded), stopping `kavita.service` the same way. The manga files
themselves live under `/mnt/backup/media` and, like the rest of the media
tree, are not backed up.

Navidrome the same again: a `navidrome` job pair (local 03:15, off-site
04:15) for `/var/lib/navidrome` (SQLite DB — the regenerable
image/transcode `cache/` excluded), stopping `navidrome.service` for the
snapshot. The music files live under `/mnt/backup/media` and are not
backed up.

All repos use the same `restic-password` secret; the off-site ones also
need `restic-offsite-env` (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`).
The endpoint and bucket are set at the top of
`hosts/dell/services/restic-backup.nix`.

The repo password is the `restic-password` agenix secret — **also keep a
copy in the password manager**; without it the repo is unreadable.

If the drive is unplugged the run fails loudly (`SystemdUnitFailed`
alert); more than 3 days without a successful run fires
`ResticBackupStale`.

```sh
sudo systemctl start restic-backups-nextcloud           # manual run (blocks)
sudo systemctl start restic-backups-nextcloud-offsite   # same, off-site repo
sudo restic-nextcloud snapshots                         # wrapper, repo/password preset
sudo restic-nextcloud-offsite snapshots
```

### Restore

```sh
sudo nextcloud-restore
```

Interactive: asks which repo (local or off-site — pick off-site when the
USB drive is gone), lists snapshots, asks which to restore (default `latest`),
requires typing `restore` to confirm, then stops php-fpm/cron, restores
files with `--delete` (true point-in-time — files created after the
snapshot are removed), reloads the DB from the snapshot's dump, clears the
Redis cache, restarts services, and re-scans files. Source:
`hosts/dell/scripts/nextcloud-restore.sh`. For a non-destructive look inside a
snapshot instead: `sudo restic-nextcloud restore latest --target /tmp/restore`.
