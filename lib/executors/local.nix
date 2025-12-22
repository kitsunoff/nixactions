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
      echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
    fi
  '';
  
  # Cleanup workspace (respects NIXACTIONS_KEEP_WORKSPACE)
  cleanupWorkspace = ''
    if [ -n "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo ""
        echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
        rm -rf "$WORKSPACE_DIR_LOCAL"
      else
        echo ""
        echo "→ Local workspace preserved: $WORKSPACE_DIR_LOCAL"
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
    
    echo "╔════════════════════════════════════════╗"
    echo "║ JOB: ${jobName}"
    echo "║ EXECUTOR: local"
    echo "║ WORKDIR: $JOB_DIR"
    echo "╚════════════════════════════════════════╝"
    
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
          echo "→ ${actionName}"
          
          # Source JOB_ENV and export all variables before running action
          set -a
          [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
          set +a
          
          # Execute action as separate process
          ${action}/bin/${lib.escapeShellArg actionName}
          _action_exit_code=$?
          
          # Track failure for subsequent actions
          if [ $_action_exit_code -ne 0 ]; then
            ACTION_FAILED=true
            echo "✗ Action ${actionName} failed (exit code: $_action_exit_code)"
            # Don't exit immediately - let conditions handle flow
          fi
        fi
      ''
    ) actionDerivations}
    
    # Fail job if any action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      echo ""
      echo "✗ Job failed due to action failures"
      exit 1
    fi
  '';
  
  provision = null;
  
  # Local executor doesn't need to fetch - artifacts already on control node
  fetchArtifacts = null;
  pushArtifacts = null;
  
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
      echo "  ✗ Path not found: ${path}"
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
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
