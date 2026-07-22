{ config, ... }:
{
  # Grafana config - accessible only via Tailscale
  services.grafana = {
    enable = true;
    settings.server = {
      http_port = 2342;
      http_addr = "0.0.0.0";
    };

    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          # Fixed uid so dashboard JSON can reference the datasource directly
          uid = "prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];

      # Provisioned dashboards are read-only in the UI; edit the JSON in-repo.
      dashboards.settings.providers = [
        {
          name = "homelab";
          options.path = ./dashboards;
          options.foldersFromFilesStructure = false;
        }
      ];
    };
  };
}
