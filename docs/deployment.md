# Deployment and secrets

[← Overview](../README.md)

## Deploying

Deployments are manual. Validate Dell and the deploy-rs schema from the repo root:

```sh
nix flake check --no-build
nix eval --raw .#nixosConfigurations.dell.config.system.build.toplevel.drvPath
```

Then deploy Dell:

```sh
nix run nixpkgs#deploy-rs -- .#dell
# Equivalent if deploy-rs is installed: deploy .#dell
```

Dell builds remotely and auto-rolls back if activation fails. The shared security
module allows the `axel` wheel user to activate deployments without a sudo password.

Note: flake eval only sees files known to git — `git add` new files
(including `.age` secrets) or they don't exist as far as nix is concerned.

## Secrets (agenix)

Recipients are defined in `hosts/dell/secrets/secrets.nix` (server host key +
laptop key). To create or edit a secret, enter `hosts/dell/secrets/`:

```sh
EDITOR=vim agenix -e <name>.age -i ~/.ssh/id_ed25519
```

After editing, **verify the content is non-empty** — a scripted/failed
editor session can silently encrypt an empty string, which passes eval and
only blows up at activation time:

```sh
agenix -d <name>.age -i ~/.ssh/id_ed25519 | wc -c
```

On the host, decrypted secrets appear under `/run/agenix/<name>`.
