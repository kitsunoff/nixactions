{ pkgs, lib ? pkgs.lib }:

let
  # Core constructors
  mkExecutor = import ./mk-executor.nix { inherit pkgs lib; };
  mkWorkflow = import ./mk-workflow.nix { inherit pkgs lib; };
  mkMatrixJobs = import ./mk-matrix-jobs.nix { inherit pkgs lib; };
  
  # Built-in executors
  executors = import ./executors/default.nix { inherit pkgs lib mkExecutor; };
  
  # Standard actions
  actions = import ./actions/default.nix { inherit pkgs lib; };
  
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
  
  # Export logging utilities
  inherit logging;
  
  # Export retry utilities
  inherit retry;
}
