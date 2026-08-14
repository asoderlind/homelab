{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Rootless Podman instead of a rootful Docker daemon: no privileged daemon
  # to compromise, and being in a "docker"-equivalent group is no longer the
  # same as having root. Containers run as the invoking user (see
  # beaverhabits.nix's `podman.user`), using each normal user's
  # auto-allocated subuid/subgid range (NixOS default, users-groups.nix).
  virtualisation.podman = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
