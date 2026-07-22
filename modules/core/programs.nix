{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    claude-code
    curl
    fastfetch
    git
    tmux
    vim
    wget
  ];
}
