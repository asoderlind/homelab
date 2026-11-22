{ config, lib, ... }:
lib.mkIf config.homelab.apps.enable {
  systemd.tmpfiles.rules = map
    (dir: "d /var/lib/job-tracker/${dir} 0700 axel users - -")
    [ "" "data" "config" "state" "backups" ];

  virtualisation.oci-containers.containers.job-tracker = {
    image = "ghcr.io/muatasim-aswad/job-tracker:v2.0.2";
    podman.user = "axel";
    ports = [ "127.0.0.1:3456:3456" ];
    user = "10001:10001";
    environment = {
      JOB_TRACKER_PROFILE = "packaged";
      JOB_TRACKER_APP_DIR = "/app";
      JOB_TRACKER_DATA_DIR = "/data";
      JOB_TRACKER_CONFIG_DIR = "/config";
      JOB_TRACKER_STATE_DIR = "/state";
      JOB_TRACKER_BACKUP_DIR = "/backups";
      DB_PATH = "/data/jobtracker.db";
      SCRIPTS_OUTPUT_DIR = "/data/script-output";
      WEB_DIST_PATH = "/app/apps/web/dist";
      PORT = "3456";
      TRUSTED_HOSTS = ''["localhost","127.0.0.1","jobtracker.soderlind.dev"]'';
    };
    volumes = map (dir: "/var/lib/job-tracker/${dir}:/${dir}")
      [ "data" "config" "state" "backups" ];
    extraOptions = [
      "--userns=keep-id:uid=10001,gid=10001"
      "--init"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--memory=1g"
      "--pids-limit=128"
      "--stop-timeout=30"
    ];
  };
}
