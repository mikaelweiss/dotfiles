{
  description = "Every machine: Macs via nix-darwin, elm, sparrow, oak and pika via NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-stable";
    # Unregistered MakeMKV builds expire, so this input gets bumped on its own.
    nixpkgs-makemkv.url = "github:NixOS/nixpkgs/master";
    # Pika's Pi-hole module, which 26.05 ships broken.
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    # Pi 5 kernel and firmware. Its own nixpkgs pin matches its binary cache, so nothing follows ours.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    # Snapshot matches the builds the Rex Mac app ships.
    rex.url = "https://pkgs.superlogical.com/rex/nix/snapshot.tar.gz";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-stable, nix-darwin, disko, nixos-raspberrypi, ... }:
  let
    mac = modules: nix-darwin.lib.darwinSystem {
      specialArgs = { inherit self inputs; };
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
      pika = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./shared.nix ./nixos/common.nix ./nixos/hosts/pika ];
      };
    };

    images.pika = self.nixosConfigurations.pika.config.system.build.sdImage;
  };
}
