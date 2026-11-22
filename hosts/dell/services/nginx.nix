{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Contains CLOUDFLARE_DNS_API_TOKEN=<token scoped to Zone.DNS edit on
  # soderlind.dev>. The host is only reachable over Tailscale, so HTTP-01
  # validation can't work; lego uses this token for DNS-01 instead,
  # publishing the challenge TXT record via Cloudflare's API.
  age.secrets.acme-cloudflare-env.file = ../secrets/acme-cloudflare-env.age;

  security.acme = {
    acceptTerms = true;
    defaults.email = "axel@soderlind.dev";
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

    virtualHosts."music.soderlind.dev" = lib.mkIf config.services.navidrome.enable {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
        # No proxyWebsockets: Navidrome pushes UI/scan events over SSE, and
        # marks those responses X-Accel-Buffering: no itself, so nginx's
        # default buffering doesn't stall them either.
      };
    };

    virtualHosts."home.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      root = pkgs.writeTextDir "index.html" ''
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="dark light">
          <title>Home · Axel's services</title>
          <style>
            :root { color-scheme: dark; --bg:#10141c; --panel:#191f2b; --ink:#eef2f8; --muted:#aab4c4; --accent:#8eb5ff; }
            * { box-sizing:border-box }
            body { margin:0; min-height:100vh; background:radial-gradient(ellipse at top,#202b40,var(--bg) 65%); color:var(--ink); font:16px/1.5 system-ui,sans-serif }
            main { width:min(900px,calc(100% - 2rem)); margin:0 auto; padding:5rem 0 }
            h1 { margin:0; font-size:clamp(2rem,6vw,3.5rem); letter-spacing:-.04em }
            p { margin:.5rem 0 2rem; color:var(--muted) }
            .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:1rem }
            a { display:block; padding:1.15rem 1.25rem; border:1px solid #303a4b; border-radius:14px; background:var(--panel); color:var(--ink); text-decoration:none; transition:transform .15s,border-color .15s }
            a:hover, a:focus-visible { transform:translateY(-2px); border-color:var(--accent); outline:none }
            strong { display:block; color:var(--accent); font-size:1.1rem }
            small { color:var(--muted) }
          </style>
        </head>
        <body>
          <main>
            <h1>Home</h1>
            <p>Personal services</p>
            <nav class="grid" aria-label="Services">
              <a href="https://jobs.soderlind.dev"><strong>Shoku</strong><small>Job search and application dashboard</small></a>
              <a href="https://bunko.soderlind.dev"><strong>Bunko</strong><small>Notes</small></a>
              <a href="https://drive.soderlind.dev"><strong>Nextcloud</strong><small>Files and collaboration</small></a>
              <a href="https://actual.soderlind.dev"><strong>Actual</strong><small>Budgeting</small></a>
              <a href="https://rss.soderlind.dev"><strong>Miniflux</strong><small>RSS reader</small></a>
              <a href="https://grafana.soderlind.dev"><strong>Grafana</strong><small>Monitoring dashboards</small></a>
              <a href="https://chat.soderlind.dev"><strong>Open WebUI</strong><small>AI chat</small></a>
              <a href="https://jellyfin.soderlind.dev"><strong>Jellyfin</strong><small>Movies and TV</small></a>
              <a href="https://kavita.soderlind.dev"><strong>Kavita</strong><small>Books and comics</small></a>
              <a href="https://transmission.soderlind.dev"><strong>Transmission</strong><small>Torrent client</small></a>
            </nav>
          </main>
        </body>
        </html>
      '';
    };

    virtualHosts."bunko.soderlind.dev" = {
      forceSSL = true;
      useACMEHost = "soderlind.dev";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
        extraConfig = ''
          client_max_body_size 25m;
        '';
      };
    };

  };
}
