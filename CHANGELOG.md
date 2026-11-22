# Changelog

## Unreleased

### Changed

- Move Karakeep and Job Tracker from Dell to a new `apps-vm` NixOS host with
  placeholder VM disks, SSH address, and deployment identity. Move HTTPS
  termination to the VM while keeping both application hostnames.
- Remove their container/setup units, nginx routes, and homepage links from
  Dell's configuration; retain existing on-disk data for manual migration.
- Use default rootless UID mapping for Karakeep to avoid unnecessary image
  ownership rewriting. Document VM provisioning, runtime TLS credentials,
  stopped-service data transfer, and pre-pulling images before activation.

### Added

- Karakeep 0.35.0 on Dell at `https://karakeep.soderlind.dev`, with rootless
  Podman, persistent storage, generated runtime secrets, private Meilisearch
  and Chrome sidecars, and a digest-pinned Chrome image.
- Job Tracker v2.0.2 on Dell at `https://jobtracker.soderlind.dev`, with rootless
  Podman, persistent SQLite/configuration/state/backup directories, and
  container resource limits.
- Tailnet-only HTTPS routes and homepage links for both apps, plus networking,
  first-run account/LLM/extension setup, verification, and backup documentation.

### Deployment notes

- Karakeep signups are disabled by default; temporarily enable them to create
  the initial account. Configure an LLM provider separately for automatic tagging.
- Install the matching Job Tracker browser extension and configure its server URL.
- The new persistent directories are not yet included in automated restic jobs.
- Configuration has not been deployed or evaluated with Nix; Nix was unavailable
  in the editing environment. Whitespace validation passed with `git diff --check`.
