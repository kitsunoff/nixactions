{ pkgs, lib, actions }:

# Jobs Library
#
# Reusable job templates for common workflows.
#
# Usage:
#   jobs = nixactions.jobs;
#   
#   jobs.myJob = (jobs.nodeCI { 
#     nodeVersion = "20"; 
#   }) // { 
#     executor = executors.local; 
#   };

{
  # TODO: Add job templates here
  # Example:
  # nodeCI = import ./node-ci.nix { inherit pkgs lib actions; };
  # pythonCI = import ./python-ci.nix { inherit pkgs lib actions; };
  # dockerPipeline = import ./docker-pipeline.nix { inherit pkgs lib actions; };
}
