# Raspberry Pi management

## Current setup

- **Host:** `rpi` in Ansible; hostname `raspberrypi`, Debian 12 on ARM64.
- **Access:** SSH as `asoderlind` over Tailscale.
- **Core tools:** Tailscale and Prometheus node exporter active/enabled;
  Pi agent harness 1.6.1 at `~/.pi/agent/bin/pi`.
- **Other services:** Docker/containerd, fail2ban, NetworkManager, and desktop services.
- **Applications:** five stopped Docker containers; Hermes and OpenClaw gateways
  absent/inactive, with residual source/configuration/history still on disk.

Ansible provides read-only discovery and a Debian 12 baseline playbook for
Tailscale and node exporter. Pi harness installation and other services are not
yet managed.

## Setup and usage

Install `ansible-core` on the controller. The Pi requires Python 3 and, for remote
runs, an authorized SSH key and tailnet access. No external collections are needed.

Run from the repository root:

```sh
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --syntax-check

# Remote discovery:
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --limit rpi

# Local discovery on the Pi, as asoderlind (without sudo):
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --limit rpi -c local
```

The inventory uses the Pi's Tailscale address. For LAN access, add
`-e ansible_host=192.168.1.211` after verifying that address. SSH host key
verification remains enabled. Local mode uses the invoking account; user-service
and npm discovery reflect that account.

## Provision baseline services

`provision.yml` installs Tailscale and node exporter and enables/starts their
services. It matches the Pi's existing `tailscale.list` repository and signing-key
layout. On other hosts, check for conflicting Tailscale repository entries first.
It leaves tailnet enrollment, firewall policy, Pi installation, and unrelated
software unchanged. A fresh Pi must be enrolled in Tailscale separately.

```sh
# Validate:
ansible-playbook -i ansible/inventory.yml ansible/provision.yml --syntax-check

# Preview:
ansible-playbook -i ansible/inventory.yml ansible/provision.yml --limit rpi --check --diff -K

# Apply:
ansible-playbook -i ansible/inventory.yml ansible/provision.yml --limit rpi -K
```

`-K` prompts for the Pi user's sudo password; omit it for passwordless sudo.
Check mode can fail on fresh hosts when prerequisites are not installed yet,
and signing-key download predictions may report changes without downloading.
Packages use `state: present`, not automatic upgrades. Node exporter's network
exposure follows the Debian package defaults and existing firewall rules.

## Discovery reports

Results overwrite `ansible/reports/rpi.json` on the controller. The directory
is private (0700), reports are 0600, and reports are gitignored. Review before
sharing: addresses, paths, service descriptions, and container metadata may be
sensitive. Secret files, service definitions, and container inspection are excluded.

Discovery does not change target configuration, though Ansible may create temporary
module files. Missing commands and permission errors are recorded and summarized;
they indicate incomplete discovery. Unreachable hosts fail normally.

Run normally to save a report: `--check` executes the read-only commands but does
not write the report.
