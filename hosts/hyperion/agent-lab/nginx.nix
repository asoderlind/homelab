{ config, ... }:

{
  # Keep on-host clients on loopback while preserving Buzz's canonical Host
  # header and TLS authentication semantics.
  networking.hosts."127.0.0.1" = [
    "buzz.soderlind.dev"
    "forgejo.soderlind.dev"
  ];

  # Hyperion is reachable only over Tailscale, so HTTP-01 cannot validate its
  # public names. Issue one SAN certificate through Cloudflare DNS-01 instead.
  age.secrets.acme-cloudflare-env.file = ../secrets/acme-cloudflare-env.age;

  security.acme = {
    acceptTerms = true;
    defaults.email = "axesode@gmail.com";
    certs."buzz.soderlind.dev" = {
      extraDomainNames = [ "forgejo.soderlind.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.acme-cloudflare-env.path;
      group = "nginx";
      dnsResolver = "1.1.1.1:53";
      # Cloudflare publishes these TXT records promptly, but lego's
      # authoritative propagation check can retain the NXDOMAIN it observed
      # before creating them. Wait a fixed interval and let the CA validate the
      # now-public records instead of timing out on that cached negative answer.
      extraLegoFlags = [
        "--dns.propagation-wait"
        "60s"
      ];
    };
  };

  # Ports 80 and 443 remain absent from the global firewall allowlist. The
  # trusted tailscale0 interface is the only ingress path to these vhosts.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;

    virtualHosts."buzz.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "buzz.soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
          client_max_body_size 100m;
        '';
      };
    };

    virtualHosts."forgejo.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "buzz.soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:3001";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 512m;
        '';
      };
    };
  };
}
