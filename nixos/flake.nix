{
  description = "NixOS hosts: elm (desktop), sparrow (server)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  outputs = { self, nixpkgs, disko, noctalia, ... }: {
    nixosConfigurations = {
      elm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit noctalia; };
        modules = [ ./hosts/elm ];
      };
      sparrow = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ disko.nixosModules.disko ./hosts/sparrow ];
      };
    };
  };
}
