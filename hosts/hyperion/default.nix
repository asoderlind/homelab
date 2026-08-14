{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
  ];

  networking.hostName = "hyperion";
  time.timeZone = "Europe/Stockholm";

  # Preserve the newer kernel selected by Hyperion's initial standalone
  # configuration while sharing the repository's nixpkgs pin.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  users.users.axel = {
    packages = [ pkgs.tree ];
    # deploy-rs connects with ~/.ssh/homelab/hyperion.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDSly1lk4JGEf9X6SitQzGbyUJXRaWLh653+E0MP2pH+lJ8nK2Gc8+rp4Z9WxbUgMgHoLUMR/rvbOp1v48OsXJDIaZfXLCBAjAWzI/cBKcd9BD8nXieO03LZLPZrL4FiJHovSZ6R8foWiqmL5PRcccQ2/jWaZcouaqYfMIHf67IoN4KOHnV9RdSxyC0sGD/S99/yVWtDqfXsBt/yTaELyMB3wcrS9xWycoPO/PgbrqDq66DU3DHJ0B4iSVv4ST+0ZoxUWocY1OXXn+FVPYgU+0YXlHR/77GubQ5bjGAc/rcB/7FYzSUNgMV0fYXPS5r3J/wPgpF0nZobzuH2DDRQfWr2bhGre1RRmYTi44gBQzgbsldJXfjcx9UW2ROur7/6f5ceZQ9OhoXhm96loOdoYiGcyJpc6X6NF0PFOIF+5mh6iE8ONHWI6cPvyAjGyB+R/ej4mLBJ0UnscJyFk1tqM30E0p5jBC1EX/d/8eILfzWvoRIzJqo8ADhWsMxAeqOvgE= axel@Axels-macbook.local"
    ];
  };

  # Keep the compatibility baseline from Hyperion's initial installation.
  system.stateVersion = "26.05";
}
