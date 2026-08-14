{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Contains TELEGRAM_BOT_TOKEN=<token from @BotFather>. Read by systemd
  # (as root) via EnvironmentFile, then envsubst'd into the alertmanager
  # config, so DynamicUser doesn't need read access to the secret itself.
  # This bot is dedicated to alerting - deliberately separate from any
  # assistant/bridge bot so alert delivery never depends on other services.
  age.secrets.alertmanager-env.file = ../secrets/alertmanager-env.age;

  # The decrypted secret's path never changes, so a token rotation alone
  # doesn't restart the unit; keying on the encrypted file's content makes
  # every rotation take effect on the next deploy.
  systemd.services.alertmanager.restartTriggers = [ config.age.secrets.alertmanager-env.file ];

  services.prometheus.alertmanager = {
    enable = true;
    port = 9093;
    environmentFile = config.age.secrets.alertmanager-env.path;
    configuration = {
      route = {
        receiver = "telegram";
        # One message per alertname per instance batch; re-notify daily if
        # an alert stays firing.
        group_by = [ "alertname" ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "24h";
      };
      receivers = [
        {
          name = "telegram";
          telegram_configs = [
            {
              bot_token = "$TELEGRAM_BOT_TOKEN";
              chat_id = 7869411488;
              parse_mode = "HTML";
              send_resolved = true;
            }
          ];
        }
      ];
    };
  };

  services.prometheus.alertmanagers = [
    {
      static_configs = [
        { targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ]; }
      ];
    }
  ];

  services.prometheus.rules = [
    (builtins.toJSON {
      groups = [
        {
          name = "homelab";
          rules = [
            {
              alert = "InstanceDown";
              expr = "up == 0";
              for = "5m";
              annotations.summary = "{{ $labels.instance }} ({{ $labels.job }}) is unreachable";
            }
            {
              alert = "DiskFullSoon";
              # Root/data filesystems projected to fill within 24h based on
              # the last 6h of growth.
              expr = ''predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"}[6h], 24*3600) < 0 and node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"} / node_filesystem_size_bytes < 0.2'';
              for = "30m";
              annotations.summary = "{{ $labels.instance }}:{{ $labels.mountpoint }} will fill within 24h";
            }
            {
              alert = "DiskAlmostFull";
              expr = ''node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"} / node_filesystem_size_bytes < 0.1'';
              for = "15m";
              annotations.summary = "{{ $labels.instance }}:{{ $labels.mountpoint }} has less than 10% free";
            }
            {
              alert = "SmartFailure";
              expr = "smartctl_device_smart_status != 1";
              for = "5m";
              annotations.summary = "SMART reports failing disk {{ $labels.device }} on {{ $labels.instance }}";
            }
            {
              alert = "HighTemperature";
              expr = "node_hwmon_temp_celsius > 80";
              for = "10m";
              annotations.summary = "{{ $labels.instance }} {{ $labels.chip }} at {{ $value | printf \"%.0f\" }}C";
            }
            {
              alert = "NextcloudUnhealthy";
              # nextcloud_up is 0 when the exporter can't fetch/parse the
              # serverinfo endpoint; InstanceDown already covers the
              # exporter process itself being down.
              expr = "nextcloud_up == 0";
              for = "5m";
              annotations.summary = "Nextcloud serverinfo check failing on {{ $labels.instance }}";
            }
            {
              alert = "ResticBackupStale";
              # 3 days: two missed daily slots plus slack, so a single
              # hiccup doesn't page (that's SystemdUnitFailed's job). Can't
              # fire before the first successful run (metric absent until
              # then). This catches the timer never firing at all, e.g. the
              # host being off for days.
              # Unlabelled so it covers every restic job (local and offsite)
              # without needing a rule per repo.
              expr = "time() - restic_backup_last_success_timestamp_seconds > 3 * 86400";
              for = "1h";
              annotations.summary = "restic backup '{{ $labels.backup }}' on {{ $labels.instance }} is stale (>3 days)";
            }
            {
              alert = "SystemdUnitFailed";
              expr = ''node_systemd_unit_state{state="failed"} == 1'';
              for = "5m";
              annotations.summary = "{{ $labels.name }} failed on {{ $labels.instance }}";
            }
          ];
        }
      ];
    })
  ];
}
