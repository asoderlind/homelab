{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Persistent habit data (SQLite db under HABITS_STORAGE=DATABASE).
  # uid/gid 1000 matches axel (see filesystems.nix) - the container is
  # forced to run as 1000:1000 below so its writes land as axel on disk.
  systemd.tmpfiles.rules = [
    "d /var/lib/beaverhabits 0750 axel users - -"
  ];

  # podman is the oci-containers default backend on stateVersion >= 22.05;
  # set explicitly since this repo has no rootful Docker daemon anymore.
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.beaverhabits = {
    # daya0576/beaverhabits doesn't publish semver tags to Docker Hub;
    # this digest is what `latest` pointed to on 2026-05-20, the v0.9.1
    # release date. Re-pin deliberately when upgrading.
    image = "daya0576/beaverhabits@sha256:6cd7e464207369785c88cfd59f99c6cc44ec57f3a8d90c3439908da42271d69f";
    # Keep the container definition and persistent state, but do not start the service.
    autoStart = false;
    user = "1000:1000";
    environment = {
      HABITS_STORAGE = "DATABASE";
    };
    volumes = [
      "/var/lib/beaverhabits:/app/.user"
    ];
    # podman.user: run this rootless, as axel, instead of a root daemon -
    # no privileged process to compromise if the container is breached.
    podman.user = "axel";
    extraOptions = [
      # --network=host: stay under the same nftables/tailscale0 filtering as
      # every other service. Rootless containers don't get a privileged
      # port-publish path anyway, but host networking also avoids the
      # slirp4netns/pasta userspace-proxy overhead of podman's default
      # rootless networking.
      "--network=host"
      # axel (uid 1000) is the invoking user; --userns=keep-id maps that
      # real identity 1:1 into the container instead of into podman's
      # normal subuid range, so the container's declared `user = 1000:1000`
      # writes to /var/lib/beaverhabits as axel, matching its ownership.
      "--userns=keep-id:uid=1000,gid=1000"
    ];
  };
}
