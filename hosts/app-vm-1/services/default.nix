{ config, lib, ... }:
{
  imports = [ ./karakeep.nix ./job-tracker.nix ./nginx.nix ];

  options.homelab.apps = {
    enable = lib.mkEnableOption "the application VM services";
    proxy.enable = lib.mkEnableOption "nginx after ACME credentials are provisioned";
  };

  config = lib.mkIf config.homelab.apps.enable {
    users.users.axel.linger = true;
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";
    # Image pulls on first activation can be slow.
    systemd.services = lib.genAttrs [
      "podman-karakeep" "podman-karakeep-search"
      "podman-karakeep-chrome" "podman-job-tracker"
    ] (_: { serviceConfig.TimeoutStartSec = lib.mkForce "3600s"; }) // {
      tailscaled = {
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
    };
    services.tailscale.enable = true;
    # Job Tracker must remain private; do not open HTTP(S) on the LAN.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
