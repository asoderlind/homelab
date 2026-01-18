{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      home-manager,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            ./modules/core
          ];
        };
      };
      deploy.nodes.nixos = {
        hostname = "10.0.0.6";
        sshUser = "axel";
        sshOpts = [
          "-i"
          "~/.ssh/homelab/dell"
        ];
        remoteBuild = true;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nixos;
        };
      };
    };
}
