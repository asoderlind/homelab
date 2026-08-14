{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
  ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
  };
}
