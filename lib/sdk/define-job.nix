# SDK defineJob - creates typed job definitions
#
# Usage:
#   buildJob = sdk.defineJob {
#     name = "build";
#     inputs = {
#       version = types.string;
#       config = types.withDefault types.string "release";
#     };
#     envOutputs = [ "buildId" "imageTag" ];  # Env vars to export
#     artifacts = { dist = "dist/"; };         # File artifacts
#     steps = ctx: [ ... ];
#   };
#
#   # In workflow:
#   jobs.build = buildJob { version = "1.0.0"; executor = ...; };
#   jobs.deploy = deployJob { 
#     buildId = sdk.jobOutput "build" "buildId";
#     executor = ...;
#   };
#
# envOutputs are transformed to artifacts by sdk.envOutputsExtension
{ lib }:

let
  types = import ./types.nix { inherit lib; };
  refs = import ./refs.nix { inherit lib; };
in
rec {
  # Main job definition function
  defineJob = {
    name,
    # Typed inputs - parameters this job accepts
    inputs ? {},
    # Env outputs - variable names exported for downstream jobs
    # Transformed to artifacts by envOutputsExtension
    envOutputs ? [],
    # Steps - list or function (ctx) -> list
    steps,
    # Artifact outputs: { name = "path"; }
    artifacts ? {},
    # Artifact inputs from other jobs
    artifactInputs ? [],
    # Job dependencies
    needs ? [],
    # Static environment variables
    env ? {},
    # Environment providers
    envFrom ? [],
    # Executor (optional - can be provided at instantiation)
    executor ? null,
    # Condition
    condition ? null,
    # Continue on error
    continueOnError ? false,
    # Retry config
    retry ? null,
    # Timeout
    timeout ? null,
    # Description
    description ? "",
  }:
  # Returns a function that takes input values and returns a job attrset
  inputValues:
  let
    # Resolve inputs with defaults
    resolvedInputs = lib.mapAttrs (inputName: inputType:
      if inputValues ? ${inputName} then
        inputValues.${inputName}
      else if types.hasDefault inputType then
        inputType.default
      else
        throw "Job '${name}': missing required input '${inputName}'"
    ) inputs;

    # Context for steps function
    ctx = {
      inputs = resolvedInputs;
      job = name;
    };

    # Resolve steps
    resolvedSteps = 
      if builtins.isFunction steps then
        steps ctx
      else
        steps;

    # Get executor
    resolvedExecutor = 
      if inputValues ? executor then inputValues.executor
      else if executor != null then executor
      else throw "Job '${name}': executor must be provided";

    # Merge needs
    resolvedNeeds = needs ++ (inputValues.needs or []);

    # Merge artifact inputs  
    resolvedArtifactInputs = artifactInputs ++ (inputValues.artifactInputs or []);

  in {
    # Standard job fields
    executor = resolvedExecutor;
    steps = resolvedSteps;
    outputs = artifacts;
    inputs = resolvedArtifactInputs;
    needs = resolvedNeeds;
    inherit env envFrom condition continueOnError retry timeout;

    # SDK metadata - used by extensions (validation, envOutputsExtension)
    __sdkJob = {
      inherit name inputs envOutputs artifacts description;
      inputValues = resolvedInputs;
    };
  };
}
