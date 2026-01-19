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
    80
    443
  ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
