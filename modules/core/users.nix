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
    # Shared laptop key. Each host adds the key used by its deploy-rs SSH
    # identity so activating either configuration cannot lock out deployment.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axesode@gmail.com"
    ];
    packages = with pkgs; [ ];
  };
}
