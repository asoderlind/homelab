#!/usr/bin/env bash
# Installs prometheus-node-exporter on the Debian Raspberry Pis.
# Idempotent - safe to re-run.
#   usage: ./scripts/setup-pi-exporter.sh [ssh-host ...]   (default: rpi rpi4)
set -euo pipefail

hosts=("$@")
if [ ${#hosts[@]} -eq 0 ]; then
  hosts=(rpi rpi4)
fi

for host in "${hosts[@]}"; do
  echo "==> $host"
  ssh "$host" 'set -e
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y prometheus-node-exporter
    sudo systemctl enable --now prometheus-node-exporter
    sleep 2
    echo -n "  hwmon temp series: "
    curl -sf localhost:9100/metrics | grep -c "^node_hwmon_temp_celsius"'
done
