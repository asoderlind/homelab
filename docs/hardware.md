# Homelab hardware

The Dell runs the main homelab services, Hyperion hosts the agent lab, and the
two Raspberry Pis are separate Debian machines. Prometheus scrapes the Dell
and Raspberry Pi 5 as `node` targets. The relevant scrape configuration lives in
`hosts/dell/services/prometheus.nix`.

## Compute

| Instance | Machine | CPU | RAM | Storage | OS |
| --- | --- | --- | --- | --- | --- |
| `dell` | Dell OptiPlex 3040 | Intel Core i5-6500T — 4C/4T, 2.5 GHz (Skylake) | 8 GB | 500 GB internal SATA HDD (Toshiba MQ01ACF050) | NixOS 26.05 |
| `hyperion` | HP EliteDesk 800 G3 | Intel Core i7-7700 — 4C/8T, 3.6 GHz (Kaby Lake) | 16 GB | 256 GB Samsung NVMe | NixOS 26.05 |
| `rpi5` | Raspberry Pi 5 Model B (Rev 1.1) | Broadcom BCM2712 — quad Cortex-A76, 2.4 GHz | 16 GB | 32 GB microSD | Debian 12 (bookworm) |
| `rpi3` | Raspberry Pi 3 Model B (Rev 1.2) | Broadcom BCM2837 — quad Cortex-A53, 1.2 GHz | 1 GB | 16 GB microSD | Debian 13 (trixie) |

The `dell` and `rpi5` names are Prometheus `instance` labels. Hyperion is not
scraped by the Dell Prometheus server.

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
[Backups](../README.md#backups-restic--mntbackup).

## Rack layout

The rack is 12U tall in total and consists of two stacked 10-inch GeekPi desk
racks: an 8U T1 rack on top and a 4U T0 rack on the bottom. Its current physical
layout, from top to bottom, is:

```text
TOP -- GEEKPI T1 8U 10-INCH DESK RACK
+------------------------------------------------------+  0.0U
| Ubiquiti USW-Lite-8-PoE switch (1U)                  |
+------------------------------------------------------+  1.0U
| Dual Raspberry Pi mount (1U)                         |
+------------------------------------------------------+  2.0U
| Patching (0.5U)                                      |
+------------------------------------------------------+  2.5U
| HP EliteDesk / hyperion (1U)                         |
+------------------------------------------------------+  3.5U
| Dell OptiPlex / dell (1U)                            |
+------------------------------------------------------+  4.5U
| External backup HDD (1U)                             |
+------------------------------------------------------+  5.5U
|          FREE / UNALLOCATED IN T1 RACK (2.5U)        |
|                                                      |
+------------------------------------------------------+  8.0U
T1 / T0 RACK BOUNDARY
+------------------------------------------------------+  8.0U
|                                                      |
|          FREE / UNALLOCATED IN T0 RACK (4U)          |
|                                                      |
|                                                      |
+------------------------------------------------------+ 12.0U
BOTTOM -- GEEKPI T0 4U 10-INCH DESK RACK
```

The rack therefore has 6.5U free in total: a contiguous 6U area plus another
0.5U of unallocated space. The schematic uses 12 interior rows—one per rack
unit—with exact half-unit boundaries identified by the measurements at right.
