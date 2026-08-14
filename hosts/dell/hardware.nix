{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Intel AC 8260's default balanced power_scheme throttles throughput to
  # near-zero (~15KB/s) despite good signal; CAM (1) keeps the radio fully
  # awake and restores normal speeds.
  boot.extraModprobeConfig = "options iwlmvm power_scheme=1";
}
