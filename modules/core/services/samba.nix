{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Samba - accessible only via Tailscale (no firewall port opened).
  # NetBIOS/mDNS discovery doesn't cross Tailscale, so connect with
  # smb://<tailscale-ip-or-magicdns>/media rather than network browsing.
  services.samba = {
    enable = true;
    openFirewall = false;
    winbindd.enable = false; # no domain/LDAP integration needed
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "nixos-homelab-dell";
        "netbios name" = "nixos-homelab-dell";
        security = "user";
        "map to guest" = "never";
      };
      media = {
        path = "/mnt/backup/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "axel";
      };
    };
  };
}
