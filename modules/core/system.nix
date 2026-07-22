{
  config,
  lib,
  pkgs,
  ...
}:

{
  time.timeZone = "Europe/Oslo";

  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # dbus-broker's reload hangs on this host (NixOS 26.05), wedging
  # switch-to-configuration and breaking logind/SSH sessions until force-killed.
  # Force a full restart instead, which works reliably.
  systemd.services.dbus.reloadIfChanged = lib.mkForce false;

  system.stateVersion = "25.11";
}
