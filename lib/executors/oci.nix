{ pkgs, lib, mkExecutor }:

{
  image ? "nixos/nix",
  mode ? "mount",  # "mount" | "build"
}:

assert lib.assertMsg (mode == "mount" || mode == "build") 
  "OCI executor mode must be 'mount' or 'build', got: ${mode}";

let
  # Sanitize image name for bash variable names (replace - / : with _)
  safeName = builtins.replaceStrings ["-" "/" ":"] ["_" "_" "_"] image;
in

mkExecutor {
  name = "oci-${safeName}-${mode}";
  
  # Setup container workspace
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: 
    if mode == "mount" then ''
      # Mode: MOUNT - mount /nix/store from host
      # Lazy init - only create if not exists
      if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
        # Create and start long-running container with /nix/store mounted
        CONTAINER_ID_OCI_${safeName}_${mode}=$(${pkgs.docker}/bin/docker create \
          -v /nix/store:/nix/store:ro \
          ${image} \
          sleep infinity)
        
        ${pkgs.docker}/bin/docker start "$CONTAINER_ID_OCI_${safeName}_${mode}"
        
        export CONTAINER_ID_OCI_${safeName}_${mode}
        
        # Create workspace directory in container
        ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" mkdir -p /workspace
        
        _log_workflow executor "oci-${safeName}-mount" container "$CONTAINER_ID_OCI_${safeName}_${mode}" workspace "/workspace" event "→" "Workspace created"
      fi
    ''
    else # mode == "build"
      let
        # Build custom image with all action derivations included
        actionPaths = map (drv: drv) actionDerivations;
        
        customImage = pkgs.dockerTools.buildLayeredImage {
          name = "nixactions-${safeName}";
          tag = "latest";
          
          contents = pkgs.buildEnv {
            name = "nixactions-root";
            paths = [ 
              pkgs.bash 
              pkgs.coreutils 
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnused
            ] ++ actionPaths;
          };
          
          config = {
            Cmd = [ "sleep" "infinity" ];
            WorkingDir = "/workspace";
          };
        };
      in ''
        # Mode: BUILD - build custom image with actions
        # Lazy init - only create if not exists
        if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
          # Load custom image
          echo "→ Loading custom OCI image with actions (this may take a while)..."
          ${pkgs.docker}/bin/docker load < ${customImage}
          
          # Create and start container from custom image
          CONTAINER_ID_OCI_${safeName}_${mode}=$(${pkgs.docker}/bin/docker create \
            nixactions-${safeName}:latest)
          
          ${pkgs.docker}/bin/docker start "$CONTAINER_ID_OCI_${safeName}_${mode}"
          
          export CONTAINER_ID_OCI_${safeName}_${mode}
          
          # Create workspace directory in container
          ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" mkdir -p /workspace
          
          _log_workflow executor "oci-${safeName}-build" container "$CONTAINER_ID_OCI_${safeName}_${mode}" workspace "/workspace" event "→" "Workspace created"
          echo "  Image includes: bash, coreutils, and all action derivations"
        fi
      '';
  
  # Cleanup container
  cleanupWorkspace = ''
    if [ -n "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow executor "oci-${safeName}-${mode}" container "$CONTAINER_ID_OCI_${safeName}_${mode}" event "→" "Stopping and removing container"
      ${pkgs.docker}/bin/docker stop "$CONTAINER_ID_OCI_${safeName}_${mode}" >/dev/null 2>&1 || true
      ${pkgs.docker}/bin/docker rm "$CONTAINER_ID_OCI_${safeName}_${mode}" >/dev/null 2>&1 || true
    fi
  '';
  
  # Execute job in container
  executeJob = { jobName, actionDerivations, env }: ''
    # Ensure workspace is initialized
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow executor "oci-${safeName}-${mode}" event "✗" "Workspace not initialized"
      exit 1
    fi
    
    ${pkgs.docker}/bin/docker exec \
      ${lib.concatMapStringsSep " " (k: "-e ${k}") (lib.attrNames env)} \
      "$CONTAINER_ID_OCI_${safeName}_${mode}" \
      bash -c ${lib.escapeShellArg ''
        set -uo pipefail
        
        # Create job directory
        JOB_DIR="/workspace/jobs/${jobName}"
        mkdir -p "$JOB_DIR"
        cd "$JOB_DIR"
        
        # Create job-specific env file INSIDE container workspace
        JOB_ENV="$JOB_DIR/.job-env"
        touch "$JOB_ENV"
        export JOB_ENV
        
        _log_job "${jobName}" executor "oci-${safeName}-${mode}" workdir "$JOB_DIR" event "▶" "Job starting"
        
        
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
              
              # Record start time (use fallback if nanoseconds not available)
              _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
              
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
              _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
              if echo "$_action_start_ns" | grep -q "N"; then
                # Fallback: seconds only
                _action_duration_s=$((_action_end_ns - _action_start_ns))
                _action_duration_ms=$((_action_duration_s * 1000))
              else
                # Nanoseconds available
                _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
                _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
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
      ''}
  '';
  
  
  # Save artifact (executed on HOST after job completes)
  # Uses docker cp to copy from container to host
  saveArtifact = { name, path, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow event "✗" "Container not initialized"
      return 1
    fi
    
    JOB_DIR="/workspace/jobs/${jobName}"
    
    # Check if path exists in container
    if ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" test -e "$JOB_DIR/${path}"; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      # Copy from container to host
      ${pkgs.docker}/bin/docker cp \
        "$CONTAINER_ID_OCI_${safeName}_${mode}:$JOB_DIR/${path}" \
        "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      _log_workflow artifact "${name}" path "${path}" event "✗" "Path not found"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  # Uses docker cp to copy from host to container
  restoreArtifact = { name, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow event "✗" "Container not initialized"
      return 1
    fi
    
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      JOB_DIR="/workspace/jobs/${jobName}"
      
      # Ensure job directory exists in container
      ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" mkdir -p "$JOB_DIR"
      
      # Copy each file/directory from artifact to container
      for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
        if [ -e "$item" ]; then
          ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${safeName}_${mode}:$JOB_DIR/"
        fi
      done
    else
      _log_workflow artifact "${name}" event "✗" "Artifact not found"
      return 1
    fi
  '';
}
