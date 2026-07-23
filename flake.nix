{
  description = "NixOS configuration";

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
      home-manager,
      agenix,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            ./modules/core
            agenix.nixosModules.default
          ];
        };
      };
      deploy.nodes.nixos = {
        hostname = "nixos-homelab-dell.tail193da7.ts.net";
        sshUser = "axel";
        sshOpts = [
          "-i"
          "~/.ssh/homelab/dell"
        ];
        remoteBuild = true;
        confirmTimeout = 300;
        activationTimeout = 600;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nixos;
        };
      };
    };
}
