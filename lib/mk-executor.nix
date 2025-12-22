{ pkgs, lib }:

{
  name,
  
  # Setup workspace for the entire workflow (lazy-init on first executeJob call)
  # Returns bash script that sets WORKSPACE_DIR env var
  # Note: Expects $WORKFLOW_ID to be set in environment
  setupWorkspace,  # :: String (bash script)
  
  # Cleanup workspace at end of workflow
  # Returns bash script
  cleanupWorkspace,  # :: String
  
  # Execute a job within the workspace
  # jobName: name of the job
  # script: bash script to execute
  # Returns wrapped bash script
  executeJob,  # :: { jobName :: String, script :: String } -> String
  
  # Optional: provision derivations to executor environment
  provision ? null,  # :: [Derivation] -> String
  
  # Optional: fetch artifacts from executor to control node
  # destination: path on control node where to copy artifacts
  # Returns bash script or null if not supported (e.g., local executor)
  fetchArtifacts ? null,  # :: { destination :: String } -> String | Null
  
  # Optional: push artifacts from control node to executor
  # source: path on control node where artifacts are stored
  # Returns bash script or null if not supported (e.g., local executor)
  pushArtifacts ? null,  # :: { artifacts :: [String], source :: String } -> String | Null
  
  # Save artifact within executor (called inside job)
  # name: artifact name
  # path: path to save (e.g., "dist/", "target/release/myapp")
  # Returns bash script that saves path to $NIXACTIONS_ARTIFACTS_DIR
  saveArtifact,  # :: { name :: String, path :: String } -> String
  
  # Restore artifact within executor (called inside job)
  # name: artifact name
  # Returns bash script that restores from $NIXACTIONS_ARTIFACTS_DIR to current dir
  restoreArtifact,  # :: { name :: String } -> String
}:

assert lib.assertMsg (name != "") "Executor name cannot be empty";
assert lib.assertMsg (builtins.isString setupWorkspace) "setupWorkspace must be a string (bash script)";
assert lib.assertMsg (builtins.isString cleanupWorkspace) "cleanupWorkspace must be a string (bash script)";
assert lib.assertMsg (builtins.isFunction executeJob) "executeJob must be a function ({ jobName, script } -> String)";
assert lib.assertMsg (provision == null || builtins.isFunction provision) "provision must be a function ([Derivation] -> String) or null";
assert lib.assertMsg (fetchArtifacts == null || builtins.isFunction fetchArtifacts) "fetchArtifacts must be a function ({ artifacts, destination } -> String) or null";
assert lib.assertMsg (pushArtifacts == null || builtins.isFunction pushArtifacts) "pushArtifacts must be a function ({ artifacts, source } -> String) or null";
assert lib.assertMsg (builtins.isFunction saveArtifact) "saveArtifact must be a function ({ name, path } -> String)";
assert lib.assertMsg (builtins.isFunction restoreArtifact) "restoreArtifact must be a function ({ name } -> String)";

{
  inherit name setupWorkspace cleanupWorkspace executeJob provision fetchArtifacts pushArtifacts saveArtifact restoreArtifact;
  canProvision = provision != null;
  canFetchArtifacts = fetchArtifacts != null;
  canPushArtifacts = pushArtifacts != null;
}
