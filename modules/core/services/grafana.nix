{ config, ... }:
{
  # Grafana config - accessible only via Tailscale
  services.grafana = {
    enable = true;
    settings.server = {
      http_port = 2342;
      http_addr = "0.0.0.0";
    };
  };
}
