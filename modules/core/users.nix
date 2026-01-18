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
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
  };
}
