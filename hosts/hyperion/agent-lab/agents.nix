{
  hermesAgent,
  lib,
  mnemosyneSrc,
  pkgs,
  buzzSrc,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  roles = [
    "coordinator"
    "developer"
    "ops"
  ];
  roleHome = role: "/var/lib/agent-lab/agents/${role}";
  hermesHome = role: "${roleHome role}/.hermes";
  workspace = role: "${roleHome role}/workspace";
  secretsDir = "/var/lib/agent-lab/secrets";

  buzzCli = pkgs.callPackage ./package.nix { inherit buzzSrc; };
  mnemosyneHermes = pkgs.callPackage ./mnemosyne-package.nix { inherit mnemosyneSrc; };
  # Hermes v2026.8.13 imports this top-level module but accidentally omits it
  # from tool.setuptools.py-modules, so its sealed Nix wheel cannot find it.
  # Expose the exact file from the pinned Hermes source until upstream's Nix
  # package includes it itself.
  hermesRegistrationLifecycle = pkgs.python312Packages.toPythonModule (
    pkgs.stdenvNoCC.mkDerivation {
      pname = "hermes-registration-lifecycle";
      version = "2026.8.13";
      dontUnpack = true;
      installPhase = ''
        install -Dm0444 \
          ${hermesAgent.outPath}/registration_lifecycle.py \
          $out/${pkgs.python312.sitePackages}/registration_lifecycle.py
      '';
    }
  );
  # Hermes's sealed environment already contains common dependencies such as
  # PyYAML, NumPy, ONNX Runtime, Hugging Face Hub, and tokenizers. Expose only
  # the Mnemosyne/FastEmbed modules it lacks so Hermes's collision check keeps
  # the sealed versions authoritative.
  withoutPropagatedPythonDeps =
    package:
    let
      bareModule =
        (pkgs.symlinkJoin {
          name = "${lib.getName package}-for-hermes";
          paths = [ package ];
          postBuild = ''
            rm -f $out/nix-support/propagated-build-inputs
          '';
        }).overrideAttrs
          (_: {
            propagatedBuildInputs = [ ];
          });
    in
    pkgs.python312Packages.toPythonModule bareModule;
  mnemosynePythonModules = map withoutPropagatedPythonDeps (
    with pkgs.python312Packages;
    [
      mnemosyneHermes
      mnemosyneHermes.mnemosyneMemory
      fastembed
      sqlite-vec
      loguru
      mmh3
      py-rust-stemmers
      pystemmer
      snowballstemmer
    ]
  );
  hermesPackage = hermesAgent.packages.${system}.default.override {
    extraPythonPackages = [ hermesRegistrationLifecycle ] ++ mnemosynePythonModules;
  };
  forgejoAskPass = pkgs.writeShellScript "agent-lab-forgejo-askpass" ''
    case "''${1:-}" in
      *Username*) printf '%s\n' "''${FORGEJO_USERNAME:?FORGEJO_USERNAME is not set}" ;;
      *) printf '%s\n' "''${FORGEJO_TOKEN:?FORGEJO_TOKEN is not set}" ;;
    esac
  '';

  denialRules = [
    "*sudo*"
    "*doas*"
    "*su -*"
    "*rm -rf*"
    "*rm -fr*"
    "*find *-delete*"
    "*git clean*"
    "*git reset*--hard*"
    "*git push*--force*"
    "*git push*-f*"
    "*pulls/*/merge*"
    "*tea pr merge*"
    "*nixos-rebuild*"
    "*deploy-rs*"
    "*rs-deploy*"
    "*systemctl*"
    "*service *"
    "*loginctl*"
    "*hostnamectl*"
    "*timedatectl*"
    "*networkctl*"
    "*nmcli*"
    "*mount *"
    "*umount*"
    "*shutdown*"
    "*reboot*"
    "*poweroff*"
    "*docker*"
    "*podman*"
    "*passwd*"
    "*useradd*"
    "*usermod*"
    "*userdel*"
    "deploy *"
    "*/deploy *"
  ];

  mkHermesConfig =
    role:
    (pkgs.formats.yaml { }).generate "agent-lab-${role}-config.yaml" {
      model = {
        default = "gpt-5.6-terra";
        provider = "openai-codex";
      };
      delegation = {
        model = "gpt-5.6-terra";
        provider = "openai-codex";
        max_concurrent_children = 2;
        max_spawn_depth = 1;
        orchestrator_enabled = false;
        worktree_isolation = role == "developer";
      };
      max_concurrent_sessions = 1;
      approvals = {
        mode = "manual";
        cron_mode = "deny";
        denial_breaker_threshold = 3;
        deny = denialRules;
      };
      terminal = {
        cwd = workspace role;
        home_mode = "profile";
      };
      memory = {
        provider = "mnemosyne";
        memory_enabled = false;
        mnemosyne = {
          auto_sleep = true;
          sleep_threshold = 50;
        };
      };
      user_profile_enabled = false;
      gateway = {
        max_concurrent_sessions = 1;
        platforms.buzz = {
          enabled = true;
          extra = {
            relay_url = "ws://hyperion:3000";
            cli_path = "${buzzCli}/bin/buzz";
            poll_interval = 4;
            require_mention = true;
            allow_all_users = false;
          };
        };
      };
      display.platforms.buzz = {
        interim_assistant_messages = false;
        tool_progress = "off";
      };
    };

  roleUsers = lib.genAttrs (map (role: "agent-${role}") roles) (
    user:
    let
      role = lib.removePrefix "agent-" user;
    in
    {
      isSystemUser = true;
      group = user;
      home = roleHome role;
      createHome = true;
      shell = pkgs.bashInteractive;
    }
  );
  roleGroups = lib.genAttrs (map (role: "agent-${role}") roles) (_: { });

  prepareProfile =
    role:
    pkgs.writeShellScript "agent-lab-${role}-prepare-profile" ''
      set -eu
      install -d -m 0700 \
        ${hermesHome role} \
        ${hermesHome role}/skills \
        ${hermesHome role}/mnemosyne \
        ${roleHome role}/.cache/fastembed \
        ${workspace role}
      ln -sfnT ${mkHermesConfig role} ${hermesHome role}/config.yaml
      ln -sfnT ${./profiles + "/${role}/SOUL.md"} ${hermesHome role}/SOUL.md
      ln -sfnT ${./profiles/AGENTS.md} ${workspace role}/AGENTS.md
      ln -sfnT ${./profiles + "/${role}/skills"} \
        ${hermesHome role}/skills/nix-managed-${role}
    '';

  mkAgentService = role: {
    description = "Hermes Buzz gateway for the ${role} agent";
    after = [
      "buzz-compose.service"
      "forgejo.service"
      "network-online.target"
    ];
    wants = [
      "buzz-compose.service"
      "forgejo.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [
      "${secretsDir}/${role}.env"
      "${hermesHome role}/auth.json"
    ];
    environment = {
      HOME = roleHome role;
      HERMES_HOME = hermesHome role;
      HERMES_MANAGED = "true";
      BUZZ_RELAY_URL = "ws://hyperion:3000";
      BUZZ_CLI_PATH = "${buzzCli}/bin/buzz";
      BUZZ_TRANSPORT = "auto";
      FORGEJO_URL = "http://127.0.0.1:3001";
      GIT_ASKPASS = forgejoAskPass;
      GIT_TERMINAL_PROMPT = "0";
      MNEMOSYNE_HOME = "${hermesHome role}/mnemosyne";
      MNEMOSYNE_DATA_DIR = "${hermesHome role}/mnemosyne/data";
      MNEMOSYNE_FASTEMBED_CACHE_DIR = "${roleHome role}/.cache/fastembed";
      MNEMOSYNE_EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
      MNEMOSYNE_EMBEDDING_DIM = "384";
      MNEMOSYNE_LLM_ENABLED = "true";
      MNEMOSYNE_HOST_LLM_ENABLED = "true";
      MNEMOSYNE_HOST_LLM_PROVIDER = "openai-codex";
      MNEMOSYNE_HOST_LLM_MODEL = "gpt-5.6-terra";
    };
    path = with pkgs; [
      bashInteractive
      coreutils
      curl
      findutils
      git
      gnugrep
      gnused
      jq
      nix
      openssh
      ripgrep
    ];
    serviceConfig = {
      User = "agent-${role}";
      Group = "agent-${role}";
      EnvironmentFile = "${secretsDir}/${role}.env";
      ExecStartPre = prepareProfile role;
      ExecStart = "${hermesPackage}/bin/hermes gateway run --replace";
      WorkingDirectory = workspace role;
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStopSec = 90;

      # The role owns only its private profile and workspace. Unix directory
      # permissions prevent cross-role reads; systemd removes host privileges.
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      ProtectSystem = "strict";
      ReadWritePaths = [ (roleHome role) ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      MemoryHigh = "2G";
      MemoryMax = "3G";
      CPUQuota = "150%";
      TasksMax = 512;
      UMask = "0077";
    };
  };

  agentLabAuth = pkgs.writeShellApplication {
    name = "agent-lab-auth";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo agent-lab-auth <coordinator|developer|ops>" >&2
        exit 1
      fi

      role="''${1:-}"
      case "$role" in
        coordinator|developer|ops) ;;
        *) echo "Usage: agent-lab-auth <coordinator|developer|ops>" >&2; exit 2 ;;
      esac

      user="agent-$role"
      home="/var/lib/agent-lab/agents/$role"
      hermes_home="$home/.hermes"
      service="agent-lab-$role.service"

      systemctl stop "$service" || true
      install -d -m 0700 -o "$user" -g "$user" "$home" "$hermes_home"
      runuser -u "$user" -- env \
        HOME="$home" \
        HERMES_HOME="$hermes_home" \
        ${hermesPackage}/bin/hermes auth add openai-codex

      if [ ! -s "$hermes_home/auth.json" ]; then
        echo "Hermes did not create $hermes_home/auth.json; service remains stopped." >&2
        exit 1
      fi
      chown "$user:$user" "$hermes_home/auth.json"
      chmod 0600 "$hermes_home/auth.json"

      if [ -s "${secretsDir}/$role.env" ]; then
        systemctl restart "$service"
        echo "Authenticated $role and restarted $service."
      else
        echo "Authenticated $role. Run buzz-bootstrap before starting $service."
      fi
    '';
  };

  wikiBootstrap = pkgs.writeShellApplication {
    name = "agent-lab-wiki-bootstrap";
    runtimeInputs = with pkgs; [
      coreutils
      git
      gnugrep
      util-linux
    ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo agent-lab-wiki-bootstrap [forgejo-owner]" >&2
        exit 1
      fi

      owner="''${1:-axel}"
      remote="http://127.0.0.1:3001/$owner/agent-wiki.git"
      old_wiki=/var/lib/agent-lab/wiki.git
      migration=/var/lib/agent-lab/wiki-migration.git

      load_role_credentials() {
        local role="$1"
        local env_file="${secretsDir}/$role.env"
        FORGEJO_USERNAME=""
        FORGEJO_TOKEN=""
        if [ ! -r "$env_file" ]; then
          echo "Missing $env_file; run buzz-bootstrap first." >&2
          exit 1
        fi
        # shellcheck disable=SC1090
        . "$env_file"
        if [ -z "''${FORGEJO_USERNAME:-}" ] || [ -z "''${FORGEJO_TOKEN:-}" ]; then
          echo "$env_file must contain FORGEJO_USERNAME and FORGEJO_TOKEN." >&2
          exit 1
        fi
        export FORGEJO_USERNAME FORGEJO_TOKEN
        export GIT_ASKPASS=${forgejoAskPass}
        export GIT_TERMINAL_PROMPT=0
      }

      git_as_role() {
        local role="$1"
        shift
        runuser -u "agent-$role" -- git "$@"
      }

      load_role_credentials coordinator
      if ! git_as_role coordinator ls-remote "$remote" >/dev/null; then
        echo "Cannot access $remote. Create the private repository and scoped role tokens first." >&2
        exit 1
      fi

      if git --git-dir="$old_wiki" rev-parse --verify HEAD >/dev/null 2>&1; then
        if [ -z "$(git_as_role coordinator ls-remote "$remote")" ]; then
          if [ ! -d "$migration" ]; then
            git clone --mirror "$old_wiki" "$migration"
            chown -R agent-coordinator:agent-coordinator "$migration"
          fi
          git_as_role coordinator -C "$migration" remote remove forgejo 2>/dev/null || true
          git_as_role coordinator -C "$migration" remote add forgejo "$remote"
          git_as_role coordinator -C "$migration" push forgejo --all
          git_as_role coordinator -C "$migration" push forgejo --tags
          echo "Migrated the old bare wiki; $old_wiki and $migration were retained."
        else
          echo "The old bare wiki was retained at $old_wiki; Forgejo already has content, so no automatic migration was attempted."
        fi
      fi

      for role in coordinator developer ops; do
        load_role_credentials "$role"
        clone="/var/lib/agent-lab/agents/$role/workspace/agent-wiki"
        if [ -d "$clone/.git" ]; then
          if ! git_as_role "$role" -C "$clone" diff --quiet || \
             ! git_as_role "$role" -C "$clone" diff --cached --quiet; then
            echo "$clone has local changes; refusing to pull." >&2
            exit 1
          fi
          git_as_role "$role" -C "$clone" pull --rebase
        elif [ -e "$clone" ]; then
          echo "$clone exists but is not a Git clone; refusing to replace it." >&2
          exit 1
        else
          git_as_role "$role" clone "$remote" "$clone"
        fi
        git_as_role "$role" -C "$clone" config pull.rebase true
        git_as_role "$role" -C "$clone" config rebase.autoStash false
        git_as_role "$role" -C "$clone" config push.default simple
        git_as_role "$role" -C "$clone" config credential.helper ""
        git_as_role "$role" -C "$clone" config user.name "Hyperion $role"
        echo "Prepared $clone without credentials in its remote URL."
      done
    '';
  };
in
{
  users.groups = roleGroups;
  users.users = roleUsers;

  environment.systemPackages = [
    agentLabAuth
    hermesPackage
    mnemosyneHermes
    wikiBootstrap
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/agent-lab/agents 0711 root root - -"
  ]
  ++ map (role: "d ${roleHome role} 0700 agent-${role} agent-${role} - -") roles
  ++ map (role: "d ${hermesHome role} 0700 agent-${role} agent-${role} - -") roles
  ++ map (role: "d ${workspace role} 0700 agent-${role} agent-${role} - -") roles;

  systemd.services = lib.genAttrs (map (role: "agent-lab-${role}") roles) (
    serviceName: mkAgentService (lib.removePrefix "agent-lab-" serviceName)
  );
}
