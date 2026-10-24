{
  description = "Every machine: Macs via nix-darwin, elm, sparrow and oak via NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-stable";
    # Unregistered MakeMKV builds expire, so this input gets bumped on its own.
    nixpkgs-makemkv.url = "github:NixOS/nixpkgs/master";
    # Tailscale security fixes land in master days before any channel.
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/master";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-stable, nix-darwin, disko, ... }:
  let
    mac = modules: nix-darwin.lib.darwinSystem {
      specialArgs = { inherit self; };
      modules = [ ./shared.nix ./darwin/common.nix ] ++ modules;
    };
    linux = modules: nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
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
      oak = linux [ disko.nixosModules.disko ./nixos/hosts/oak ];
    };
  };
}
