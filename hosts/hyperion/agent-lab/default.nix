{
  imports = [
    ./agents.nix
    ./buzz.nix
    ./forgejo.nix
  ];

  # All application ports remain closed on the LAN firewall. Tailscale's
  # authenticated interface is the private ingress path for the lab.
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Burst protection for three bounded Hermes processes. This is compressed
  # RAM-backed swap, sized as a percentage of physical memory.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };
}
