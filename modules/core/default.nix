{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./boot.nix
    ./networking.nix
    ./nix.nix
    ./programs.nix
    ./security.nix
    ./users.nix
  ];
}
