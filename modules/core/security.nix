{
  config,
  lib,
  pkgs,
  ...
}:

{
  security = {
    apparmor.enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  services.fail2ban = {
    enable = true;
    jails.sshd.enabled = true;
  };
}
