{
  description = "Every machine: Macs via nix-darwin, elm and sparrow via NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-stable";
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-stable, nix-darwin, disko, noctalia, ... }:
  let
    mac = modules: nix-darwin.lib.darwinSystem {
      specialArgs = { inherit self; };
      modules = [ ./shared.nix ./darwin/common.nix ] ++ modules;
    };
    linux = modules: nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs noctalia; };
      modules = [ ./shared.nix ./nixos/common.nix ] ++ modules;
    };
  in
  {
    darwinConfigurations = {
      "Mikaels-MacBook-Air" = mac [ ./darwin/personal.nix ./darwin/hosts/macbook-air.nix ];
      "wolf" = mac [ ./darwin/personal.nix ./darwin/hosts/wolf.nix ];
      "Mikaels-MacBook-Pro" = mac [ ./darwin/hosts/macbook-pro.nix ];
    };

    nixosConfigurations = {
      elm = linux [ ./nixos/hosts/elm ];
      sparrow = linux [ disko.nixosModules.disko ./nixos/hosts/sparrow ];
    };
  };
}
