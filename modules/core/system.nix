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

  system.stateVersion = "25.11";
}
