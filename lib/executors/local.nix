{ pkgs, lib, mkExecutor }:

let
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
  localHelpers = import ./local-helpers.nix { inherit pkgs lib; };
in

mkExecutor {
  name = "local";
  
  # Setup local workspace in /tmp
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: ''
    source ${localHelpers}/bin/nixactions-local-executor
setup_local_workspace'';
  
  # Cleanup workspace (respects NIXACTIONS_KEEP_WORKSPACE)
  cleanupWorkspace = ''
    cleanup_local_workspace
  '';
  
  # Execute job locally in isolated directory
  executeJob = { jobName, actionDerivations, env }: ''
    setup_local_job "${jobName}"
${lib.concatStringsSep "\n" (
  lib.mapAttrsToList (k: v: ''
    if [ -z "''${${k}+x}" ]; then
      export ${k}=${lib.escapeShellArg (toString v)}
    fi'') env
)}
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
fi'';
  
  
  # Save artifact (executed on HOST after job completes)
  saveArtifact = { name, path, jobName }: ''
    save_local_artifact "${name}" "${path}" "${jobName}"
  '';
  
  # Restore artifact (executed on HOST before job starts)
  restoreArtifact = { name, path ? ".", jobName }: ''
    restore_local_artifact "${name}" "${path}" "${jobName}"
  '';
}
