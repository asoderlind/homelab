# Raspberry Pi inventory

## Current setup

- **Host:** `rpi5` in Ansible; hostname `raspberrypi`, Debian 12 on ARM64.
- **Access:** SSH as `asoderlind` over Tailscale.
- **Core tools:** Tailscale and Prometheus node exporter active/enabled;
  Pi agent harness 1.6.1 at `~/.pi/agent/bin/pi`.
- **Other services:** Docker/containerd, fail2ban, NetworkManager, and desktop services.
- **Applications:** five stopped Docker containers; Hermes and OpenClaw gateways
  absent/inactive, with residual source/configuration/history still on disk.

Ansible currently provides read-only discovery, not provisioning or compliance
checks. It does not install or configure the tools above.

## Setup and usage

Install `ansible-core` on the controller. The Pi requires Python 3 and, for remote
runs, an authorized SSH key and tailnet access. No external collections are needed.

Run from the repository root:

```sh
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --syntax-check

# Remote discovery:
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --limit rpi5

# Local discovery on the Pi, as asoderlind (without sudo):
ansible-playbook -i ansible/inventory.yml ansible/discover.yml --limit rpi5 -c local
```

The inventory uses the Pi's Tailscale address. For LAN access, add
`-e ansible_host=192.168.1.211` after verifying that address. SSH host key
verification remains enabled. Local mode uses the invoking account; user-service
and npm discovery reflect that account.

## Discovery reports

Results overwrite `ansible/reports/rpi5.json` on the controller. The directory
is private (0700), reports are 0600, and reports are gitignored. Review before
sharing: addresses, paths, service descriptions, and container metadata may be
sensitive. Secret files, service definitions, and container inspection are excluded.

Discovery does not change target configuration, though Ansible may create temporary
module files. Missing commands and permission errors are recorded and summarized;
they indicate incomplete discovery. Unreachable hosts fail normally.

Run normally to save a report: `--check` executes the read-only commands but does
not write the report.
