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
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
  };
}
