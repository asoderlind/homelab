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
    ./openproject.nix
  ];
}
