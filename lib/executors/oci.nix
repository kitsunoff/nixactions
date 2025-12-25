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
  
  # Import helpers
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
  ociHelpers = import ./oci-helpers.nix { inherit pkgs lib; };
  
  # Import runtime helpers for build mode
  loggingLib = import ../logging.nix { inherit pkgs lib; };
  retryLib = import ../retry.nix { inherit lib pkgs; };
  runtimeHelpers = import ../runtime-helpers.nix { inherit pkgs lib; };
in

mkExecutor {
  name = "oci-${safeName}-${mode}";
  
  # Setup container workspace
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: 
    if mode == "mount" then ''
      # Mode: MOUNT - mount /nix/store from host
      source ${ociHelpers}/bin/nixactions-oci-executor
      export DOCKER=${pkgs.docker}/bin/docker
      setup_oci_workspace "${image}" "${safeName}_${mode}"
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
              loggingLib.loggingHelpers
              retryLib.retryHelpers
              runtimeHelpers
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
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow executor "oci-${safeName}-${mode}" event "✗" "Workspace not initialized"
      exit 1
    fi
    ${pkgs.docker}/bin/docker exec \
      -e WORKFLOW_NAME \
      -e NIXACTIONS_LOG_FORMAT \
      "$CONTAINER_ID_OCI_${safeName}_${mode}" \
      bash -c ${lib.escapeShellArg ''
        set -uo pipefail
        source /nix/store/*-nixactions-logging/bin/nixactions-logging
        source /nix/store/*-nixactions-retry/bin/nixactions-retry
        source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
        JOB_DIR="/workspace/jobs/${jobName}"
        mkdir -p "$JOB_DIR"
        cd "$JOB_DIR"
        JOB_ENV="$JOB_DIR/.job-env"
        touch "$JOB_ENV"
        export JOB_ENV
        _log_job "${jobName}" executor "oci-${safeName}-${mode}" workdir "$JOB_DIR" event "▶" "Job starting"
        
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
  restoreArtifact = { name, path ? ".", jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      _log_workflow event "✗" "Container not initialized"
      return 1
    fi
    
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      JOB_DIR="/workspace/jobs/${jobName}"
      
      # Determine target directory
      if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
        # Restore to root of job directory (default behavior)
        ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" mkdir -p "$JOB_DIR"
        
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${safeName}_${mode}:$JOB_DIR/"
          fi
        done
      else
        # Restore to custom path
        TARGET_DIR="$JOB_DIR/${path}"
        ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${safeName}_${mode}" mkdir -p "$TARGET_DIR"
        
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${safeName}_${mode}:$TARGET_DIR/"
          fi
        done
      fi
    else
      _log_workflow artifact "${name}" event "✗" "Artifact not found"
      return 1
    fi
  '';
}
