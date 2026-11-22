{ ... }:
{
  imports = [
    ../../modules/common
    ./hardware-configuration.nix
    ./services/karakeep.nix
    ./services/job-tracker.nix
    ./services/nginx.nix
  ];

  # Temporary inventory name; replace when provisioning the Proxmox VM.
  networking.hostName = "apps-vm";
  system.stateVersion = "26.05";
  services.qemuGuest.enable = true;
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  # Only SSH is open outside Tailscale (from modules/common).
  users.users.axel.linger = true;
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
}
