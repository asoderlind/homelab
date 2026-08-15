{ config, ... }:
{
  # Prometheus config
  services.prometheus = {
    enable = true;
    port = 9001;
    retentionTime = "90d";
    globalConfig.scrape_interval = "15s";
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          # Ad-hoc metrics dropped as *.prom files, e.g. the restic backup
          # freshness timestamp (see restic-backup.nix).
          "textfile"
        ];
        extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfiles" ];
        port = 9002;
      };
    };
    # The Raspberry Pis run Debian and are not managed by this flake; they get
    # node_exporter via hosts/dell/scripts/setup-pi-exporter.sh. Their IPs must be
    # DHCP-reserved on the router.
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
            labels.instance = "dell";
          }
          {
            targets = [ "192.168.1.212:9100" ];
            labels.instance = "rpi5";
          }
          {
            targets = [ "192.168.1.98:9100" ];
            labels.instance = "rpi3";
          }
          {
            # Hyperion exposes node_exporter only over its trusted Tailscale
            # interface; MagicDNS keeps the scrape target independent of its
            # current tailnet IP.
            targets = [ "hyperion.tail193da7.ts.net:9100" ];
            labels.instance = "hyperion";
          }
        ];
      }
    ];
  };
}
