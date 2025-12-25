{ pkgs, lib }:

# OCI executor helpers - bash functions compiled into derivation
# Reduces codegen by providing reusable OCI container management

pkgs.writeScriptBin "nixactions-oci-executor" ''
  #!${pkgs.bash}/bin/bash
  
  # ============================================================
  # OCI Executor Helpers
  # ============================================================
  
  # Setup OCI workspace (container)
  # Usage: setup_oci_workspace IMAGE EXECUTOR_NAME
  # Expects: $WORKFLOW_ID, $DOCKER (path to docker binary)
  # Exports: $CONTAINER_ID_OCI_<normalized_name>, $WORKSPACE_DIR_OCI_<normalized_name>
  setup_oci_workspace() {
    local image=$1
    local executor_name=$2
    local var_name="CONTAINER_ID_OCI_''${executor_name}"
    
    # Lazy init - only create if not exists
    if [ -z "''${!var_name:-}" ]; then
      echo "→ Creating OCI container from image: $image"
      
      # Create container with /nix/store mounted read-only
      local container_id=$("$DOCKER" create -v /nix/store:/nix/store:ro "$image" sleep infinity)
      "$DOCKER" start "$container_id"
      
      # Export container ID
      export "$var_name=$container_id"
      
      # Create workspace inside container
      "$DOCKER" exec "$container_id" mkdir -p /workspace
      
      local workspace_var="WORKSPACE_DIR_OCI_''${executor_name}"
      export "$workspace_var=/workspace"
      
      echo "→ OCI workspace: container $container_id:/workspace"
    fi
  }
  
  # Setup job directory within OCI container
  # Usage: setup_oci_job JOB_NAME EXECUTOR_NAME
  # Expects: $CONTAINER_ID_OCI_<normalized_name>, $DOCKER
  # Exports: $JOB_DIR, $JOB_ENV
  setup_oci_job() {
    local job_name=$1
    local executor_name=$2
    local var_name="CONTAINER_ID_OCI_''${executor_name}"
    local container_id="''${!var_name}"
    
    if [ -z "$container_id" ]; then
      echo "✗ Container not initialized for executor: $executor_name"
      return 1
    fi
    
    JOB_DIR="/workspace/jobs/$job_name"
    
    # Create job directory inside container
    "$DOCKER" exec "$container_id" mkdir -p "$JOB_DIR"
    
    # Create job-specific env file INSIDE container workspace
    JOB_ENV="$JOB_DIR/.job-env"
    "$DOCKER" exec "$container_id" touch "$JOB_ENV"
    
    export JOB_DIR JOB_ENV
    
    _log_job "$job_name" executor "oci-$executor_name" workdir "$JOB_DIR" event "▶" "Job starting"
  }
  
  # Cleanup OCI workspace (stop and remove container)
  # Usage: cleanup_oci_workspace EXECUTOR_NAME
  # Expects: $CONTAINER_ID_OCI_<normalized_name>, $DOCKER, $NIXACTIONS_KEEP_WORKSPACE
  cleanup_oci_workspace() {
    local executor_name=$1
    local var_name="CONTAINER_ID_OCI_''${executor_name}"
    local container_id="''${!var_name}"
    
    if [ -n "$container_id" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo "→ Cleaning up OCI container: $container_id"
        "$DOCKER" stop "$container_id" >/dev/null 2>&1 || true
        "$DOCKER" rm "$container_id" >/dev/null 2>&1 || true
      else
        _log_workflow executor "oci-$executor_name" container "$container_id" event "→" "Container preserved"
      fi
    fi
  }
  
  # Save artifact from OCI container to HOST artifacts storage
  # Usage: save_oci_artifact ARTIFACT_NAME RELATIVE_PATH JOB_NAME EXECUTOR_NAME
  # Expects: $CONTAINER_ID_OCI_<normalized_name>, $NIXACTIONS_ARTIFACTS_DIR, $DOCKER
  save_oci_artifact() {
    local name=$1
    local path=$2
    local job_name=$3
    local executor_name=$4
    local var_name="CONTAINER_ID_OCI_''${executor_name}"
    local container_id="''${!var_name}"
    
    if [ -z "$container_id" ]; then
      _log_workflow event "✗" "Container not initialized"
      return 1
    fi
    
    local job_dir="/workspace/jobs/$job_name"
    
    # Check if path exists in container
    if "$DOCKER" exec "$container_id" test -e "$job_dir/$path"; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/$name"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/$name"
      
      # Preserve directory structure
      local parent_dir=$(dirname "$path")
      if [ "$parent_dir" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/$name/$parent_dir"
      fi
      
      # Copy from container to host
      "$DOCKER" cp \
        "$container_id:$job_dir/$path" \
        "$NIXACTIONS_ARTIFACTS_DIR/$name/$path"
      return 0
    else
      _log_workflow artifact "$name" path "$path" event "✗" "Path not found"
      return 1
    fi
  }
  
  # Restore artifact from HOST storage to OCI container
  # Usage: restore_oci_artifact ARTIFACT_NAME JOB_NAME EXECUTOR_NAME
  # Expects: $CONTAINER_ID_OCI_<normalized_name>, $NIXACTIONS_ARTIFACTS_DIR, $DOCKER
  restore_oci_artifact() {
    local name=$1
    local job_name=$2
    local executor_name=$3
    local var_name="CONTAINER_ID_OCI_''${executor_name}"
    local container_id="''${!var_name}"
    
    if [ -z "$container_id" ]; then
      _log_workflow event "✗" "Container not initialized"
      return 1
    fi
    
    local job_dir="/workspace/jobs/$job_name"
    
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/$name" ]; then
      # Create job directory in container
      "$DOCKER" exec "$container_id" mkdir -p "$job_dir"
      
      # Copy each file/directory from artifact to container
      for item in "$NIXACTIONS_ARTIFACTS_DIR/$name"/*; do
        if [ -e "$item" ]; then
          "$DOCKER" cp "$item" "$container_id:$job_dir/"
        fi
      done
      return 0
    else
      _log_workflow artifact "$name" event "✗" "Artifact not found"
      return 1
    fi
  }
  
  # ============================================================
  # Export functions
  # ============================================================
  
  export -f setup_oci_workspace
  export -f setup_oci_job
  export -f cleanup_oci_workspace
  export -f save_oci_artifact
  export -f restore_oci_artifact
''
