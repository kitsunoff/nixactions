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
    WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
    export WORKSPACE_DIR_LOCAL
    
    # Lazy init - only create if not exists (use lock file)
    if [ ! -f "$WORKSPACE_DIR_LOCAL/.initialized" ]; then
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
      
      # Mark as initialized
      touch "$WORKSPACE_DIR_LOCAL/.initialized"
    fi
  }
  
  # Setup job directory within local workspace
  # Usage: setup_local_job "job_name"
  # Expects: $WORKSPACE_DIR_LOCAL
  # Expects: $NIXACTIONS_COPY_REPO (optional, default: true)
  # Exports: $JOB_DIR, $JOB_ENV
  setup_local_job() {
    local job_name=$1
    
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
    mkdir -p "$JOB_DIR"
    
    # Copy repository to job directory for isolation
    # Each job gets its own fresh copy
    if [ "''${NIXACTIONS_COPY_REPO:-true}" = "true" ]; then
      _log_job "$job_name" event "→" "Copying repository to job directory"
      
      # Use rsync if available, otherwise cp
      if command -v rsync &> /dev/null; then
        rsync -a \
          --exclude='.git' \
          --exclude='result' \
          --exclude='result-*' \
          --exclude='.direnv' \
          --exclude='target' \
          --exclude='node_modules' \
          "$PWD/" "$JOB_DIR/"
      else
        # Fallback to cp with filters
        (
          cd "$PWD"
          find . -maxdepth 1 ! -name . ! -name '.git' ! -name 'result*' ! -name '.direnv' \
            -exec cp -r {} "$JOB_DIR/" \;
        )
      fi
      
      _log_job "$job_name" event "✓" "Repository copied"
    fi
    
    cd "$JOB_DIR"
    
    # Create job-specific env file INSIDE workspace
    JOB_ENV="$JOB_DIR/.job-env"
    touch "$JOB_ENV"
    export JOB_DIR JOB_ENV
    
    _log_job "$job_name" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"
  }
  
  # Cleanup local workspace
  # Usage: cleanup_local_workspace
  # Expects: $WORKFLOW_ID (required), $NIXACTIONS_KEEP_WORKSPACE (optional)
  # Note: Can use $WORKSPACE_DIR_LOCAL if already set, otherwise derives from $WORKFLOW_ID
  cleanup_local_workspace() {
    # Determine workspace directory
    local workspace_dir="''${WORKSPACE_DIR_LOCAL:-/tmp/nixactions/$WORKFLOW_ID}"
    
    if [ -d "$workspace_dir" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo "→ Cleaning up local workspace: $workspace_dir" >&2
        rm -rf "$workspace_dir"
      else
        _log_workflow executor "local" workspace "$workspace_dir" event "→" "Workspace preserved"
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
  # Usage: restore_local_artifact "artifact_name" "target_path" "job_name"
  # Args:
  #   - artifact_name: Name of the artifact to restore
  #   - target_path: Where to restore in job dir (e.g., "." for root, "lib/" for subdir)
  #   - job_name: Name of the job
  # Expects: $WORKSPACE_DIR_LOCAL, $NIXACTIONS_ARTIFACTS_DIR
  restore_local_artifact() {
    local name=$1
    local target_path=$2
    local job_name=$3
    
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/$name" ]; then
      mkdir -p "$JOB_DIR"
      
      # Determine target directory
      if [ "$target_path" = "." ] || [ "$target_path" = "./" ]; then
        # Restore to root of job directory (default behavior)
        # Use shopt dotglob to include hidden files (like .env-*)
        (shopt -s dotglob && cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$JOB_DIR/" 2>/dev/null) || true
      else
        # Restore to custom path
        TARGET_DIR="$JOB_DIR/$target_path"
        mkdir -p "$TARGET_DIR"
        (shopt -s dotglob && cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$TARGET_DIR/" 2>/dev/null) || true
      fi
      
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
