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
    git
    neofetch
    tmux
    vim
    wget
  ];
}
