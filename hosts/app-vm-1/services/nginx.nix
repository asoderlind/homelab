{ config, lib, ... }:
lib.mkIf config.homelab.apps.enable {
  # Provision this root-only runtime file on the VM before enabling ACME.
  # No Dell secret files or private keys are reused.
  security.acme = {
    acceptTerms = true;
    defaults.email = "axel@soderlind.dev";
    certs."soderlind.dev" = {
      extraDomainNames = [ "*.soderlind.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/acme-secrets/cloudflare.env";
      dnsResolver = "1.1.1.1:53";
      group = "nginx";
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/acme-secrets 0700 root root - -" ];
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    virtualHosts."karakeep.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:3006";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 100m;
        '';
      };
    };

    # No public access: Job Tracker relies on the private tailnet boundary.
    virtualHosts."jobtracker.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:3456";
        proxyWebsockets = true;
      };
    };

  };
}
