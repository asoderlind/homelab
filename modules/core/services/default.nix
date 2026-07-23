{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./grafana.nix
    ./prometheus.nix
    ./jellyfin.nix
    ./samba.nix
    ./beaverhabits.nix
    ./smart.nix
    ./alertmanager.nix
    ./nginx.nix
  ];
}
