# NixOS homelab

Declarative configuration for my homelab, managed with Nix flakes and deploy-rs.

- **Dell:** self-hosted apps, media, monitoring, and local/off-site backups.
- **Supporting hardware:** a Raspberry Pi 5, a UGREEN NAS, and a growing Proxmox cluster.

Services use Tailscale-only ingress with nginx and Cloudflare DNS-01 TLS.
Secrets are encrypted with agenix; deployments are manual.

## Architecture

> **Architecture image coming soon** — a generated overview of the hosts,
> network, storage, and services.

![Homelab architecture](https://github.com/user-attachments/assets/7fc3a2f3-0a51-4e0e-8117-4971a42dac20)

## Documentation

| Guide | Contents |
| --- | --- |
| [Hardware](docs/hardware.md) | Machines, storage, network equipment, UPS, and rack layout |
| [Networking](docs/networking.md) | Tailscale ingress, DNS/TLS, nginx, and Proton VPN isolation |
| [Deployment and secrets](docs/deployment.md) | Validation, deploy-rs, and agenix workflows |
| [Dell services](docs/services.md) | App setup, troubleshooting, release updates, and monitoring |
| [Backups and recovery](docs/backups.md) | Restic schedules, retention, and restore procedures |
| [Proxmox cluster](docs/proxmox.md) | Provisioning notes and outstanding setup |

Host configurations live in `hosts/` and shared NixOS modules in `modules/common/`.
