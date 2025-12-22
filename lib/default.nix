{ pkgs, lib ? pkgs.lib }:

let
  # Core constructors
  mkExecutor = import ./mk-executor.nix { inherit pkgs lib; };
  mkWorkflow = import ./mk-workflow.nix { inherit pkgs lib; };
  
  # Built-in executors
  executors = import ./executors/default.nix { inherit pkgs lib mkExecutor; };
  
  # Standard actions
  actions = import ./actions/default.nix { inherit pkgs lib; };
  
in {
  # Export core constructors
  inherit mkExecutor mkWorkflow;
  
  # Export built-in executors
  inherit executors;
  
  # Export standard actions
  inherit actions;
}
