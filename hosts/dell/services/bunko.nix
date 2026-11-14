{ config, ... }:
{
  # Bunko stores its SQLite database and uploaded media together under /data.
  # The container runs rootless as axel, so the decrypted environment file must
  # be readable by that user rather than root-only like most system services.
  age.secrets.bunko-env = {
    file = ../secrets/bunko-env.age;
    owner = "axel";
    group = "users";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/bunko 0750 axel users - -"
  ];

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.bunko = {
    # The release workflow publishes this tag as linux/amd64 for Dell.
    # Pin to an image digest after inspecting the release if desired.
    image = "ghcr.io/asoderlind/bunko:0.0.3";
    autoStart = true;
    podman.user = "axel";

    # Keep the service private to the host; nginx provides the HTTPS entrypoint.
    cmd = [
      "sh"
      "-c"
      "python -m app.cli init-db && alembic upgrade head && exec uvicorn app.main:app --host 127.0.0.1 --port 8000"
    ];
    environment = {
      DATABASE_URL = "sqlite:////data/bunko.sqlite3";
      DEBUG = "0";
      ALLOWED_HOSTS = "bunko.soderlind.dev,127.0.0.1";
      TAGGING_POLL_SECONDS = "2";
    };
    environmentFiles = [ config.age.secrets.bunko-env.path ];
    volumes = [
      "/var/lib/bunko:/data"
    ];
    extraOptions = [
      "--network=host"
      "--userns=keep-id:uid=0,gid=0"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
  };
}
