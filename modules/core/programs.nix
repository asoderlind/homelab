{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    curl
    fastfetch
    git
    tmux
    vim
    wget
  ];
}
