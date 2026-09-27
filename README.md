# NixOS homelab

One flake manages two x86_64 NixOS hosts:

- `dell` runs the existing homelab services. They are tailnet-only: nginx
  terminates TLS with a wildcard `*.soderlind.dev` cert (ACME DNS-01 via
  Cloudflare), and nothing but SSH is exposed outside `tailscale0`.
- `hyperion` is the HP EliteDesk agent lab: a pinned Buzz production Compose
  stack, Forgejo, an isolated Actions runner, and three owner-gated ACP agents.

Host entry points and generated hardware settings live under `hosts/`.
`modules/common/default.nix` is the baseline imported by both hosts. Dell-only
storage, services, secrets, scripts, Podman configuration, and hardware
workarounds live under `hosts/dell/`.

Most things are declarative, but a few steps are manual. This is the list.

## Hardware

The machine inventory, network hardware, storage, monitoring labels, and 12U
rack layout are documented in [docs/hardware.md](docs/hardware.md).

## Networking

The tailnet-only ingress model, DNS and TLS setup, vhost routing, and
Transmission's isolated Proton VPN egress are documented in
[docs/networking.md](docs/networking.md).

## Deploying

Deployments are manual and host-specific. Validate both configurations and
the deploy-rs schema from the repo root:

```sh
nix flake check --no-build
nix eval --raw .#nixosConfigurations.dell.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.hyperion.config.system.build.toplevel.drvPath
```

Then deploy only the intended host:

```sh
nix run nixpkgs#deploy-rs -- .#dell
nix run nixpkgs#deploy-rs -- .#hyperion
# Equivalent if deploy-rs is installed: deploy .#dell / deploy .#hyperion
```

Both nodes build remotely and auto-roll back if activation fails. `hyperion`
uses the `Host hyperion` entry in `~/.ssh/config`; the shared security module
allows the `axel` wheel user to activate deployments without a sudo password.

Note: flake eval only sees files known to git — `git add` new files
(including `.age` secrets) or they don't exist as far as nix is concerned.

## Hyperion agent lab

Hyperion follows Buzz's production single-node Compose layout rather than a
development Compose file or an XMPP substitute. The pinned bundle runs the
Buzz relay with PostgreSQL, Redis, MinIO, its Git data volume, and a stateless
NIP-AB device-pairing sidecar. nginx exposes only the sidecar's exact `/pair`
WebSocket path, and the main relay advertises it to Buzz clients as
`wss://buzz.soderlind.dev/pair`. Forgejo is at
`https://forgejo.soderlind.dev`; Buzz is at
`https://buzz.soderlind.dev` (`wss://buzz.soderlind.dev` for relay clients). See
[docs/networking.md](docs/networking.md) for its DNS, TLS, nginx, and Tailscale
ingress design.

When moving an already-bootstrapped lab from `hyperion:3000` to the HTTPS
hostname, deploy first and rerun `sudo buzz-bootstrap` without a public-key
argument. It preserves the existing relay and agent private keys, rewrites only
the non-secret endpoint settings, and registers those identities in the new
`buzz.soderlind.dev` community. Select `wss://buzz.soderlind.dev` as the relay
in Buzz Desktop, then recreate the desired channels and add the agents. The old
`hyperion:3000` community remains untouched in PostgreSQL and is not exposed or
deleted automatically. Forgejo keeps its existing database and repositories;
only its canonical URL changes.

The three workers are independent Hermes `v2026.8.13` gateways running as
`agent-coordinator`, `agent-developer`, and `agent-ops`. Hermes talks to Buzz
natively and authenticates to `gpt-5.6-terra` through the `openai-codex`
ChatGPT/Codex OAuth provider. There is no API-key or OpenRouter fallback. Each
role has a separate Unix user, Hermes home, OAuth store, Buzz identity,
Mnemosyne `v3.15.1` SQLite database, workspace, mutable skills, sessions, and
Forgejo token. All three share one ChatGPT account quota but no credential file.

Each gateway has one top-level active session, at most two flat Terra
subagents, manual command approval, immutable deny rules for privilege,
deployment, destructive deletion, forced pushes, containers, and host
management, plus `MemoryHigh=2G`, `MemoryMax=3G`, `CPUQuota=150%`, and 512 tasks.
The users are not in `wheel` or `docker`, cannot traverse another role's home,
and have only their own home writable. Hyperion also has 25% zram swap for
short-lived memory bursts.

Linear is the authoritative task surface. Each role also exposes an
authenticated Hermes API on a distinct loopback-only port and runs a small
outbound polling bridge. A Cloudflare Worker receives signed Linear Agent
Session webhooks and queues them in D1, so no Hyperion port is public. Humans
remain accountable as Agent Session creators while the Coordinator, Developer,
or Ops app handles the delegated work. Forgejo remains the source and
pull-request host; Buzz remains a
private fallback communication path. See
[`integrations/linear-agent-relay/README.md`](integrations/linear-agent-relay/README.md)
for the Worker, OAuth application, secret, and smoke-test bootstrap.

