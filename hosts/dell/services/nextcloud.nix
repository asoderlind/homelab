{ config, pkgs, ... }:
{
  age.secrets = {
    nextcloud-admin-pass = {
      file = ../secrets/nextcloud-admin-pass.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };
    # Shared secret between the exporter and Nextcloud's serverinfo app.
    # Nextcloud learns it once via
    #   nextcloud-occ config:app:set serverinfo token --value <token>
    # (persisted in the DB), so rotating it requires re-running that command.
    nextcloud-serverinfo-token = {
      file = ../secrets/nextcloud-serverinfo-token.age;
      owner = "nextcloud-exporter";
      group = "nextcloud-exporter";
      mode = "0400";
    };
  };

  services.nextcloud = {
    enable = true;
    hostName = "drive.soderlind.dev";
    # Must be bumped manually on every major upgrade.
    package = pkgs.nextcloud33;
    database.createLocally = true; # local PostgreSQL, socket auth
    configureRedis = true;
    maxUploadSize = "16G";
    https = true; # nginx vhost terminates TLS

    autoUpdateApps.enable = true;
    extraAppsEnable = true;
    extraApps = with config.services.nextcloud.package.packages.apps; {
      inherit
        contacts
        notes
        ;
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "32";
      "opcache.memory_consumption" = "256";
    };

    settings = {
      overwriteprotocol = "https";
      "overwrite.cli.url" = "https://drive.soderlind.dev";
      maintenance_window_start = "3";
      # File log so fail2ban can watch it
      log_type = "file";
      logfile = "/var/log/nextcloud/nextcloud.log";
      loglevel = 2;
    };

    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.age.secrets.nextcloud-admin-pass.path;
    };
  };

  systemd.tmpfiles.rules = [ "d /var/log/nextcloud 0750 nextcloud nextcloud -" ];

  # fail2ban itself is enabled in modules/common/security.nix. All clients
  # arrive via tailscale0 (100.64.0.0/10), so a ban locks that tailnet
  # device out for a day; recover with
  #   fail2ban-client set nextcloud unbanip <ip>
  services.fail2ban.jails.nextcloud.settings = {
    enabled = true;
    port = "80,443";
    logpath = "/var/log/nextcloud/nextcloud.log";
    filter = "nextcloud";
    maxretry = 3;
    bantime = "86400";
    findtime = "43200";
  };
  environment.etc."fail2ban/filter.d/nextcloud.conf".text = ''
    [Definition]
    _groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
    failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
                ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
    datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
  '';

  services.prometheus.exporters.nextcloud = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9205;
    # Goes through DNS + nginx + the wildcard cert on purpose, so the probe
    # also exercises the full client path, not just php-fpm.
    url = "https://drive.soderlind.dev";
    tokenFile = config.age.secrets.nextcloud-serverinfo-token.path;
  };
  # The decrypted path never changes, so key on the encrypted content to
  # pick up token rotations on deploy (same rationale as alertmanager).
  systemd.services.prometheus-nextcloud-exporter.restartTriggers = [
    config.age.secrets.nextcloud-serverinfo-token.file
  ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "nextcloud";
      # Slower than the global 15s: serverinfo is brute-force protected
      # (action=serverinfo), so if the token ever stops matching, every
      # scrape counts as a failed attempt and quickly locks out the host's
      # IP with 429s (recover with security:bruteforce:reset, see README).
      scrape_interval = "1m";
      static_configs = [
        {
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.nextcloud.port}" ];
          labels.instance = "dell";
        }
      ];
    }
  ];
}
