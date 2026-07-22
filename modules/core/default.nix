{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./boot.nix
    ./filesystems.nix
    ./hardware.nix
    ./networking.nix
    ./nix.nix
    ./programs.nix
    ./security.nix
    ./services
    ./system.nix
    ./virtualisation.nix
    ./users.nix
  ];
}
