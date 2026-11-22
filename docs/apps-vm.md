# Apps VM (provisioning template)

Karakeep and Job Tracker have moved out of Dell's configuration to
`hosts/apps-vm/`. This is not yet a bootable/deployable VM configuration:
replace the placeholders below first. The public application hostnames remain
unchanged.

## Redeploy Dell first

From the repository root, deploy **only Dell**:

```sh
nix run nixpkgs#deploy-rs -- .#dell
```

Do not deploy all nodes: apps-vm deliberately uses a non-resolving placeholder
SSH hostname. Removing the imports stops/removes the four app container units
and the Karakeep setup unit on activation; nginx routes and homepage links are
also removed. Existing Bunko and Shoku are unaffected.

No data deletion or Podman pruning is performed. Dell retains
`/var/lib/karakeep`, `/var/lib/job-tracker`, cached images, and possibly the
unused Karakeep network. Verify the old units are stopped after deployment,
especially following any previous failed activation/rollback. These two URLs
will be unavailable until the VM is ready and DNS is updated.

## Provision the VM

1. Create an x86_64 UEFI NixOS VM on Proxmox, initially around 2–4 vCPUs,
   4 GB RAM and 40–60 GB SSD storage. Set Proxmox I/O limits if needed.
2. Replace `hosts/apps-vm/hardware-configuration.nix` with generated hardware
   settings from that VM. Both disk labels are intentionally placeholders.
   Verify boot mode, filesystem types, and `system.stateVersion` against the
   installed system.
3. Replace the apps-vm deployment hostname and SSH identity placeholders in
   `flake.nix`. Change `networking.hostName` if desired. Add the corresponding
   SSH public key to `users.users.axel.openssh.authorizedKeys.keys` in the host
   module; the common laptop key is already inherited.
4. Install/bootstrap NixOS, join Tailscale, and verify SSH and non-interactive
   sudo before using deploy-rs.
5. Provision `/var/lib/acme-secrets/cloudflare.env`, root-owned mode 0600
   inside a root-owned mode 0700 directory, containing
   `CLOUDFLARE_DNS_API_TOKEN=...` scoped to DNS editing for soderlind.dev.
   This runtime file is deliberately not a missing agenix path, so Dell
   evaluation does not depend on provisioning VM secrets.
6. If preserving existing app data, copy both entire state directories from
   Dell while all related containers are stopped. Preserve permissions and
   set their ownership to the VM's axel user (UID 1000); do not start the new
   containers until the copy is complete. Preserve Karakeep's runtime.env so
   its authentication and search secrets remain unchanged. Keep the Dell
   copies until the migration is verified.
7. Pre-pull the four images specified in `hosts/apps-vm/services/` as
   `axel` (not root), one at a time, before activation. This avoids spending
   the deployment confirmation window downloading/extracting images.
   Karakeep now uses default rootless UID mapping rather than the unnecessary
   keep-id mapping that caused image-wide ownership rewriting on Dell.
8. Validate and deploy only the new host:

   ```sh
   nix eval --raw .#nixosConfigurations.apps-vm.config.system.build.toplevel.drvPath
   nix run nixpkgs#deploy-rs -- .#apps-vm
   ```

9. Point both DNS names at the VM's Tailscale address (DNS-only, no Cloudflare
   proxy). HTTPS terminates on the VM, not Dell. Confirm both apps and the
   Job Tracker extension work before considering the migration complete.

## Application setup

- **https://karakeep.soderlind.dev** — Karakeep 0.35.0, with private
  Meilisearch and Chrome sidecars. Only the web port is published, on loopback
  port 3006. State and runtime credentials live under `/var/lib/karakeep`.
- **https://jobtracker.soderlind.dev** — Job Tracker v2.0.2, on loopback port
  3456. SQLite, configuration, runtime state, and backups persist under
  `/var/lib/job-tracker/{data,config,state,backups}`.
- Both use rootless Podman as `axel`, the existing wildcard TLS certificate,
  and tailnet-only nginx ingress. Bunko and Shoku remain unchanged.
  Ensure both DNS names resolve to the VM's Tailscale address (DNS-only, not
  Cloudflare-proxied). Job Tracker's trusted-host list is not authentication:
  anyone allowed through this tailnet boundary can access it.

### First-run setup

Karakeep's setup unit generates persistent authentication and search secrets
on the server; no plaintext secrets enter Git or the Nix store. Signups are
disabled by default. Temporarily set `DISABLE_SIGNUPS = "false"` in
`hosts/apps-vm/services/karakeep.nix`, deploy, create your account, then restore
`"true"` and deploy again.

For automatic tagging, add provider settings to
`/var/lib/karakeep/runtime.env` using `sudoedit`, preserving the generated
secrets and mode 0600/owner axel. For example:

```ini
OLLAMA_BASE_URL=http://YOUR-OLLAMA-HOST:11434
INFERENCE_TEXT_MODEL=YOUR-INSTALLED-MODEL
```

Use an endpoint reachable from the container, not localhost. Alternatively
configure `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `INFERENCE_TEXT_MODEL`
for an OpenAI-compatible provider. Restart `podman-karakeep` afterward.
See [Karakeep configuration](https://docs.karakeep.com/configuration).
AI tagging remains unconfigured until a provider is supplied.

For Job Tracker, download and unpack `job-tracker-extension-2.0.2.zip` from
[the matching release](https://github.com/Muatasim-Aswad/job-tracker/releases/tag/v2.0.2),
load it as an unpacked Chromium extension, and set its Server setting to
`https://jobtracker.soderlind.dev`. Keep the extension and server versions aligned.

### Verification and backups

After deployment:

```sh
sudo systemctl status podman-karakeep podman-karakeep-search podman-karakeep-chrome podman-job-tracker
curl -f http://127.0.0.1:3456/health/ready
curl -I https://karakeep.soderlind.dev
curl -I https://jobtracker.soderlind.dev
```

Test saving/reopening a note, automatic tagging after configuring a model, and
capturing an opportunity through the extension. Confirm persistence after
restarting the containers. Chrome is pinned to a registry manifest digest;
update it deliberately alongside Karakeep upgrades.

**These directories are not yet included in the existing restic jobs.**
Before upgrades, stop the corresponding containers and copy the entire
`/var/lib/karakeep` or `/var/lib/job-tracker` directory to protected off-host
storage, then restart even if copying fails. Stop both Karakeep and its search
sidecar for a consistent snapshot. Include runtime secrets in encrypted backups.
Image rollback alone does not reverse database migrations.
