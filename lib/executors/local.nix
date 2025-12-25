{ pkgs, lib, mkExecutor }:

let
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
  localHelpers = import ./local-helpers.nix { inherit pkgs lib; };
  makeConfigurable = import ../make-configurable.nix { inherit lib; };
in

makeConfigurable {
  # Default configuration
  defaultConfig = {
    copyRepo = true;
    name = null;
  };
  
  # Function that creates executor from config
  make = { copyRepo ? true, name ? null }: 
    let
      executorName = if name != null then name else "local";
    in
    mkExecutor {
      inherit copyRepo;
      name = executorName;
    
    # === WORKSPACE LEVEL ===
    
    # Setup local workspace in /tmp (called once at workflow start)
    setupWorkspace = { actionDerivations }: ''
      source ${localHelpers}/bin/nixactions-local-executor
      setup_local_workspace
    '';
    
    # Cleanup workspace (called once at workflow end)
    cleanupWorkspace = { actionDerivations }: ''
      source ${localHelpers}/bin/nixactions-local-executor
      cleanup_local_workspace
    '';
    
    # === JOB LEVEL ===
    
    # Setup job directory (called before executeJob)
    setupJob = { jobName, actionDerivations }: ''
      source ${localHelpers}/bin/nixactions-local-executor
      export NIXACTIONS_COPY_REPO=${if copyRepo then "true" else "false"}
      setup_local_job "${jobName}"
    '';
    
    # Execute job locally in isolated directory
    executeJob = { jobName, actionDerivations, env }: ''
      # Set job-level environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''
          if [ -z "''${${k}+x}" ]; then
            export ${k}=${lib.escapeShellArg (toString v)}
          fi'') env
      )}
      
      # Execute actions
      ACTION_FAILED=false
      ${lib.concatMapStringsSep "\n" (action: 
        let
          actionName = action.passthru.name or (builtins.baseNameOf action);
        in
          actionRunner.generateActionExecution {
            inherit action jobName;
            actionBinary = "${action}/bin/${lib.escapeShellArg actionName}";
          }
      ) actionDerivations}
      
      if [ "$ACTION_FAILED" = "true" ]; then
        _log_job "${jobName}" event "✗" "Job failed due to action failures"
        exit 1
      fi
    '';
    
    # Cleanup job resources (called after executeJob)
    cleanupJob = { jobName }: ''
      # Nothing to cleanup for local executor at job level
      # Job directory cleanup happens in cleanupWorkspace
    '';
    
    # === ARTIFACTS ===
    
    # Save artifact (executed on HOST after job completes)
    saveArtifact = { name, path, jobName }: ''
      save_local_artifact "${name}" "${path}" "${jobName}"
    '';
    
    # Restore artifact (executed on HOST before job starts)
    restoreArtifact = { name, path ? ".", jobName }: ''
      restore_local_artifact "${name}" "${path}" "${jobName}"
    '';
  };
}
