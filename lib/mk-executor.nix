{ pkgs, lib }:

{
  name,
  
  # Setup workspace for job (lazy-init pattern)
  # Receives action derivations for this specific job
  # Returns bash script that creates execution environment if not exists
  # Note: Expects $WORKFLOW_ID to be set in environment
  setupWorkspace,  # :: { actionDerivations :: [Derivation] } -> String (bash script)
  
  # Cleanup workspace at end of workflow
  # Returns bash script
  cleanupWorkspace,  # :: String
  
  # Execute a job within the workspace
  # Receives action derivations and composes them for execution
  # jobName: name of the job
  # actionDerivations: list of action derivations to execute
  # env: job-level environment variables
  # Returns wrapped bash script
  executeJob,  # :: { jobName :: String, actionDerivations :: [Derivation], env :: AttrSet } -> String
  
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
  
  # Save artifact from job directory to HOST artifacts storage
  # Called AFTER executeJob completes (executed on HOST)
  # name: artifact name
  # path: relative path in job directory
  # jobName: job that created it
  # Returns bash script that saves path to $NIXACTIONS_ARTIFACTS_DIR
  saveArtifact,  # :: { name :: String, path :: String, jobName :: String } -> String
  
  # Restore artifact from HOST storage to job directory
  # Called BEFORE executeJob starts (executed on HOST)
  # name: artifact name
  # jobName: job to restore into
  # Returns bash script that restores from $NIXACTIONS_ARTIFACTS_DIR
  restoreArtifact,  # :: { name :: String, jobName :: String } -> String
}:

assert lib.assertMsg (name != "") "Executor name cannot be empty";
assert lib.assertMsg (builtins.isFunction setupWorkspace) "setupWorkspace must be a function ({ actionDerivations } -> String)";
assert lib.assertMsg (builtins.isString cleanupWorkspace) "cleanupWorkspace must be a string (bash script)";
assert lib.assertMsg (builtins.isFunction executeJob) "executeJob must be a function ({ jobName, actionDerivations, env } -> String)";
assert lib.assertMsg (provision == null || builtins.isFunction provision) "provision must be a function ([Derivation] -> String) or null";
assert lib.assertMsg (fetchArtifacts == null || builtins.isFunction fetchArtifacts) "fetchArtifacts must be a function ({ artifacts, destination } -> String) or null";
assert lib.assertMsg (pushArtifacts == null || builtins.isFunction pushArtifacts) "pushArtifacts must be a function ({ artifacts, source } -> String) or null";
assert lib.assertMsg (builtins.isFunction saveArtifact) "saveArtifact must be a function ({ name, path, jobName } -> String)";
assert lib.assertMsg (builtins.isFunction restoreArtifact) "restoreArtifact must be a function ({ name, jobName } -> String)";

{
  inherit name setupWorkspace cleanupWorkspace executeJob provision fetchArtifacts pushArtifacts saveArtifact restoreArtifact;
  canProvision = provision != null;
  canFetchArtifacts = fetchArtifacts != null;
  canPushArtifacts = pushArtifacts != null;
}
