{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.hostName = "nixos-homelab-dell";
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
  ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
  };

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
