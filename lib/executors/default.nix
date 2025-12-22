{ pkgs, lib, mkExecutor }:

{
  local = import ./local.nix { inherit pkgs lib mkExecutor; };
  ssh = import ./ssh.nix { inherit pkgs lib mkExecutor; };
  oci = import ./oci.nix { inherit pkgs lib mkExecutor; };
  nixos-container = import ./nixos-container.nix { inherit pkgs lib mkExecutor; };
  k8s = import ./k8s.nix { inherit pkgs lib mkExecutor; };
  nomad = import ./nomad.nix { inherit pkgs lib mkExecutor; };
}
