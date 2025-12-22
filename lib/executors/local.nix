{ pkgs, lib, mkExecutor }:

mkExecutor {
  name = "local";
  
  # Setup local workspace in /tmp
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = ''
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
  executeJob = { jobName, script }: ''
    # Create isolated directory for this job
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    echo "╔════════════════════════════════════════╗"
    echo "║ JOB: ${jobName}"
    echo "║ EXECUTOR: local"
    echo "║ WORKDIR: $JOB_DIR"
    echo "╚════════════════════════════════════════╝"
    
    # Execute the job script
    ${script}
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
