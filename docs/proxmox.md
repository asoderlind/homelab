# Proxmox cluster

[← Overview](../README.md)

Three Dell OptiPlex 3080s are being provisioned as a Proxmox VE cluster. One,
`pve1`, is installed; two more follow. Specifications are in
[docs/hardware.md](hardware.md#compute).

Two things to know before the cluster grows:

- A node must be **empty** when it joins. Provision the second and third 3080s
  before putting guests on them, or their workloads have to be moved off first.
  `pve1` is the exception — it creates the cluster with `pvecm create`, which
  keeps its existing guests.
- Fix hostnames and static IPs while each node is still standalone. Renaming a
  node after it has joined is a remove-and-rejoin operation.

Two nodes cannot hold quorum on their own, so either add a `corosync-qnetd`
QDevice on the Raspberry Pi 5, or stay on a single node until the third
machine is ready.

Open item: `pve1` currently has a **non-production-ready repository** enabled,
which the web UI flags on the summary page. Replace it with the production
`pve-no-subscription` repository before the node holds anything worth keeping.
