{ lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ./services ];

  # Enable only after base deployment, reboot verification, and secret provisioning.
  homelab.apps.enable = false;

  boot.loader.grub.enable = true;
  boot.loader.grub.devices = [ "/dev/sda" ];
  boot.kernelParams = [ "console=ttyS0,115200" ];

  networking.hostName = "app-vm-1";
  # Keep DHCP until the address reservation strategy is agreed.
  networking.useDHCP = lib.mkDefault true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  services.openssh.enable = true;

  users.users.axel = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axel@soderlind.dev"
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axel@soderlind.dev"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
  ];
  system.stateVersion = "26.05";
}
