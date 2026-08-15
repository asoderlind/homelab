{
  config,
  pkgs,
  ...
}:

let
  runnerTokenFile = "/var/lib/agent-lab/secrets/forgejo-runner.env";
  runnerBootstrap = pkgs.writeShellApplication {
    name = "forgejo-runner-bootstrap";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run this command as root: sudo forgejo-runner-bootstrap" >&2
        exit 1
      fi

      token="$(runuser -u forgejo -- env \
        HOME=/var/lib/forgejo \
        USER=forgejo \
        FORGEJO_WORK_DIR=/var/lib/forgejo \
        FORGEJO_CUSTOM=/var/lib/forgejo/custom \
        ${config.services.forgejo.package}/bin/forgejo actions generate-runner-token \
          --work-path /var/lib/forgejo \
          --config /var/lib/forgejo/custom/conf/app.ini)"
      umask 0077
      printf 'TOKEN=%s\n' "$token" > ${runnerTokenFile}
      systemctl restart gitea-runner-hyperion.service
      echo "The isolated Forgejo runner is registered."
    '';
  };
in
{
  environment.systemPackages = [
    config.services.forgejo.package
    runnerBootstrap
  ];

  services.forgejo = {
    enable = true;
    lfs.enable = true;
    dump = {
      enable = true;
      interval = "daily";
      type = "tar.zst";
      age = "4w";
    };
    settings = {
      server = {
        DOMAIN = "hyperion";
        HTTP_ADDR = "0.0.0.0";
        HTTP_PORT = 3001;
        ROOT_URL = "http://hyperion:3001/";
        DISABLE_SSH = true;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
      actions.ENABLED = true;
      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_BRANCH = "main";
      };
      security = {
        LOGIN_REMEMBER_DAYS = 14;
        REVERSE_PROXY_LIMIT = 1;
      };
      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
      };
    };
  };

  services.gitea-actions-runner.instances.hyperion = {
    enable = true;
    name = "hyperion-container";
    url = "http://127.0.0.1:3001";
    tokenFile = runnerTokenFile;
    labels = [
      "debian-latest:docker://docker.io/library/node:24-bookworm"
      "ubuntu-latest:docker://docker.io/library/node:24-bookworm"
    ];
    settings = {
      log.level = "info";
      runner = {
        capacity = 1;
        timeout = "30m";
        shutdown_timeout = "30s";
      };
      container = {
        network = "";
        privileged = false;
        options = "--cpus=2 --memory=4g --pids-limit=512";
        valid_volumes = [ ];
        docker_host = "-";
        force_pull = true;
      };
    };
  };

  # A missing registration token is an intentional pre-bootstrap state, not a
  # failing boot unit. forgejo-runner-bootstrap creates it and starts the unit.
  systemd.services.gitea-runner-hyperion.unitConfig.ConditionPathExists = runnerTokenFile;
}
