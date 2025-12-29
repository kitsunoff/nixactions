{ pkgs, lib, sdk }:

let
  setupActions = import ./setup.nix { inherit pkgs lib; };
  npmActions = import ./npm.nix { inherit pkgs lib; };
in
setupActions // npmActions // {
  # Environment management
  nixShell = import ./nix-shell.nix { inherit pkgs lib; };
  
  # Load and validate JSON outputs from a file
  loadOutputs = import ./load-outputs.nix { inherit pkgs lib sdk; };
}
