{
  # Export host CPU, memory, disk, network, and systemd metrics to Dell's
  # Prometheus. Port 9100 is deliberately not opened in the global firewall:
  # it is reachable through the already-trusted tailscale0 interface only.
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    openFirewall = false;
    enabledCollectors = [ "systemd" ];
  };
}
