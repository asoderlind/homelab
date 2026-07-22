{
  config,
  lib,
  pkgs,
  ...
}:

{
  virtualisation.docker = {
    enable = true;
    # nixpkgs' `docker` alias tracks docker_28, which is now marked
    # insecure/unmaintained; pin to a maintained major version explicitly.
    package = pkgs.docker_29;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
