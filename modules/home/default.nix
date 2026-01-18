{
  host,
  config,
  pkgs,
  ...
}:
{
  # Import modules
  imports = [
    ./git.nix
  ];
}

