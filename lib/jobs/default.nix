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
  # Container build pipelines
  buildahBuildPush = import ./buildah-build-push.nix { inherit pkgs lib actions; };
  
  # TODO: Add more job templates here
  # Example:
  # nodeCI = import ./node-ci.nix { inherit pkgs lib actions; };
  # pythonCI = import ./python-ci.nix { inherit pkgs lib actions; };
}
