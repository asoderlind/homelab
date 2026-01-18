{
  config,
  lib,
  pkgs,
  ...
}:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Increase timeouts for downloading packages
    connect-timeout = 60;
    stalled-download-timeout = 300;

    # Automatically run garbage collection when disk space is low
    min-free = "${toString (1024 * 1024 * 1024)}"; # 1GB
    max-free = "${toString (5 * 1024 * 1024 * 1024)}"; # 5GB

    # Don't warn about dirty Git trees
    warn-dirty = false;
  };

  # More aggressive garbage collection for low disk space
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # Optimise store to deduplicate files (hardlink identical files)
  nix.optimise.automatic = true;
  nixpkgs.config.allowUnfree = true;
}
