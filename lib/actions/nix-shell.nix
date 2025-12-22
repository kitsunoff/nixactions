{ pkgs, lib }:

packages:
# Creates a nix-shell environment with the specified packages
# 
# Usage:
#   nixShell [ "curl" "jq" "git" ]
#
# This adds the packages to PATH for subsequent actions in the same job.
# Note: Unlike other actions, this modifies the environment for the entire job.

let
  packageList = lib.concatStringsSep " " packages;
  
  # Build attribute paths for nix-build (e.g., "pkgs.curl" "pkgs.jq")
  attrPaths = map (pkg: "pkgs.${pkg}") packages;
  buildEnvExpr = ''
    with import <nixpkgs> {};
    buildEnv {
      name = "nixshell-env";
      paths = [ ${lib.concatStringsSep " " attrPaths} ];
    }
  '';
in
{
  name = "nix-shell";
  bash = ''
    echo "→ Setting up nix-shell with packages: ${packageList}"
    
    # Build the environment with all packages
    ENV_PATH=$(nix-build --no-out-link -E '${buildEnvExpr}' 2>&1)
    
    if [ $? -eq 0 ]; then
      # Add to PATH for this job
      export PATH="$ENV_PATH/bin:$PATH"
      echo "  ✓ Packages available in PATH"
    else
      echo "  ✗ Failed to build environment"
      echo "$ENV_PATH"
      exit 1
    fi
  '';
}
