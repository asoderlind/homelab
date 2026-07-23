{ config, ... }:
{
  age.secrets.grafana-secret-key = {
    file = ../../../secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # Grafana config - reached via the nginx HTTPS proxy (see nginx.nix),
  # so it only listens on loopback now instead of every interface.
  services.grafana = {
    enable = true;
    settings.server = {
      http_port = 2342;
      http_addr = "127.0.0.1";
      # Grafana builds absolute links/redirects from this, so it must
      # match the public-facing URL, not the internal listen address.
      root_url = "https://grafana.soderlind.dev/";
    };
    settings.security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";

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
