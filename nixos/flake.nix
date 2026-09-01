{
  description = "NixOS hosts: elm (desktop), sparrow (server)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, noctalia, ... }@inputs: {
    nixosConfigurations = {
      elm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit noctalia inputs; };
        modules = [ ./hosts/elm ];
      };
      sparrow = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [ disko.nixosModules.disko ./hosts/sparrow ];
      };
    };
  };
}
