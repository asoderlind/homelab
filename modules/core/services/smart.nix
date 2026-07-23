{
  config,
  lib,
  pkgs,
  ...
}:
{
  # smartd watches all SMART-capable disks (DEVICESCAN default) and logs
  # warnings to the journal. The external USB drive may or may not expose
  # SMART through its bridge; smartd skips devices that don't respond.
  services.smartd.enable = true;

  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9633;
  };

  # Merges with the "node" job defined in prometheus.nix.
  services.prometheus.scrapeConfigs = [
    {
      job_name = "smartctl";
      static_configs = [
        {
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}" ];
          labels.instance = "dell";
        }
      ];
    }
  ];
}
