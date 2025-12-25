{ pkgs, lib }:

{
  # File provider - load from .env files
  file = import ./file.nix { inherit pkgs lib; };
  
  # SOPS provider - decrypt SOPS encrypted files
  sops = import ./sops.nix { inherit pkgs lib; };
  
  # Required validator - check required variables are set
  required = import ./required.nix { inherit pkgs lib; };
  
  # Static provider - hardcoded environment variables
  static = import ./static.nix { inherit pkgs lib; };
}
