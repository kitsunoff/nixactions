{ pkgs, lib, mkExecutor, linuxPkgs ? pkgs }:

{
  local = import ./local.nix { inherit pkgs lib mkExecutor; };
  oci = import ./oci.nix { inherit pkgs lib mkExecutor linuxPkgs; };
}
