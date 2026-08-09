{ config, ... }:
{
  # Contains CLOUDFLARE_DNS_API_TOKEN=<token scoped to Zone.DNS edit on
  # soderlind.dev>. The host is only reachable over Tailscale, so HTTP-01
  # validation can't work; lego uses this token for DNS-01 instead,
  # publishing the challenge TXT record via Cloudflare's API.
  age.secrets.acme-cloudflare-env.file = ../../../secrets/acme-cloudflare-env.age;

  security.acme = {
    acceptTerms = true;
    defaults.email = "axesode@gmail.com";
    # One wildcard cert for every service subdomain: new services need no
    # new cert (and individual hostnames stay out of the public CT logs).
    certs."soderlind.dev" = {
      extraDomainNames = [ "*.soderlind.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.acme-cloudflare-env.path;
      group = "nginx";
      # The host's only resolver is Tailscale MagicDNS (100.100.100.100),
      # whose upstream can serve stale delegation for the zone; have lego
      # verify the challenge TXT records via a public resolver instead.
      dnsResolver = "1.1.1.1:53";
    };
  };

  # TLS-terminating reverse proxy. Listens on 80/443, but neither port is
  # in allowedTCPPorts - only tailscale0 (a trusted interface) reaches it,
  # preserving the tailnet-only access model.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;

    virtualHosts."grafana.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        # Grafana live features (dashboard streaming) use a websocket.
        proxyWebsockets = true;
      };
    };

    virtualHosts."jellyfin.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        # Jellyfin's web client keeps a websocket open for playback/session
        # state; without Upgrade headers it silently degrades.
        proxyWebsockets = true;
      };
    };

    # The nextcloud module generates this vhost itself
    virtualHosts."${config.services.nextcloud.hostName}" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
    };

    virtualHosts."transmission.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        # Transmission lives in the protonvpn netns; 10.233.0.2 is its end
        # of the veth pair (see protonvpn.nix).
        proxyPass = "http://10.233.0.2:${toString config.services.transmission.settings.rpc-port}";
      };
    };

    virtualHosts."actual.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.actual.settings.port}";
        # Sync uploads/downloads move whole budget files; the nginx-module
        # default client_max_body_size (10m) is too tight for larger budgets.
        extraConfig = ''
          client_max_body_size 50m;
        '';
      };
    };

    virtualHosts."kavita.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.kavita.settings.Port}";
        # Kavita pushes scan/reading events to the UI over a SignalR
        # websocket.
        proxyWebsockets = true;
      };
    };

    virtualHosts."rss.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://${config.services.miniflux.config.LISTEN_ADDR}";
      };
      # poseidon's security headers, minus its rate limiting (no limit_req
      # zones are defined in this nginx).
      extraConfig = ''
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      '';
    };

    virtualHosts."music.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
        # No proxyWebsockets: Navidrome pushes UI/scan events over SSE, and
        # marks those responses X-Accel-Buffering: no itself, so nginx's
        # default buffering doesn't stall them either.
      };
    };

    virtualHosts."habits.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        # beaverhabits runs with --network=host (see beaverhabits.nix), so
        # its gunicorn listens directly on the host at its default port.
        proxyPass = "http://127.0.0.1:8080";
        # NiceGUI apps do all UI updates over a websocket.
        proxyWebsockets = true;
      };
    };
  };
}
