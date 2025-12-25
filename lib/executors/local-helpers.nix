{ pkgs, lib }:

# Local executor helpers - bash functions compiled into derivation
# Reduces codegen by providing reusable workspace management

pkgs.writeScriptBin "nixactions-local-executor" ''
  #!${pkgs.bash}/bin/bash
  
  # ============================================================
  # Local Executor Helpers
  # ============================================================
  
  # Setup local workspace in /tmp
  # Usage: setup_local_workspace
  # Expects: $WORKFLOW_ID
  setup_local_workspace() {
    # Lazy init - only create if not exists
    if [ -z "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      export WORKSPACE_DIR_LOCAL
      _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
    fi
  }
  
  # Setup job directory within local workspace
  # Usage: setup_local_job "job_name"
  # Expects: $WORKSPACE_DIR_LOCAL
  # Exports: $JOB_DIR, $JOB_ENV
  setup_local_job() {
    local job_name=$1
    
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    # Create job-specific env file INSIDE workspace
    JOB_ENV="$JOB_DIR/.job-env"
    touch "$JOB_ENV"
    export JOB_DIR JOB_ENV
    
    _log_job "$job_name" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"
  }
  
  # Cleanup local workspace
  # Usage: cleanup_local_workspace
  # Expects: $WORKSPACE_DIR_LOCAL, $NIXACTIONS_KEEP_WORKSPACE
  cleanup_local_workspace() {
    if [ -n "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
        rm -rf "$WORKSPACE_DIR_LOCAL"
      else
        _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace preserved"
      fi
    fi
  }
  
  # Save artifact from job directory to HOST artifacts storage
  # Usage: save_local_artifact "artifact_name" "relative/path" "job_name"
  # Expects: $WORKSPACE_DIR_LOCAL, $NIXACTIONS_ARTIFACTS_DIR
  save_local_artifact() {
    local name=$1
    local path=$2
    local job_name=$3
    
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
    if [ -e "$JOB_DIR/$path" ]; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/$name"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/$name"
      
      # Save preserving original path structure
      PARENT_DIR=$(dirname "$path")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/$name/$PARENT_DIR"
      fi
      
      cp -r "$JOB_DIR/$path" "$NIXACTIONS_ARTIFACTS_DIR/$name/$path"
      return 0
    else
      _log_workflow artifact "$name" path "$path" event "✗" "Path not found"
      return 1
    fi
  }
  
  # Restore artifact from HOST storage to job directory
  # Usage: restore_local_artifact "artifact_name" "job_name"
  # Expects: $WORKSPACE_DIR_LOCAL, $NIXACTIONS_ARTIFACTS_DIR
  restore_local_artifact() {
    local name=$1
    local job_name=$2
    
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/$name" ]; then
      # Restore to job directory (will be created by executeJob)
      mkdir -p "$JOB_DIR"
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$JOB_DIR/" 2>/dev/null || true
      return 0
    else
      _log_workflow artifact "$name" event "✗" "Artifact not found"
      return 1
    fi
  }
  
  # ============================================================
  # Export functions
  # ============================================================
  
  export -f setup_local_workspace
  export -f setup_local_job
  export -f cleanup_local_workspace
  export -f save_local_artifact
  export -f restore_local_artifact
''
