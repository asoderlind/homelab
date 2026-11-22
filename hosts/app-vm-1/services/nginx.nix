{ config, lib, ... }:
lib.mkIf (config.homelab.apps.enable && config.homelab.apps.proxy.enable) {
  # Share the encrypted DNS credential with Dell, not its private host key.
  age.secrets.acme-cloudflare-env.file = ../../dell/secrets/acme-cloudflare-env.age;
  security.acme = {
    acceptTerms = true;
    defaults.email = "axel@soderlind.dev";
    certs."soderlind.dev" = {
      extraDomainNames = [ "*.soderlind.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.acme-cloudflare-env.path;
      dnsResolver = "1.1.1.1:53";
      group = "nginx";
    };
  };
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
