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
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      agenix,
      ...
    }:
    let
      system = "x86_64-linux";
      mkHost =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
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
        dell = mkHost [
          ./hosts/dell
          agenix.nixosModules.default
        ];
        hyperion = mkHost [
          ./hosts/hyperion
        ];
      };

      deploy.nodes = {
        dell = (mkDeployNode "nixos-homelab-dell.tail193da7.ts.net" self.nixosConfigurations.dell) // {
          sshOpts = [
            "-i"
            "~/.ssh/homelab/dell"
          ];
        };

        hyperion = (mkDeployNode "hyperion" self.nixosConfigurations.hyperion) // {
          sshOpts = [
            "-i"
            "~/.ssh/homelab/hyperion"
          ];
        };
      };

      # The deployment targets are x86_64-linux. Publishing deploy checks for
      # Darwin makes deploy-rs try to build Linux activation derivations on the
      # invoking Mac before remoteBuild gets a chance to use the target host.
      checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
    };
}
