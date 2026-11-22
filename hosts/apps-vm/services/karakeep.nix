{ config, pkgs, ... }:
let
  uid = toString config.users.users.axel.uid;
  network = "karakeep";
  common = {
    podman.user = "axel";
    extraOptions = [
      "--network=${network}"
      "--security-opt=no-new-privileges"
    ];
  };
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/karakeep 0700 axel users - -"
    "d /var/lib/karakeep/data 0700 axel users - -"
    "d /var/lib/karakeep/search 0700 axel users - -"
  ];

  # Generate credentials once on the host, never in the world-readable Nix store.
  # The same file supplies the search key to both Meilisearch and Karakeep.
  systemd.services.karakeep-setup = {
    requires = [ "user@${uid}.service" ];
    after = [ "user@${uid}.service" "systemd-tmpfiles-setup.service" ];
    path = [ pkgs.podman pkgs.openssl ];
    environment.XDG_RUNTIME_DIR = "/run/user/${uid}";
    serviceConfig = {
      Type = "oneshot";
      User = "axel";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      set -eu
      if [ ! -f /var/lib/karakeep/runtime.env ]; then
        printf 'NEXTAUTH_SECRET=%s\nMEILI_MASTER_KEY=%s\n' \
          "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" \
          > /var/lib/karakeep/runtime.env.tmp
        mv /var/lib/karakeep/runtime.env.tmp /var/lib/karakeep/runtime.env
      fi
      podman network exists ${network} || podman network create ${network}
    '';
  };

  systemd.services.podman-karakeep = {
    requires = [ "karakeep-setup.service" ];
    after = [ "karakeep-setup.service" ];
  };
  systemd.services.podman-karakeep-search = {
    requires = [ "karakeep-setup.service" ];
    after = [ "karakeep-setup.service" ];
  };
  systemd.services.podman-karakeep-chrome = {
    requires = [ "karakeep-setup.service" ];
    after = [ "karakeep-setup.service" ];
  };

  virtualisation.oci-containers.containers = {
    karakeep = common // {
      image = "ghcr.io/karakeep-app/karakeep:0.35.0";
      dependsOn = [ "karakeep-search" "karakeep-chrome" ];
      ports = [ "127.0.0.1:3006:3000" ];
      volumes = [ "/var/lib/karakeep/data:/data" ];
      environmentFiles = [ "/var/lib/karakeep/runtime.env" ];
      environment = {
        DATA_DIR = "/data";
        NEXTAUTH_URL = "https://karakeep.soderlind.dev";
        MEILI_ADDR = "http://karakeep-search:7700";
        BROWSER_WEB_URL = "http://karakeep-chrome:9222";
        # Enable temporarily in this module for initial account creation.
        DISABLE_SIGNUPS = "true";
      };
    };
    karakeep-search = common // {
      image = "docker.io/getmeili/meilisearch:v1.55.0";
      environmentFiles = [ "/var/lib/karakeep/runtime.env" ];
      environment.MEILI_NO_ANALYTICS = "true";
      volumes = [ "/var/lib/karakeep/search:/meili_data" ];
    };
    karakeep-chrome = common // {
      # Pin the separately published Chrome release to an immutable manifest.
      image = "ghcr.io/karakeep-app/karakeep-chrome@sha256:00fb4fa9c37aa74c58e74d0bdd16c4e3b81dddb5f264917c879f9579c3b3ad95";
      extraOptions = common.extraOptions ++ [ "--init" ];
      cmd = [
        "--disable-gpu"
        "--disable-dev-shm-usage"
        "--hide-scrollbars"
        "--disable-blink-features=AutomationControlled"
        "--window-size=1440,900"
      ];
    };
  };
}
