{ config, ... }:
{
  # Runtime SECRET_KEY and SHOKU_PASSWORD; rootless Podman needs read access.
  age.secrets.shoku-env = {
    file = ../secrets/shoku-env.age;
    owner = "axel";
    group = "users";
    mode = "0400";
  };

  # Shoku job dashboard. The GHCR package must be public for unattended
  # anonymous pulls; use a version tag instead of :main to pin releases.
  systemd.tmpfiles.rules = [
    "d /var/lib/shoku 0750 axel users - -"
  ];

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.shoku = {
    image = "ghcr.io/asoderlind/shoku:2.2.1";
    autoStart = true;
    podman.user = "axel";

    # The image defaults to 8000; use an unused loopback-only host port
    # because Bunko already binds 127.0.0.1:8000.
    cmd = [
      "uvicorn"
      "app.main:app"
      "--host"
      "127.0.0.1"
      "--port"
      "8770"
    ];
    environment = {
      JOBDASH_DATA_DIR = "/app/data";
      SHOKU_COOKIE_SECURE = "1";
    };
    environmentFiles = [ config.age.secrets.shoku-env.path ];
    volumes = [
      "/var/lib/shoku:/app/data"
    ];
    extraOptions = [
      "--network=host"
      "--userns=keep-id:uid=0,gid=0"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
  };
}
