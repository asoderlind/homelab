{
  lib,
  pkgs,
  buzzSrc,
  ...
}:

let
  composeDir = "/var/lib/buzz/compose";
  composeFile = "${composeDir}/compose.yml";
  envFile = "${composeDir}/.env";
  secretsDir = "/var/lib/agent-lab/secrets";
  # The pinned Buzz source commit only changes the desktop release metadata, so
  # it did not publish a relay image. Its parent contains identical relay and
  # Compose sources and has a published multi-architecture image.
  buzzImage = "ghcr.io/block/buzz:sha-4749bc7@sha256:1cf416a2f7794498bbbcffb88568f9869fa98c9b345f7a343f05287bf03d285d";
  buzzTools = pkgs.callPackage ./package.nix { inherit buzzSrc; };
  dockerCompose = "${pkgs.docker}/bin/docker compose --project-directory ${composeDir} --env-file ${envFile} -f ${composeFile}";

  buzzBootstrap = pkgs.writeShellApplication {
    name = "buzz-bootstrap";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      gawk
      gnugrep
      gnused
      openssl
      systemd
    ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run this command as root: sudo buzz-bootstrap <owner-pubkey>" >&2
        exit 1
      fi

      owner_pubkey="''${1:-}"
      if [ ! -s ${envFile} ]; then
        if ! [[ "$owner_pubkey" =~ ^[0-9a-fA-F]{64}$ ]]; then
          echo "Supply the 64-character hex pubkey of your human Buzz identity." >&2
          exit 1
        fi
        owner_pubkey="''${owner_pubkey,,}"

        umask 0077
        relay_key="$(openssl rand -hex 32)"
        hook_secret="$(openssl rand -hex 32)"
        postgres_password="$(openssl rand -hex 32)"
        redis_password="$(openssl rand -hex 32)"
        s3_access_key="$(openssl rand -hex 16)"
        s3_secret_key="$(openssl rand -hex 32)"

        install -d -m 0700 ${composeDir}
        {
          echo "BUZZ_IMAGE=${buzzImage}"
          echo "BUZZ_DOMAIN=hyperion"
          echo "RELAY_URL=ws://hyperion:3000"
          echo "BUZZ_MEDIA_BASE_URL=http://hyperion:3000/media"
          echo "BUZZ_MEDIA_SERVER_DOMAIN=hyperion"
          echo "BUZZ_CORS_ORIGINS=http://hyperion:3000"
          echo "BUZZ_REQUIRE_AUTH_TOKEN=true"
          echo "BUZZ_REQUIRE_RELAY_MEMBERSHIP=true"
          echo "BUZZ_ALLOW_NIP_OA_AUTH=true"
          echo "BUZZ_AUTO_MIGRATE=true"
          echo "BUZZ_GIT_CONFORMANCE_PROBE=true"
          echo "RUST_LOG=buzz_relay=info,buzz_db=info,buzz_auth=info,buzz_pubsub=info,tower_http=info"
          echo "RELAY_OWNER_PUBKEY=$owner_pubkey"
          echo "BUZZ_RELAY_PRIVATE_KEY=$relay_key"
          echo "BUZZ_GIT_HOOK_HMAC_SECRET=$hook_secret"
          echo "POSTGRES_DB=buzz"
          echo "POSTGRES_USER=buzz"
          echo "POSTGRES_PASSWORD=$postgres_password"
          echo "REDIS_PASSWORD=$redis_password"
          echo "BUZZ_S3_ACCESS_KEY=$s3_access_key"
          echo "BUZZ_S3_SECRET_KEY=$s3_secret_key"
          echo "BUZZ_S3_BUCKET=buzz-media"
          echo "BUZZ_S3_ADDRESSING_STYLE=path"
          echo "BUZZ_HTTP_PORT=3000"
        } > ${envFile}
        chmod 0600 ${envFile}
      else
        owner_pubkey="$(awk -F= '$1 == "RELAY_OWNER_PUBKEY" { print $2 }' ${envFile})"
      fi

      # Keep generated secrets stable while reconciling the declarative image
      # pin. This also repairs .env files left by an unavailable image tag.
      if grep -q '^BUZZ_IMAGE=' ${envFile}; then
        sed -i 's|^BUZZ_IMAGE=.*$|BUZZ_IMAGE=${buzzImage}|' ${envFile}
      else
        printf '%s\n' 'BUZZ_IMAGE=${buzzImage}' >> ${envFile}
      fi

      ${dockerCompose} up -d --wait --remove-orphans

      install -d -m 0700 ${secretsDir}
      roles=(coordinator developer ops)
      for role in "''${roles[@]}"; do
        if [ ! -s "${secretsDir}/$role.key" ] || [ ! -s "${secretsDir}/$role.pub" ]; then
          keypair="$(${dockerCompose} exec -T relay buzz-admin generate-key)"
          public_key="$(awk '/^Public key:/ { print $3 }' <<<"$keypair")"
          private_key="$(awk '/^Secret key:/ { print $3 }' <<<"$keypair")"
          printf '%s\n' "$private_key" > "${secretsDir}/$role.key"
          printf '%s\n' "$public_key" > "${secretsDir}/$role.pub"
          chmod 0600 "${secretsDir}/$role.key" "${secretsDir}/$role.pub"
        fi
        ${dockerCompose} exec -T relay buzz-admin add-member \
          --pubkey "$(cat "${secretsDir}/$role.pub")" --role member >/dev/null
      done

      all_agents="$(awk 'BEGIN { sep="" } { printf "%s%s", sep, $0; sep="," } END { print "" }' \
        ${secretsDir}/coordinator.pub ${secretsDir}/developer.pub ${secretsDir}/ops.pub)"
      for role in "''${roles[@]}"; do
        identity_env="${secretsDir}/$role.env"
        preserved_env="$(mktemp "${secretsDir}/.$role.env.XXXXXX")"
        next_env="$(mktemp "${secretsDir}/.$role.env.XXXXXX")"
        if [ -f "$identity_env" ]; then
          grep -E '^(FORGEJO_USERNAME|FORGEJO_TOKEN|BUZZ_CHANNELS|BUZZ_HOME_CHANNEL)=' \
            "$identity_env" > "$preserved_env" || true
        fi
        {
          echo "BUZZ_PRIVATE_KEY=$(cat "${secretsDir}/$role.key")"
          echo "BUZZ_ALLOWED_USERS=$owner_pubkey,$all_agents"
          echo "BUZZ_ALLOW_ALL_USERS=false"
          cat "$preserved_env"
        } > "$next_env"
        rm -f "$preserved_env"
        chown "root:agent-$role" "$next_env"
        chmod 0640 "$next_env"
        mv -f "$next_env" "$identity_env"

        case "$role" in
          coordinator) profile_name="Coordinator" ;;
          developer) profile_name="Developer" ;;
          ops) profile_name="Ops" ;;
        esac
        BUZZ_PRIVATE_KEY="$(cat "${secretsDir}/$role.key")" \
          BUZZ_RELAY_URL=ws://127.0.0.1:3000 \
          ${buzzTools}/bin/buzz users set-profile \
            --name "$profile_name" \
            --about "Hyperion agent-lab $role agent" >/dev/null || \
          echo "Warning: could not publish the $role Buzz profile yet." >&2
      done

      systemctl try-restart agent-lab-coordinator.service || true
      systemctl try-restart agent-lab-developer.service || true
      systemctl try-restart agent-lab-ops.service || true

      echo
      echo "Buzz is running at http://hyperion:3000 on the tailnet."
      echo "Agent identities and private Hermes allowlists are registered."
      echo "Next: add each role's FORGEJO_USERNAME/TOKEN to its .env file,"
      echo "run agent-lab-auth for each role, then run agent-lab-wiki-bootstrap."
    '';
  };
in
{
  environment.systemPackages = [
    buzzBootstrap
    buzzTools
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/buzz 0700 root root - -"
    "d ${composeDir} 0700 root root - -"
    "L+ ${composeFile} - - - - ${buzzSrc}/deploy/compose/compose.yml"
    "d /var/lib/agent-lab 0751 root root - -"
    "d ${secretsDir} 0700 root root - -"
  ];

  systemd.services.buzz-compose = {
    description = "Buzz production Docker Compose stack";
    after = [
      "docker.service"
      "network-online.target"
    ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = envFile;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${dockerCompose} up -d --wait --remove-orphans";
      ExecReload = "${dockerCompose} up -d --wait --remove-orphans";
      ExecStop = "${dockerCompose} stop";
      TimeoutStartSec = 300;
      TimeoutStopSec = 120;
    };
  };

  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.docker-compose.version "2.24.4";
      message = "Buzz's production bundle requires a current Docker Compose v2 implementation.";
    }
  ];
}
