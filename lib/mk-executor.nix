{ pkgs, lib }:

{
  name,
  
  # Repository copying behavior
  # Default: true - copy $PWD to job directory before executing actions
  copyRepo ? true,
  
  # === WORKSPACE LEVEL (for entire workflow) ===
  
  # Setup workspace (called once at workflow start for each unique executor)
  # Receives all action derivations that will be used by this executor
  # Should be idempotent (may be called multiple times if same executor used multiple times)
  # Note: Expects $WORKFLOW_ID to be set in environment
  setupWorkspace,  # :: { actionDerivations :: [Derivation] } -> String
  
  # Cleanup workspace (called once at workflow end via trap EXIT)
  # Receives all action derivations that were used by this executor
  # Should cleanup all workspace-level resources
  cleanupWorkspace,  # :: { actionDerivations :: [Derivation] } -> String
  
  # === JOB LEVEL (for each job) ===
  
  # Setup job environment (called before executeJob for each job)
  # Receives action derivations for this specific job
  # Should create job-specific resources (directories, containers, pods, etc.)
  setupJob,  # :: { jobName :: String, actionDerivations :: [Derivation] } -> String
  
  # Execute a job within the workspace
  # Receives action derivations and composes them for execution
  executeJob,  # :: { jobName :: String, actionDerivations :: [Derivation], env :: AttrSet } -> String
  
  # Cleanup job resources (called after executeJob for each job)
  # Should cleanup job-specific resources (containers, pods, etc.)
  # Workspace-level resources should NOT be cleaned here (use cleanupWorkspace)
  cleanupJob,  # :: { jobName :: String } -> String
  
  # === ARTIFACTS ===
  
  # Save artifact from job directory to HOST artifacts storage
  # Called AFTER executeJob completes (executed on HOST)
  saveArtifact,  # :: { name :: String, path :: String, jobName :: String } -> String
  
  # Restore artifact from HOST storage to job directory
  # Called BEFORE executeJob starts (executed on HOST)
  restoreArtifact,  # :: { name :: String, path :: String, jobName :: String } -> String
  
  # === OPTIONAL (deprecated, may be removed) ===
  provision ? null,
  fetchArtifacts ? null,
  pushArtifacts ? null,
}:

assert lib.assertMsg (name != "") "Executor name cannot be empty";
assert lib.assertMsg (builtins.isFunction setupWorkspace) "setupWorkspace must be a function ({ actionDerivations } -> String)";
assert lib.assertMsg (builtins.isFunction cleanupWorkspace) "cleanupWorkspace must be a function ({ actionDerivations } -> String)";
assert lib.assertMsg (builtins.isFunction setupJob) "setupJob must be a function ({ jobName, actionDerivations } -> String)";
assert lib.assertMsg (builtins.isFunction executeJob) "executeJob must be a function ({ jobName, actionDerivations, env } -> String)";
assert lib.assertMsg (builtins.isFunction cleanupJob) "cleanupJob must be a function ({ jobName } -> String)";
assert lib.assertMsg (builtins.isFunction saveArtifact) "saveArtifact must be a function ({ name, path, jobName } -> String)";
assert lib.assertMsg (builtins.isFunction restoreArtifact) "restoreArtifact must be a function ({ name, path, jobName } -> String)";

{
  inherit name copyRepo setupWorkspace cleanupWorkspace setupJob executeJob cleanupJob saveArtifact restoreArtifact;
  
  # Deprecated/optional
  inherit provision fetchArtifacts pushArtifacts;
  canProvision = provision != null;
  canFetchArtifacts = fetchArtifacts != null;
  canPushArtifacts = pushArtifacts != null;
}
