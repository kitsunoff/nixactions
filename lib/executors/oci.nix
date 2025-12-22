{ pkgs, lib, mkExecutor }:

{
  image ? "nixos/nix",
}:

mkExecutor {
  name = "oci-${lib.strings.sanitizeDerivationName image}";
  
  # Setup container workspace
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = ''
    # Lazy init - only create if not exists
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      # Create and start long-running container without volume mounts
      CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}=$(${pkgs.docker}/bin/docker create \
        -v /nix/store:/nix/store:ro \
        ${image} \
        sleep infinity)
      
      ${pkgs.docker}/bin/docker start "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}"
      
      export CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}
      
      # Create workspace directory in container
      ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" mkdir -p /workspace
      
      echo "→ OCI workspace: container $CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:/workspace"
    fi
  '';
  
  # Cleanup container
  cleanupWorkspace = ''
    if [ -n "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo ""
      echo "→ Stopping and removing OCI container: $CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}"
      ${pkgs.docker}/bin/docker stop "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" >/dev/null 2>&1 || true
      ${pkgs.docker}/bin/docker rm "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" >/dev/null 2>&1 || true
    fi
  '';
  
  # Execute job in container
  executeJob = { jobName, script }: ''
    # Ensure workspace is initialized
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "Error: OCI workspace not initialized for ${image}"
      exit 1
    fi
    
    ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" bash -c ${lib.escapeShellArg ''
      set -euo pipefail
      
      # Create job directory
      JOB_DIR="/workspace/jobs/${jobName}"
      mkdir -p "$JOB_DIR"
      cd "$JOB_DIR"
      
      echo "╔════════════════════════════════════════╗"
      echo "║ JOB: ${jobName}"
      echo "║ EXECUTOR: oci-${lib.strings.sanitizeDerivationName image}"
      echo "║ WORKDIR: $JOB_DIR"
      echo "╚════════════════════════════════════════╝"
      
      # Execute job script
      ${script}
    ''}
  '';
  
  provision = null;
  fetchArtifacts = null;
  pushArtifacts = null;
  
  # Save artifact (executed on HOST after job completes)
  # Uses docker cp to copy from container to host
  saveArtifact = { name, path, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "  ✗ Container not initialized"
      return 1
    fi
    
    JOB_DIR="/workspace/jobs/${jobName}"
    
    # Check if path exists in container
    if ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" test -e "$JOB_DIR/${path}"; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      # Copy from container to host
      ${pkgs.docker}/bin/docker cp \
        "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:$JOB_DIR/${path}" \
        "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      echo "  ✗ Path not found: ${path}"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  # Uses docker cp to copy from host to container
  restoreArtifact = { name, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "  ✗ Container not initialized"
      return 1
    fi
    
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      JOB_DIR="/workspace/jobs/${jobName}"
      
      # Ensure job directory exists in container
      ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" mkdir -p "$JOB_DIR"
      
      # Copy each file/directory from artifact to container
      for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
        if [ -e "$item" ]; then
          ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:$JOB_DIR/"
        fi
      done
    else
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
