# Node and pnpm for every machine, taken from one package set.
{ config, lib, pkgs, ... }:

{
  options.node.pkgs = lib.mkOption {
    type = lib.types.raw;
    default = pkgs;
  };

  config.environment.systemPackages = [ config.node.pkgs.nodejs_24 config.node.pkgs.pnpm ];
}
