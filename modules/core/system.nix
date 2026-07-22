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

  # Never touch dbus during nixos-rebuild switch / deploy; apply dbus unit
  # changes on the next reboot instead. Both ways of applying them live are
  # broken on this host (NixOS 26.05):
  #   - reload (the NixOS default): dbus-broker hangs on reload, wedging
  #     switch-to-configuration until it is force-killed
  #   - restart: stopping the system bus disconnects every bus client;
  #     switch-to-configuration loses its connection to systemd and aborts,
  #     and systemd-logind never reconnects, killing SSH session setup
  #     until logind is manually restarted
  # reloadIfChanged=false disables the reload path (mkForce because NixOS
  # sets it to true), restartIfChanged=false the restart path. Set on both
  # units because dbus.service is an alias of dbus-broker.service when
  # services.dbus.implementation == "broker" (the default).
  systemd.services.dbus.reloadIfChanged = lib.mkForce false;
  systemd.services.dbus.restartIfChanged = false;
  systemd.services.dbus-broker.reloadIfChanged = lib.mkForce false;
  systemd.services.dbus-broker.restartIfChanged = false;

  system.stateVersion = "25.11";
}
