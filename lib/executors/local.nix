{ pkgs, lib, mkExecutor }:

mkExecutor {
  name = "local";
  
  # Setup local workspace in /tmp
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: ''
    # Lazy init - only create if not exists
    if [ -z "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      export WORKSPACE_DIR_LOCAL
      _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
    fi
  '';
  
  # Cleanup workspace (respects NIXACTIONS_KEEP_WORKSPACE)
  cleanupWorkspace = ''
    if [ -n "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
        rm -rf "$WORKSPACE_DIR_LOCAL"
      else
        _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace preserved"
      fi
    fi
  '';
  
  # Execute job locally in isolated directory
  executeJob = { jobName, actionDerivations, env }: ''
    # Create isolated directory for this job
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    # Create job-specific env file INSIDE workspace
    JOB_ENV="$JOB_DIR/.job-env"
    touch "$JOB_ENV"
    export JOB_ENV
    
    _log_job "${jobName}" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"
    
    
    # Set job-level environment
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: 
        "export ${k}=${lib.escapeShellArg (toString v)}"
      ) env
    )}
    
    # Track action failures
    ACTION_FAILED=false
    
    # Execute action derivations as separate processes
    ${lib.concatMapStringsSep "\n\n" (action: 
      let
        actionName = action.passthru.name or (builtins.baseNameOf action);
        actionCondition = 
          if action.passthru.condition != null 
          then action.passthru.condition 
          else "success()";
      in ''
        # === ${actionName} ===
        
        # Check action condition
        _should_run=true
        ACTION_CONDITION="${actionCondition}"
        case "$ACTION_CONDITION" in
          'always()')
            # Always run
            ;;
          'success()')
            # Run only if no previous action failed
            if [ "$ACTION_FAILED" = "true" ]; then
              _should_run=false
            fi
            ;;
          'failure()')
            # Run only if a previous action failed
            if [ "$ACTION_FAILED" = "false" ]; then
              _should_run=false
            fi
            ;;
          'cancelled()')
            # Would need workflow-level cancellation support
            _should_run=false
            ;;
          *)
            # Bash script condition - evaluate it
            if ! ($ACTION_CONDITION); then
              _should_run=false
            fi
            ;;
        esac
        
        if [ "$_should_run" = "false" ]; then
          echo "⊘ Skipping ${actionName} (condition: $ACTION_CONDITION)"
        else
          _log job "${jobName}" action "${actionName}" event "→" "Starting"
          
          # Record start time
          _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
          
          # Source JOB_ENV and export all variables before running action
          set -a
          [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
          set +a
          
          # Execute action as separate process with output wrapping
          set +e
          if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
            # Simple format - pass through unchanged
            ${action}/bin/${lib.escapeShellArg actionName}
            _action_exit_code=$?
          else
            # Structured/JSON format - wrap each line
            ${action}/bin/${lib.escapeShellArg actionName} 2>&1 | _log_line "${jobName}" "${actionName}"
            _action_exit_code=''${PIPESTATUS[0]}
          fi
          set -e
          
          # Calculate duration
          if [ "$_action_start_ns" != "0" ]; then
            _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
            _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
            _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | ${pkgs.bc}/bin/bc 2>/dev/null || echo "0")
          else
            _action_duration_s="0"
          fi
          
          # Log result and track failure for subsequent actions
          if [ $_action_exit_code -ne 0 ]; then
            ACTION_FAILED=true
            _log job "${jobName}" action "${actionName}" duration "''${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
            # Don't exit immediately - let conditions handle flow
          else
            _log job "${jobName}" action "${actionName}" duration "''${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
          fi
        fi
      ''
    ) actionDerivations}
    
    # Fail job if any action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _log_job "${jobName}" event "✗" "Job failed due to action failures"
      exit 1
    fi
  '';
  
  
  # Save artifact (executed on HOST after job completes)
  saveArtifact = { name, path, jobName }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    if [ -e "$JOB_DIR/${path}" ]; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Save preserving original path structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      cp -r "$JOB_DIR/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      _log_workflow artifact "${name}" path "${path}" event "✗" "Path not found"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  restoreArtifact = { name, jobName }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      # Restore to job directory (will be created by executeJob)
      mkdir -p "$JOB_DIR"
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}"/* "$JOB_DIR/" 2>/dev/null || true
    else
      _log_workflow artifact "${name}" event "✗" "Artifact not found"
      return 1
    fi
  '';
}
