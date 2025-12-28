{ pkgs, lib ? pkgs.lib }:

let
  # Determine Linux pkgs for OCI image building
  # On Linux: use same pkgs
  # On Darwin: use x86_64-linux or aarch64-linux pkgs
  linuxPkgs = 
    if pkgs.stdenv.isLinux then pkgs
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      # aarch64-darwin -> aarch64-linux
      import pkgs.path { system = "aarch64-linux"; }
    else
      # x86_64-darwin -> x86_64-linux
      import pkgs.path { system = "x86_64-linux"; };
  
  # Core constructors
  mkExecutor = import ./mk-executor.nix { inherit pkgs lib; };
  mkWorkflow = import ./mk-workflow.nix { inherit pkgs lib; };
  mkMatrixJobs = import ./mk-matrix-jobs.nix { inherit pkgs lib; };
  
  # Built-in executors
  executors = import ./executors/default.nix { inherit pkgs lib mkExecutor linuxPkgs; };
  
  # Standard actions
  actions = import ./actions/default.nix { inherit pkgs lib; };
  
  # Job templates
  jobs = import ./jobs/default.nix { inherit pkgs lib actions; };
  
  # Environment providers
  envProviders = import ./env-providers/default.nix { inherit pkgs lib; };
  
  # Logging utilities
  logging = import ./logging.nix { inherit pkgs lib; };
  
  # Retry utilities
  retry = import ./retry.nix { inherit lib pkgs; };
  
in {
  # Export core constructors
  inherit mkExecutor mkWorkflow mkMatrixJobs;
  
  # Export built-in executors
  inherit executors;
  
  # Export standard actions
  inherit actions;
  
  # Export job templates
  inherit jobs;
  
  # Export environment providers
  inherit envProviders;
  
  # Export logging utilities
  inherit logging;
  
  # Export retry utilities
  inherit retry;
  
  # Export linuxPkgs for OCI executor extraPackages
  # Use: platform.linuxPkgs.git instead of pkgs.git
  inherit linuxPkgs;
}
