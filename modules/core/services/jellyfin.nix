{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Jellyfin - accessible only via Tailscale (no firewall port opened)
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # Intel QuickSync hardware transcoding
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD VAAPI driver (Broadwell/2014+)
      intel-vaapi-driver # legacy i965 fallback
      libvdpau-va-gl
    ];
  };

  # Jellyfin's service user needs /dev/dri access for hw transcoding
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
  ];
}
