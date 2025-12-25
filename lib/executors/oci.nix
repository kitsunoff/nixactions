{ pkgs, lib, mkExecutor }:

{
  image ? "nixos/nix",
  copyRepo ? true,  # Copy repository to job directory (like LOCAL executor)
  name ? null,      # Optional custom name (defaults to "oci-${sanitized-image}")
}:

let
  # Sanitize image name for bash variable names (replace - / : with _)
  safeName = builtins.replaceStrings ["-" "/" ":"] ["_" "_" "_"] image;
  
  # Use custom name if provided, otherwise auto-generate from image
  executorName = if name != null then name else "oci-${safeName}";
  
  # Sanitize executor name for bash variable names
  # (custom names might have dashes/special chars)
  sanitizedExecutorName = builtins.replaceStrings ["-" "/" ":"] ["_" "_" "_"] executorName;
  
  # Import helpers
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
in

mkExecutor {
  inherit copyRepo;
  name = executorName;
  
  # === WORKSPACE LEVEL ===
  
  # Setup workspace directory on host (called once at workflow start)
  setupWorkspace = { actionDerivations }: ''
    # Create workspace directory on host for all jobs
    WORKSPACE_DIR_${sanitizedExecutorName}="/tmp/nixactions/$WORKFLOW_ID/${executorName}"
    mkdir -p "$WORKSPACE_DIR_${sanitizedExecutorName}"
    export WORKSPACE_DIR_${sanitizedExecutorName}
    
    _log_workflow executor "${executorName}" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" action_count "${toString (builtins.length actionDerivations)}" event "→" "Workspace created (${toString (builtins.length actionDerivations)} actions)"
  '';
  
  # Cleanup workspace directory on host (called once at workflow end)
  cleanupWorkspace = { actionDerivations }: ''
    if [ -n "''${WORKSPACE_DIR_${sanitizedExecutorName}:-}" ] && [ -d "$WORKSPACE_DIR_${sanitizedExecutorName}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_workflow executor "${executorName}" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" event "→" "Cleaning up workspace"
        rm -rf "$WORKSPACE_DIR_${sanitizedExecutorName}"
      else
        _log_workflow executor "${executorName}" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" event "→" "Workspace preserved"
      fi
    fi
  '';
  
  # === JOB LEVEL ===
  
  # Setup job: create directory, copy repo, start container
  setupJob = { jobName, actionDerivations }: ''
    # 1. Create job directory on host
    JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
    mkdir -p "$JOB_DIR_HOST"
    
    # 2. Copy repository to job directory (if copyRepo enabled)
    if [ "''${NIXACTIONS_COPY_REPO:-${if copyRepo then "true" else "false"}}" = "true" ]; then
      _log_job "${jobName}" event "→" "Copying repository to job directory"
      
      # Use rsync if available, otherwise cp
      if command -v rsync &> /dev/null; then
        rsync -a \
          --exclude='.git' \
          --exclude='result' \
          --exclude='result-*' \
          --exclude='.direnv' \
          --exclude='target' \
          --exclude='node_modules' \
          "$PWD/" "$JOB_DIR_HOST/"
      else
        # Fallback to cp with filters
        (
          cd "$PWD"
          find . -maxdepth 1 ! -name . ! -name '.git' ! -name 'result*' ! -name '.direnv' \
            -exec cp -r {} "$JOB_DIR_HOST/" \;
        )
      fi
      
      _log_job "${jobName}" event "✓" "Repository copied"
    fi
    
    # 3. Start container for this job with mount
    JOB_CONTAINER_${sanitizedExecutorName}_${jobName}=$(${pkgs.docker}/bin/docker run -d \
      -v "$JOB_DIR_HOST:/workspace" \
      -v /nix/store:/nix/store:ro \
      -e WORKFLOW_NAME \
      -e NIXACTIONS_LOG_FORMAT \
      ${image} sleep infinity)
    
    export JOB_CONTAINER_${sanitizedExecutorName}_${jobName}
    
    _log_job "${jobName}" executor "${executorName}" container "$JOB_CONTAINER_${sanitizedExecutorName}_${jobName}" event "→" "Container started"
  '';
  
  # Execute actions in container
  executeJob = { jobName, actionDerivations, env }: ''
    ${pkgs.docker}/bin/docker exec \
      "$JOB_CONTAINER_${sanitizedExecutorName}_${jobName}" \
      bash -c ${lib.escapeShellArg ''
        set -uo pipefail
        cd /workspace
        
        # Source helpers
        source /nix/store/*-nixactions-logging/bin/nixactions-logging
        source /nix/store/*-nixactions-retry/bin/nixactions-retry
        source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
        
        JOB_ENV="/workspace/.job-env"
        touch "$JOB_ENV"
        export JOB_ENV
        
        _log_job "${jobName}" executor "${executorName}" workdir "/workspace" event "▶" "Job starting in container"
        
        # Set job-level environment variables
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: 
            "export ${k}=${lib.escapeShellArg (toString v)}"
          ) env
        )}
        
        ACTION_FAILED=false
        ${lib.concatMapStringsSep "\n" (action: 
          let
            actionName = action.passthru.name or (builtins.baseNameOf action);
          in
            actionRunner.generateActionExecution {
              inherit action jobName;
              actionBinary = "${action}/bin/${lib.escapeShellArg actionName}";
              timingCommand = "date +%s%N 2>/dev/null || date +%s";
            }
        ) actionDerivations}
        
        if [ "$ACTION_FAILED" = "true" ]; then
          _log_job "${jobName}" event "✗" "Job failed due to action failures"
          exit 1
        fi
      ''}
  '';
  
  # Cleanup job: stop and remove container
  cleanupJob = { jobName }: ''
    _log_job "${jobName}" executor "${executorName}" container "$JOB_CONTAINER_${sanitizedExecutorName}_${jobName}" event "→" "Stopping container"
    ${pkgs.docker}/bin/docker stop "$JOB_CONTAINER_${sanitizedExecutorName}_${jobName}" >/dev/null 2>&1 || true
    ${pkgs.docker}/bin/docker rm "$JOB_CONTAINER_${sanitizedExecutorName}_${jobName}" >/dev/null 2>&1 || true
  '';
  
  # === ARTIFACTS ===
  
  
  # Save artifact (executed on HOST after job completes)
  # Artifacts are already on host in $WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}/
  saveArtifact = { name, path, jobName }: ''
    JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
    
    if [ -e "$JOB_DIR_HOST/${path}" ]; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      # Copy from job directory to artifacts
      cp -r "$JOB_DIR_HOST/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      _log_workflow artifact "${name}" path "${path}" event "✗" "Path not found in $JOB_DIR_HOST"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  # Copy from artifacts to job directory on host (will be visible in container via mount)
  restoreArtifact = { name, path ? ".", jobName }: ''
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
      
      # Determine target directory
      if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
        # Restore to root of job directory (default behavior)
        mkdir -p "$JOB_DIR_HOST"
        
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            cp -r "$item" "$JOB_DIR_HOST/"
          fi
        done
      else
        # Restore to custom path
        TARGET_DIR="$JOB_DIR_HOST/${path}"
        mkdir -p "$TARGET_DIR"
        
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            cp -r "$item" "$TARGET_DIR/"
          fi
        done
      fi
    else
      _log_workflow artifact "${name}" event "✗" "Artifact not found"
      return 1
    fi
  '';
}
