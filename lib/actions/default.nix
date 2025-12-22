{ pkgs, lib }:

let
  setupActions = import ./setup.nix { inherit pkgs lib; };
  npmActions = import ./npm.nix { inherit pkgs lib; };
in
setupActions // npmActions // {
  # Environment management
  nixShell = import ./nix-shell.nix { inherit pkgs lib; };
  
  # Secrets management
  sopsLoad = import ./sops.nix { inherit pkgs lib; };
  vaultLoad = import ./vault.nix { inherit pkgs lib; };
  opLoad = import ./1password.nix { inherit pkgs lib; };
  ageDecrypt = import ./age.nix { inherit pkgs lib; };
  bwLoad = import ./bitwarden.nix { inherit pkgs lib; };
  requireEnv = import ./require-env.nix { inherit pkgs lib; };
}