### First deployment and bootstrap

Run these steps in order:

1. Deploy the configuration, then join the host to the tailnet if necessary:

   ```sh
   nix run nixpkgs#deploy-rs -- .#hyperion
   ssh hyperion sudo tailscale up
   ```

2. In Buzz Desktop, create or select your human identity and copy its 64-byte
   hex public key. Bootstrap the closed relay and three agent identities:

   ```sh
   ssh hyperion sudo buzz-bootstrap YOUR_64_CHARACTER_HEX_PUBKEY
   ```

   The command creates the stable Compose secrets under
   `/var/lib/buzz/compose/.env`, starts the upstream stack, registers the agent
   identities, and publishes their profiles. Re-running it is safe and retains
   the keys. It also writes the private human/agent allowlists used by Hermes.
   Existing `*-model.env` files are ignored and deliberately not deleted.
   Existing Forgejo, Linear relay, and Hermes API entries in each role's
   environment file are preserved.

3. Create the initial Forgejo administrator from the host:

   ```sh
   ssh hyperion
   sudo -u forgejo forgejo admin user create \
     --work-path /var/lib/forgejo \
     --config /var/lib/forgejo/custom/conf/app.ini \
     --username asoderlind --email axel@soderlind.dev --admin \
     --password 'forgejo'
   sudo forgejo-runner-bootstrap
   ```

   Log in at `https://forgejo.soderlind.dev`, create the private `agent-wiki`
   repository,
   and create one least-privilege account and scoped token for each role. Grant
   only the repository and issue permissions that role needs; do not grant
   administrator, Actions administration, or package permissions. Add
   branch protection to `main`, require human review, disable automatic merge,
   and do not let any agent account bypass protection. Add
   each account and token to its existing root-owned environment file:

   ```sh
   sudoedit /var/lib/agent-lab/secrets/coordinator.env
   sudoedit /var/lib/agent-lab/secrets/developer.env
   sudoedit /var/lib/agent-lab/secrets/ops.env
   ```

   Preserve the generated Buzz entries and add the Forgejo values below. The
   Linear relay setup adds its own values to these same files later:

   ```ini
   FORGEJO_USERNAME=agent-coordinator
   FORGEJO_TOKEN=replace-with-this-role-token
   ```

   Use the matching account in each file. `buzz-bootstrap` preserves these
   Forgejo lines when rerun. The runner remains container-only with concurrency,
   CPU, memory, and PID limits; it exposes no host label, Docker socket, auto
   merge, or deployment path.

4. Authenticate each Hermes home with the ChatGPT account. The helper stops
   only that role, starts Hermes's device-code login as the role user, verifies
   its private `auth.json`, and safely restarts the service when Buzz is ready:

   ```sh
   ssh -t hyperion sudo agent-lab-auth coordinator
   ssh -t hyperion sudo agent-lab-auth developer
   ssh -t hyperion sudo agent-lab-auth ops
   ```

   Complete the URL/code flow in a browser for every role. This is subscription
   authentication, not an OpenAI Platform API key. Eligibility and quota remain
   provider-controlled, so validate each role with a real first inference.

5. Initialize the Forgejo-backed Obsidian wiki and the three private clones:

   ```sh
   ssh hyperion sudo agent-lab-wiki-bootstrap axel
   ```

   If `/var/lib/agent-lab/wiki.git` contains commits and `agent-wiki` is empty,
   the helper pushes its branches and tags first. The old bare repository and a
   migration mirror are retained. If Forgejo already has content, it refuses to
   overwrite it. Credentials are supplied through an immutable askpass helper;
   they are never written into Git remotes or command lines. Existing clones
   must be clean and pull with rebase; any conflict stops for human resolution.

6. Start and inspect all gateways:

   ```sh
   sudo systemctl start agent-lab-{coordinator,developer,ops}.service
   sudo systemctl status agent-lab-{coordinator,developer,ops}.service
   ```

7. Clone the same repository on the Mac and open it as an Obsidian vault. Let
   Git prompt for the Forgejo username and a separate Mac-scoped token so the
   token does not become part of the remote URL:

   ```sh
   git -c credential.helper=osxkeychain clone \
     https://forgejo.soderlind.dev/axel/agent-wiki.git ~/Documents/agent-wiki
   git -C ~/Documents/agent-wiki config pull.rebase true
   open -a Obsidian ~/Documents/agent-wiki
   ```

### Smoke checks

After activation and OAuth login, make one real subscription-backed inference
per role, then test one Linear delegation and follow-up plus one Buzz DM and one
mention-gated channel request per role. Verify a linked Linear child-issue
handoff does not loop, a one-time approval works while permanent approval is
unavailable, a Forgejo pull request is linked back to Linear, and queued work
survives a bridge restart. Also store and recall a Mnemosyne memory across a
gateway restart, spawn two flat Terra subagents (and confirm a nested spawn is
rejected), and push a wiki commit that the Mac pulls. Finally confirm each user
cannot read the other two homes and cannot use sudo, Docker, merge, deploy,
force-push, or run host-management commands.

