{
  config,
  lib,
  pkgs,
  ...
}:

{
  users.users.axel = {
    isNormalUser = true;
    description = "axel";
    # Pinned (matches the account already on disk - see filesystems.nix)
    # so oci-containers can resolve /run/user/1000 for rootless Podman's
    # RequiresMountsFor at eval time instead of an unresolved UID.
    uid = 1000;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
    # Rootless Podman containers run as axel via a system unit
    # (virtualisation.oci-containers' `podman.user`); lingering keeps
    # /run/user/1000 available at boot so that unit doesn't race an
    # interactive login.
    linger = true;
  };
}
