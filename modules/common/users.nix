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
    # Pinned to match the existing account and shared data ownership on disk.
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
