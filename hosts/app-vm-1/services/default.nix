{ config, lib, ... }:
{
  imports = [ ./karakeep.nix ./job-tracker.nix ./nginx.nix ];

  options.homelab.apps.enable = lib.mkEnableOption "the application VM services";

  config = lib.mkIf config.homelab.apps.enable {
    users.users.axel.linger = true;
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";
    services.tailscale.enable = true;
    # Job Tracker must remain private; do not open HTTP(S) on the LAN.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
