{
  config,
  lib,
  pkgs,
  ...
}:

{
  age.secrets.openproject-env = {
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
      config.age.secrets.openproject-env.path
    ];
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/openproject/pgdata 0755 root root -"
    "d /var/lib/openproject/assets 0755 root root -"
  ];
}
