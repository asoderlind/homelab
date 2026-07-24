# nixos-homelab-dell

NixOS configuration for the Dell homelab. Services are tailnet-only: nginx
terminates TLS with a wildcard `*.soderlind.dev` cert (ACME DNS-01 via
Cloudflare) and nothing but SSH is exposed outside `tailscale0`.

Most things are declarative, but a few steps are manual. This is the list.

## Deploying

Always done manually, from the repo root:

```sh
nix run nixpkgs#deploy-rs -- .#nixos    # or `deploy .#nixos`
```

deploy-rs builds remotely on the host and auto-rolls-back if activation
fails (e.g. a unit fails to start during the switch). Validate before
deploying:

```sh
nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
```

Note: flake eval only sees files known to git — `git add` new files
(including `.age` secrets) or they don't exist as far as nix is concerned.

## Secrets (agenix)

Recipients are defined in `secrets/secrets.nix` (server host key + laptop
key). To create or edit a secret, from `secrets/`:

```sh
EDITOR=vim agenix -e <name>.age -i ~/.ssh/id_ed25519
```

After editing, **verify the content is non-empty** — a scripted/failed
editor session can silently encrypt an empty string, which passes eval and
only blows up at activation time:

```sh
agenix -d <name>.age -i ~/.ssh/id_ed25519 | wc -c
```

On the host, decrypted secrets appear under `/run/agenix/<name>`.

## Adding a new service subdomain

1. All `*.soderlind.dev` names already resolve to the host's tailscale IP
   (wildcard record in the Cloudflare zone, DNS-only/grey cloud) and are
   covered by the wildcard cert — usually no DNS or cert work needed.
2. Add an nginx vhost with `forceSSL = true; useACMEHost = "soderlind.dev";`
   (never per-vhost `enableACME`: HTTP-01 can't reach a tailnet-only host).
3. Don't open firewall ports — `tailscale0` is a trusted interface.

## Nextcloud (drive.soderlind.dev)

First-time setup after the initial deploy:

1. **Admin password**: initial value comes from the `nextcloud-admin-pass`
   secret (used only at install time). Read it with
   `sudo cat /run/agenix/nextcloud-admin-pass`, log in as `admin`, change
   it in the UI if you like.
2. **Register the serverinfo token** (one-time; the Prometheus exporter
   authenticates with it, but Nextcloud stores its copy in the DB):

   ```sh
   sudo nextcloud-occ config:app:set serverinfo token \
     --value "$(sudo cat /run/agenix/nextcloud-serverinfo-token)"
   sudo systemctl restart prometheus-nextcloud-exporter
   ```

   Re-run both after rotating the `nextcloud-serverinfo-token` secret.
3. **Verify**:

   ```sh
   sudo nextcloud-occ status                                  # installed: true
   curl -s http://127.0.0.1:9205/metrics | grep nextcloud_up  # nextcloud_up 1
   sudo fail2ban-client status nextcloud                      # jail active
   ```

### Troubleshooting

- **Exporter reports "too many requests" / `nextcloud_up 0` with a correct
  token**: the serverinfo endpoint is brute-force protected. Failed auth
  attempts (e.g. from a stale token) lock out the source IP — which is the
  host's own tailscale IP, since the exporter probes via
  `https://drive.soderlind.dev` — for up to 12h. Check and reset:

  ```sh
  sudo nextcloud-occ security:bruteforce:attempts <host tailscale IP>
  sudo nextcloud-occ security:bruteforce:reset <host tailscale IP>
  ```

- **A tailnet device gets banned by fail2ban** (3 failed Nextcloud logins):

  ```sh
  sudo fail2ban-client set nextcloud unbanip <ip>
  ```

- **Major Nextcloud upgrades** are not automatic: bump `pkgs.nextcloudNN`
  in `modules/core/services/nextcloud.nix` one major version at a time and
  deploy.

## Backups (restic → /mnt/backup)

Weekly (Sun 03:00, `Persistent` so missed runs catch up) restic backup of
`/var/lib/nextcloud` plus a fresh pg_dump
(`/var/backup/postgresql/nextcloud.sql.gz`) into the encrypted repo
`/mnt/backup/restic/nextcloud` on the external USB drive. Retention:
4 weekly + 6 monthly snapshots, pruned and checked after each run.

The repo password is the `restic-password` agenix secret — **also keep a
copy in the password manager**; without it the repo is unreadable.

If the drive is unplugged the run fails loudly (`SystemdUnitFailed`
alert); more than 8 days without a successful run fires
`ResticBackupStale`.

```sh
sudo systemctl start restic-backups-nextcloud   # manual run (blocks)
sudo restic-nextcloud snapshots                 # wrapper with repo/password preset
sudo restic-nextcloud stats
```

### Restore

```sh
sudo nextcloud-restore
```

Interactive: lists snapshots, asks which to restore (default `latest`),
requires typing `restore` to confirm, then stops php-fpm/cron, restores
files with `--delete` (true point-in-time — files created after the
snapshot are removed), reloads the DB from the snapshot's dump, clears the
Redis cache, restarts services, and re-scans files. Source:
`scripts/nextcloud-restore.sh`. For a non-destructive look inside a
snapshot instead: `sudo restic-nextcloud restore latest --target /tmp/restore`.

## Monitoring

Prometheus (`:9001`) + Alertmanager → Telegram. Alert rules live in
`modules/core/services/alertmanager.nix`; exporters and scrape jobs live in
each service's own module. Grafana at `grafana.soderlind.dev`.
