{
  description = "NixOS homelab configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pin Buzz's production Compose bundle and CLI together.
    buzz = {
      url = "github:block/buzz/248b9d1b7666aacbcb1485b76e81de30a271ba0e";
      flake = false;
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.8.13";
      # The Mnemosyne plugin must use the exact same Python interpreter as
      # Hermes for Nix's Python-module discovery and ABI checks.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mnemosyne = {
      url = "github:mnemosyne-oss/mnemosyne/v3.15.1";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      agenix,
      buzz,
      hermes-agent,
      mnemosyne,
      ...
    }:
    let
      system = "x86_64-linux";
      mkHost =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            buzzSrc = buzz;
            hermesAgent = hermes-agent;
            mnemosyneSrc = mnemosyne;
          };
        };
      mkDeployNode = hostname: configuration: {
        inherit hostname;
        sshUser = "axel";
        remoteBuild = true;
        confirmTimeout = 300;
        activationTimeout = 600;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos configuration;
        };
      };
    in
    {
      nixosConfigurations = {
        app-vm-1 = mkHost [
          ./hosts/app-vm-1/configuration.nix
          agenix.nixosModules.default
        ];
        dell = mkHost [
          ./hosts/dell
          agenix.nixosModules.default
        ];
      };

      deploy.nodes = {
        app-vm-1 = (mkDeployNode "192.168.1.217" self.nixosConfigurations.app-vm-1) // {
          sshUser = "root";
          activationTimeout = 3600;
          confirmTimeout = 600;
        };
        dell = (mkDeployNode "nixos-homelab-dell.tail193da7.ts.net" self.nixosConfigurations.dell) // {
          sshOpts = [
            "-i"
            "~/.ssh/homelab/dell"
          ];
        };
      };

      # The deployment targets are x86_64-linux. Publishing deploy checks for
      # Darwin makes deploy-rs try to build Linux activation derivations on the
      # invoking Mac before remoteBuild gets a chance to use the target host.
      checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
