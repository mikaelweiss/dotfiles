# The node on PATH for every machine. A host pins another major with node.package.
{ config, lib, pkgs, ... }:

{
  options.node.package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.nodejs_24;
  };

  config.environment.systemPackages = [ config.node.package ];
}
