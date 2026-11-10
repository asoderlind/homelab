{ ... }:
{
  # Accounts, chats, uploads and admin connection settings persist under
  # /var/lib/open-webui-container. Enter the OpenRouter key in Admin Panel > Settings
  # > Connections after creating the first (administrator) account.
  systemd.tmpfiles.rules = [
    "d /var/lib/open-webui-container 0700 axel users - -"
  ];

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.open-webui = {
    # Match the previous native package version; no local frontend build.
    image = "ghcr.io/open-webui/open-webui:v0.13.3";
    autoStart = true;
    podman.user = "axel";
    # Root inside this rootless container maps to axel on the host.
    user = "0:0";
    volumes = [ "/var/lib/open-webui-container:/app/backend/data" ];
    extraOptions = [
      "--network=host"
      "--userns=keep-id:uid=0,gid=0"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
    environment = {
      HOST = "127.0.0.1";
      PORT = "8081";
      # Keep the generated signing key across container replacements.
      WEBUI_SECRET_KEY_FILE = "/app/backend/data/.webui_secret_key";
      WEBUI_URL = "https://chat.soderlind.dev";
      WEBUI_AUTH = "True";
      ENABLE_OLLAMA_API = "False";
      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = "https://openrouter.ai/api/v1";
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
    };
  };

  services.nginx.virtualHosts."chat.soderlind.dev" = {
    forceSSL = true;
    useACMEHost = "soderlind.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8081";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        client_max_body_size 50m;
      '';
    };
  };
}
