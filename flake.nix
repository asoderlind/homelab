{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
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
        hostname = "100.114.177.112";
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