Useful checks:

```sh
sudo systemctl status buzz-compose forgejo
sudo docker compose --project-directory /var/lib/buzz/compose \
  --env-file /var/lib/buzz/compose/.env \
  -f /var/lib/buzz/compose/compose.yml ps
sudo systemctl status agent-lab-{coordinator,developer,ops}
sudo journalctl -u agent-lab-developer -f
```

### Portable state and backup boundary

This change does not configure off-host backups. Before treating the lab as
durable, back up all of the following:

- Hermes profiles, sessions, mutable skills, and workspaces:
  `/var/lib/agent-lab/agents/{coordinator,developer,ops}/`
- Role OAuth stores: each role's `.hermes/auth.json` (treat as a credential)
- Private Mnemosyne banks: each role's
  `.hermes/mnemosyne/data/mnemosyne.db` plus SQLite WAL/SHM files
- Buzz identities, Forgejo tokens, Linear relay tokens, and Hermes loopback API
  keys: `/var/lib/agent-lab/secrets/` (treat all as credentials)
- Cloudflare D1 relay state and Worker secrets; these live outside Hyperion and
  are not covered by the host's filesystem backup
- Buzz Compose secrets: `/var/lib/buzz/compose/.env`
- Buzz named volumes: `buzz-postgres-data`, `buzz-redis-data`,
  `buzz-minio-data`, and `buzz-git-data`
- Forgejo state and four weeks of daily dumps under `/var/lib/forgejo/`
- The canonical `agent-wiki` Forgejo repository, every role clone, and the Mac
  Obsidian clone; retain `/var/lib/agent-lab/wiki.git` and
  `/var/lib/agent-lab/wiki-migration.git` when present

The Nix-managed `SOUL.md`, shared `AGENTS.md`, and `nix-managed-*` skills are
reproducible from this repository. Any additional skills placed beside the
managed skill link in a role's `.hermes/skills/` directory are mutable state and
must be backed up.

## Secrets (agenix)

Recipients are defined in each host's `secrets/secrets.nix` (server host key +
laptop key). Hyperion and Dell have separate encrypted copies of the
Cloudflare ACME environment file so each host decrypts only its own file. To
create or edit a secret, enter the relevant host's secrets directory:

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
  in `hosts/dell/services/nextcloud.nix` one major version at a time and
  deploy.

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

## Actual Budget (actual.soderlind.dev)

No secrets in the repo: the server password is created in-app. **Set it by
visiting `https://actual.soderlind.dev` right after the first deploy** — an
unconfigured server accepts whatever password the first visitor picks, so
until then anyone on the tailnet could claim it.

## Kavita (kavita.soderlind.dev)

Manga/comic server. Same first-visit caveat as Actual: **register the
admin account at `https://kavita.soderlind.dev` right after the first
deploy** — until then anyone on the tailnet could claim it. Then add a
library in the admin UI pointing at `/mnt/backup/media/manga` (create the
directory first; the `kavita` user only needs read access, which the
media tree's default permissions provide). The only repo secret is
`kavita-token` (JWT signing key); rotating it just logs everyone out.

## Miniflux (rss.soderlind.dev)

RSS reader, adapted from the poseidon repo. The admin account is created
on first start from the `miniflux-admin-creds` agenix secret
(`agenix -d hosts/dell/secrets/miniflux-admin-creds.age` on the laptop shows it);
change the password in-app afterwards — the file is only read again if
the user table is ever empty. State is the local `miniflux` postgres
database, backed up via the nextcloud restic jobs (see above).

## Navidrome (music.soderlind.dev)

Music streaming server; Subsonic-compatible mobile apps (Symfonium,
substreamer, play:Sub, …) log in with the same URL and account. Same
first-visit caveat as Actual and Kavita: **create the admin account at
`https://music.soderlind.dev` right after the first deploy** — until then
anyone on the tailnet could claim it. The library is
`/mnt/backup/media/music` (create the directory first; the `navidrome`
user only needs read access, which the media tree's default permissions
provide). No secrets in the repo.

## Monitoring

Prometheus (`:9001`) + Alertmanager → Telegram. Alert rules live in
`hosts/dell/services/alertmanager.nix`; exporters and scrape jobs live in
each service's own module. Grafana at `grafana.soderlind.dev`.

The `node` scrape job includes Dell, both Raspberry Pis, and Hyperion. Hyperion
serves node_exporter on port 9100 through Tailscale only; Dell scrapes its stable
MagicDNS name. In Grafana's provisioned **Node Exporter Full** dashboard, select
the `node` job, the `hyperion` nodename, and the `hyperion` instance.
