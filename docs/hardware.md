# Homelab hardware

The Dell runs the main homelab services, the OptiPlex 3080s form a Proxmox VE
cluster, and the Raspberry Pi 5 runs Debian. Prometheus scrapes the Dell,
Raspberry Pi 5, and app-vm-1 as `node` targets. The relevant scrape configuration
lives in `hosts/dell/services/prometheus.nix`.

The app VM runs the NixOS node exporter on port 9100, scraped over Tailscale at
`app-vm-1.tail193da7.ts.net` (requires that MagicDNS name and tailnet access from
Dell). No LAN firewall port is opened. Deploy `app-vm-1` first, then `dell`:

```sh
nix run nixpkgs#deploy-rs -- .#app-vm-1
nix run nixpkgs#deploy-rs -- .#dell
```

After deployment, verify `up{job="node",instance="app-vm-1"}` is `1` in
Prometheus. To troubleshoot, run
`curl -f http://app-vm-1.tail193da7.ts.net:9100/metrics` from Dell.

## Compute

| Instance | Machine | CPU | RAM | Storage | OS |
| --- | --- | --- | --- | --- | --- |
| `dell` | Dell OptiPlex 3040 | Intel Core i5-6500T — 4C/4T, 2.5 GHz (Skylake) | 8 GB | 500 GB internal SATA HDD (Toshiba MQ01ACF050) | NixOS 26.05 |
| `pve1` | Dell OptiPlex 3080 | Intel Core i5-10500T — 6C/12T, 2.3 GHz (Comet Lake) | 32 GB (31.09 GiB usable) | 67.73 GiB root filesystem, 4.22 GiB used | Proxmox VE 9.2.2 |
| `rpi5` | Raspberry Pi 5 Model B (Rev 1.1) | Broadcom BCM2712 — quad Cortex-A76, 2.4 GHz | 16 GB | 32 GB microSD | Debian 12 (bookworm) |

The `dell`, `rpi5`, and `app-vm-1` names are Prometheus `instance` labels.

`pve1`, `pve2`, and `pve3` are provisioned and joined to the `homelab` Proxmox
cluster at `192.168.1.55`, `.56`, and `.57`, respectively. All three nodes are
online and the cluster is quorate (two of three votes required). The detailed
specifications above were collected from `pve1`; the other nodes have not yet
been hardware-inventoried. `pve1` boots in EFI mode on kernel
`7.0.2-6-pve` with an 8 GiB swap volume, and storage is local to the node.
Cluster provisioning notes are in the [Proxmox guide](proxmox.md).

## Network

The rack contains a
[Ubiquiti UniFi Switch Lite 8 PoE (USW-Lite-8-PoE)](https://amzn.to/4xnZNK2),
installed in the top 1U position. This is connected by cable to a UniFi dream router.

## Power

The rack is backed by a dedicated UPS: a CyberPower Systems ValuePRO
line-interactive unit rated 1200 VA / 720 W, model `VP1200ELCD`, with five
Schuko outlets. It is a tower-format unit rather than rack hardware, so it does
not occupy a U in the layout below.

No USB monitoring is wired up. The unit simply passes mains power through, so
there is no telemetry and no automatic shutdown on power loss — the hosts keep
running until the battery is exhausted.

## Storage

A diskless
[UGREEN NASync DXP2800](https://nas-eu.ugreen.com/products/ugreen-nasync-dxp2800-nas-storage)
provides two SATA drive bays and two M.2 NVMe slots. It has an Intel N100
quad-core processor, 8 GB DDR5 RAM, one 2.5 GbE port, and 4K HDMI output. Two
4 TB WD Red Plus 3.5-inch NAS hard drives (5400 RPM, SATA 6 Gb/s, CMR, 256 MB
cache) are on order for its SATA bays.

A Western Digital 2 TB USB drive (WD20EARX-00PASB0) is mounted at
`/mnt/backup` on the Dell and holds the local restic repository. It is mounted
with `nofail`; the backup jobs verify the mountpoint and fail loudly when it is
absent. Operational details are in
[Backups](backups.md).

## Rack layout

The rack is 12U tall in total and consists of two stacked 10-inch GeekPi desk
racks: an 8U T1 rack on top and a 4U T0 rack on the bottom. Its current physical
layout, from top to bottom, is:

```text
TOP -- GEEKPI T1 8U 10-INCH DESK RACK
+------------------------------------------------------+  0.0U
| Ubiquiti USW-Lite-8-PoE switch (1U)                  |
+------------------------------------------------------+  1.0U
| Raspberry Pi 5 / dual mount (1U, one slot free)       |
+------------------------------------------------------+  2.0U
| Patching (0.5U)                                      |
+------------------------------------------------------+  2.5U
| FREE / UNALLOCATED (1U)                             |
+------------------------------------------------------+  3.5U
| External backup HDD (1U)                             |
+------------------------------------------------------+  4.5U
| Dell OptiPlex / dell (1U)                            |
+------------------------------------------------------+  5.5U
| Dell OptiPlex 3080 / pve1 (1U)                       |
+------------------------------------------------------+  6.5U
| Dell OptiPlex 3080 (1U, not yet provisioned)         |
+------------------------------------------------------+  7.5U
|          FREE / UNALLOCATED IN T1 RACK (0.5U)        |
+------------------------------------------------------+  8.0U
T1 / T0 RACK BOUNDARY
+------------------------------------------------------+  8.0U
| Dell OptiPlex 3080 (1U, not yet provisioned)         |
+------------------------------------------------------+  9.0U
|                                                      |
|          FREE / UNALLOCATED IN T0 RACK (3U)          |
|                                                      |
+------------------------------------------------------+ 12.0U
BOTTOM -- GEEKPI T0 4U 10-INCH DESK RACK
```

The rack therefore has 4.5U free in total: 1U below the patching, a contiguous
3U at the bottom of T0, and 0.5U at the bottom of T1. The remaining equipment
is shown in its existing positions. The schematic uses 12
interior rows—one per rack unit—with exact half-unit boundaries identified by
the measurements at right.
