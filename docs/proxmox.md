# Proxmox cluster

[← Overview](../README.md)

Three Dell OptiPlex 3080s form the **`homelab`** Proxmox VE cluster.
Membership and quorum were verified via `pvecm status` and `pvecm nodes` on
`pve1`: all three nodes are online and the cluster is quorate.
Specifications are in [docs/hardware.md](hardware.md#compute).

| Node | Management / cluster IP | Node ID |
| --- | --- | --- |
| `pve1` | `192.168.1.55` | 1 |
| `pve2` | `192.168.1.56` | 2 |
| `pve3` | `192.168.1.57` | 3 |

The cluster uses Corosync `knet`, with one vote per node, three expected votes,
and quorum of two. It can tolerate one node being offline without losing quorum;
a QDevice is not needed for this three-node arrangement. Local storage is not
made shared or replicated just by joining the cluster.

## Adding future nodes

Two things to know before the cluster grows:

- A node must be **empty** when it joins. Join future nodes before creating
  guests on them. The founding node, `pve1`, retained its guests when creating
  the cluster with `pvecm create`.
- Fix hostnames and static IPs while each node is still standalone. Renaming a
  node after it has joined is a remove-and-rejoin operation.

A two-node cluster has quorum while both nodes are online, but cannot tolerate
one node going offline without a QDevice. The current three-node cluster avoids
that limitation.

## Host monitoring

Debian's `prometheus-node-exporter` package (1.9.0) is installed directly on
all three nodes, without Ansible or optional collector packages. The systemd
service is enabled at boot and active; each node's `/metrics` endpoint was
verified locally. A drop-in at
`/etc/systemd/system/prometheus-node-exporter.service.d/management.conf` sets:

```ini
[Service]
Environment="ARGS=--web.listen-address=192.168.1.55:9100 --collector.systemd"
```

The address is `.56` on `pve2` and `.57` on `pve3`. Package installation and
services are per-host, not distributed by cluster membership. Administration
was performed through `ssh pve1`, then root SSH to the other management IPs,
using `HostKeyAlias=pve2` / `pve3` and the corresponding cluster-managed
`UserKnownHostsFile=/etc/pve/nodes/<node>/ssh_known_hosts` with strict host-key
checking enabled.

Firewall rules were not changed. Restrict TCP 9100 to Dell in the applicable
Proxmox/network firewall. Metrics are unauthenticated and must not be exposed
to the Internet.

The NixOS scrape configuration is prepared in
`hosts/dell/services/prometheus.nix`; deployment and end-to-end verification
from Dell are still pending. From a controller with Nix and Dell SSH access:

```sh
nix run nixpkgs#deploy-rs -- .#dell
```

Dell's Prometheus scrapes all three management IPs under job `node`, with
instance labels `pve1`, `pve2`, and `pve3`. After provisioning and deploying Dell,
the existing Grafana **Node Exporter Full** dashboard discovers them automatically.
Verify `up{job="node",instance=~"pve[123]"}` is 1 for all three. These are host
CPU, memory, disk, and network metrics, not Proxmox API/guest inventory metrics.

## Repositories

`pve2` returned HTTP 401 for the Proxmox enterprise PVE and Ceph repositories
when refreshing APT indexes. Repository policy was left unchanged; Debian-only
indexes were refreshed on `pve2` and `pve3` to install the exporter. Configure
valid subscription access or the appropriate no-subscription repositories
before routine updates.

Open item: `pve1` currently has a **non-production-ready repository** enabled,
which the web UI flags on the summary page. Replace it with the production
`pve-no-subscription` repository before the node holds anything worth keeping.
