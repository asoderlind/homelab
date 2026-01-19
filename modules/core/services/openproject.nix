{
  config,
  lib,
  pkgs,
  ...
}:

{
  age.secrets.openproject-secret-key = {
    file = ../../../secrets/openproject-secret-key.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  virtualisation.oci-containers.containers.openproject = {
    image = "openproject/openproject:15";
    ports = [ "8080:80" ];
    volumes = [
      "/var/lib/openproject/pgdata:/var/openproject/pgdata"
      "/var/lib/openproject/assets:/var/openproject/assets"
    ];
    environment = {
      OPENPROJECT_HOST__NAME = "nixos-homelab-dell:8080";
      OPENPROJECT_HTTPS = "false";
      OPENPROJECT_DEFAULT__LANGUAGE = "en";
    };
    environmentFiles = [
      "/run/secrets/openproject-env"
    ];
  };

  # Generate environment file from agenix secret before container starts
  systemd.services.openproject-env-setup = {
    description = "Generate OpenProject environment file from agenix secret";
    wantedBy = [ "podman-openproject.service" ];
    before = [ "podman-openproject.service" ];
    after = [ "agenix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo "OPENPROJECT_SECRET_KEY_BASE=$(cat ${config.age.secrets.openproject-secret-key.path})" > /run/secrets/openproject-env
      chmod 400 /run/secrets/openproject-env
    '';
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/openproject/pgdata 0755 root root -"
    "d /var/lib/openproject/assets 0755 root root -"
    "d /run/secrets 0755 root root -"
  ];
}
