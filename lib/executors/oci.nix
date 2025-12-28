{ pkgs, lib, mkExecutor, linuxPkgs ? pkgs }:

let
  # Import helpers (for host-side operations)
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
  makeConfigurable = import ../make-configurable.nix { inherit lib; };
  
  # Import shared image builder
  imageBuilder = import ./oci-image-builder.nix { inherit pkgs lib linuxPkgs; };
  inherit (imageBuilder) toLinuxPkg mkUniqueActionName buildLinuxActions buildExecutorImage;
  inherit (imageBuilder) loggingLib retryLib runtimeHelpers timeoutLib lpkgs;
in

makeConfigurable {
  # Default configuration
  defaultConfig = {
    copyRepo = true;
    name = null;
    mode = "shared";  # "shared" or "isolated"
    extraPackages = [];
    extraMounts = [];
    containerEnv = {};
  };
  
  # Function that creates executor from config
  make = { 
    copyRepo ? true, 
    name ? null,
    mode ? "shared",
    extraPackages ? [],
    extraMounts ? [],
    containerEnv ? {},
  }: 
    let
      executorName = if name != null then name else "oci";
      
      # Sanitize executor name for bash variable names
      sanitizedExecutorName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] executorName;
      
      # Generate docker run extra mount arguments
      extraMountArgs = lib.concatMapStringsSep " " (mount: 
        "-v ${lib.escapeShellArg mount}"
      ) extraMounts;
      
    in
    mkExecutor {
      inherit copyRepo;
      name = executorName;
      
      # === WORKSPACE LEVEL ===
      
      # Setup workspace: build image, create workspace dir, start container (shared mode)
      setupWorkspace = { actionDerivations }: 
        let
          image = buildExecutorImage { 
            inherit actionDerivations executorName extraPackages containerEnv;
          };
        in
        if mode == "shared" then ''
          # Create workspace directory on host
          WORKSPACE_DIR_${sanitizedExecutorName}="/tmp/nixactions/$WORKFLOW_ID/${executorName}"
          mkdir -p "$WORKSPACE_DIR_${sanitizedExecutorName}"
          export WORKSPACE_DIR_${sanitizedExecutorName}
          
          _log_workflow executor "${executorName}" mode "shared" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" event "→" "Setting up OCI workspace"
          
          # Load OCI image (pre-built at nix build time)
          _log_workflow executor "${executorName}" event "→" "Loading OCI image"
          ${pkgs.gzip}/bin/zcat ${image.imageTarball} | ${pkgs.docker}/bin/docker load >&2
          
          # Start container with workspace mount
          CONTAINER_ID_${sanitizedExecutorName}=$(${pkgs.docker}/bin/docker run -d \
            -v "$WORKSPACE_DIR_${sanitizedExecutorName}:/workspace" \
            ${extraMountArgs} \
            -e WORKFLOW_NAME \
            -e WORKFLOW_ID \
            -e NIXACTIONS_LOG_FORMAT \
            ${image.imageName}:${image.imageTag})
          
          export CONTAINER_ID_${sanitizedExecutorName}
          
          _log_workflow executor "${executorName}" container "$CONTAINER_ID_${sanitizedExecutorName}" event "✓" "Container started"
        '' else ''
          # Isolated mode: just create workspace directory, containers created per-job
          WORKSPACE_DIR_${sanitizedExecutorName}="/tmp/nixactions/$WORKFLOW_ID/${executorName}"
          mkdir -p "$WORKSPACE_DIR_${sanitizedExecutorName}"
          export WORKSPACE_DIR_${sanitizedExecutorName}
          
          _log_workflow executor "${executorName}" mode "isolated" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" event "→" "Workspace created (containers per-job)"
        '';
      
      # Cleanup workspace: stop container (shared mode), cleanup dirs
      cleanupWorkspace = { actionDerivations }: 
        if mode == "shared" then ''
          # Stop and remove shared container
          if [ -n "''${CONTAINER_ID_${sanitizedExecutorName}:-}" ]; then
            if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
              _log_workflow executor "${executorName}" container "$CONTAINER_ID_${sanitizedExecutorName}" event "→" "Stopping container"
              ${pkgs.docker}/bin/docker stop "$CONTAINER_ID_${sanitizedExecutorName}" >/dev/null 2>&1 || true
              ${pkgs.docker}/bin/docker rm "$CONTAINER_ID_${sanitizedExecutorName}" >/dev/null 2>&1 || true
            else
              _log_workflow executor "${executorName}" container "$CONTAINER_ID_${sanitizedExecutorName}" event "→" "Container preserved"
            fi
          fi
          
          # Cleanup workspace directory
          if [ -n "''${WORKSPACE_DIR_${sanitizedExecutorName}:-}" ] && [ -d "$WORKSPACE_DIR_${sanitizedExecutorName}" ]; then
            if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
              rm -rf "$WORKSPACE_DIR_${sanitizedExecutorName}"
            fi
          fi
        '' else ''
          # Isolated mode: just cleanup workspace directory
          # (containers are cleaned up in cleanupJob)
          if [ -n "''${WORKSPACE_DIR_${sanitizedExecutorName}:-}" ] && [ -d "$WORKSPACE_DIR_${sanitizedExecutorName}" ]; then
            if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
              _log_workflow executor "${executorName}" workspace "$WORKSPACE_DIR_${sanitizedExecutorName}" event "→" "Cleaning up workspace"
              rm -rf "$WORKSPACE_DIR_${sanitizedExecutorName}"
            fi
          fi
        '';
      
      # === JOB LEVEL ===
      
      # Setup job: create job dir, copy repo, start container (isolated mode)
      setupJob = { jobName, actionDerivations }: 
        let
          # Sanitize job name for bash variable names
          sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
          
          # In isolated mode, build image for this specific job
          jobImage = buildExecutorImage { 
            inherit actionDerivations extraPackages containerEnv;
            executorName = executorName;
          };
        in
        if mode == "shared" then ''
          # Create job directory inside container
          ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_${sanitizedExecutorName}" mkdir -p "/workspace/jobs/${jobName}"
          
          # Copy repository to job directory (if enabled)
          if [ "''${NIXACTIONS_COPY_REPO:-${if copyRepo then "true" else "false"}}" = "true" ]; then
            _log_job "${jobName}" event "→" "Copying repository to container"
            
            # Create temp dir on host and copy repo there
            JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
            mkdir -p "$JOB_DIR_HOST"
            
            # Use rsync if available
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
              (
                cd "$PWD"
                find . -maxdepth 1 ! -name . ! -name '.git' ! -name 'result*' ! -name '.direnv' \
                  -exec cp -r {} "$JOB_DIR_HOST/" \;
              )
            fi
            
            _log_job "${jobName}" event "✓" "Repository copied"
          fi
          
          _log_job "${jobName}" executor "${executorName}" workdir "/workspace/jobs/${jobName}" event "▶" "Job starting"
        '' else ''
          # Isolated mode: create job dir and start container for this job
          JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
          mkdir -p "$JOB_DIR_HOST"
          
          # Copy repository (if enabled)
          if [ "''${NIXACTIONS_COPY_REPO:-${if copyRepo then "true" else "false"}}" = "true" ]; then
            _log_job "${jobName}" event "→" "Copying repository to job directory"
            
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
              (
                cd "$PWD"
                find . -maxdepth 1 ! -name . ! -name '.git' ! -name 'result*' ! -name '.direnv' \
                  -exec cp -r {} "$JOB_DIR_HOST/" \;
              )
            fi
            
            _log_job "${jobName}" event "✓" "Repository copied"
          fi
          
          # Load and start container for this job (pre-built at nix build time)
          _log_job "${jobName}" executor "${executorName}" event "→" "Loading job image"
          ${pkgs.gzip}/bin/zcat ${jobImage.imageTarball} | ${pkgs.docker}/bin/docker load >&2
          
          JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}=$(${pkgs.docker}/bin/docker run -d \
            -v "$JOB_DIR_HOST:/workspace" \
            ${extraMountArgs} \
            -e WORKFLOW_NAME \
            -e WORKFLOW_ID \
            -e NIXACTIONS_LOG_FORMAT \
            ${jobImage.imageName}:${jobImage.imageTag})
          
          export JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}
          
          _log_job "${jobName}" executor "${executorName}" container "$JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}" workdir "/workspace" event "▶" "Job starting in container"
        '';
      
      # Execute job actions inside container
      executeJob = { jobName, actionDerivations, env }:
        let
          sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
          
          # Container ID variable depends on mode
          containerVar = if mode == "shared" 
            then "$CONTAINER_ID_${sanitizedExecutorName}"
            else "$JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}";
          
          # Working directory inside container
          workdir = if mode == "shared" 
            then "/workspace/jobs/${jobName}"
            else "/workspace";
          
          # Rebuild actions for Linux
          linuxActionDerivations = buildLinuxActions actionDerivations;
        in ''
          ${pkgs.docker}/bin/docker exec \
            ${containerVar} \
            bash -c ${lib.escapeShellArg ''
              set -uo pipefail
              cd ${workdir}
              
              # Source helpers (using explicit paths from image)
              source ${loggingLib.loggingHelpers}/bin/nixactions-logging
              source ${retryLib.retryHelpers}/bin/nixactions-retry
              source ${runtimeHelpers}/bin/nixactions-runtime
              
              JOB_ENV="${workdir}/.job-env"
              touch "$JOB_ENV"
              export JOB_ENV
              
              # Set job-level environment variables
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (k: v: 
                  "export ${k}=${lib.escapeShellArg (toString v)}"
                ) env
              )}
              
              ACTION_FAILED=false
              ${lib.concatMapStringsSep "\n" (action: 
                let
                  # Use originalName for logs, but unique name for binary path
                  originalName = action.passthru.originalName or action.passthru.name or "action";
                  # Get the actual derivation name (with hash suffix)
                  drvName = action.name or (builtins.baseNameOf action);
                in
                  actionRunner.generateActionExecution {
                    # Override action name for logging
                    action = action // { passthru = action.passthru // { name = originalName; }; };
                    inherit jobName;
                    actionBinary = "${action}/bin/${lib.escapeShellArg drvName}";
                    timingCommand = "date +%s%N 2>/dev/null || date +%s";
                  }
              ) linuxActionDerivations}
              
              if [ "$ACTION_FAILED" = "true" ]; then
                _log_job "${jobName}" event "✗" "Job failed due to action failures"
                exit 1
              fi
            ''}
        '';
      
      # Cleanup job: nothing for shared mode, stop container for isolated
      cleanupJob = { jobName }:
        let
          sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
        in
        if mode == "shared" then ''
          # Shared mode: container stays running until cleanupWorkspace
          true
        '' else ''
          # Isolated mode: stop and remove job container
          if [ -n "''${JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}:-}" ]; then
            _log_job "${jobName}" executor "${executorName}" container "$JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}" event "→" "Stopping container"
            ${pkgs.docker}/bin/docker stop "$JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}" >/dev/null 2>&1 || true
            ${pkgs.docker}/bin/docker rm "$JOB_CONTAINER_${sanitizedExecutorName}_${sanitizedJobName}" >/dev/null 2>&1 || true
          fi
        '';
      
      # === ARTIFACTS ===
      
      # Save artifact: copy from container workspace to host artifacts dir
      saveArtifact = { name, path, jobName }:
        let
          workdir = if mode == "shared" 
            then "/workspace/jobs/${jobName}"
            else "/workspace";
        in ''
          JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
          
          if [ -e "$JOB_DIR_HOST/${path}" ]; then
            rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
            mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
            
            # Preserve directory structure
            PARENT_DIR=$(dirname "${path}")
            if [ "$PARENT_DIR" != "." ]; then
              mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
            fi
            
            # Copy from host workspace to artifacts
            cp -r "$JOB_DIR_HOST/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
          else
            _log_workflow artifact "${name}" path "${path}" event "✗" "Path not found in $JOB_DIR_HOST"
            return 1
          fi
        '';
      
      # Restore artifact: copy from host artifacts to container workspace
      restoreArtifact = { name, path ? ".", jobName }: ''
        if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
          JOB_DIR_HOST="$WORKSPACE_DIR_${sanitizedExecutorName}/jobs/${jobName}"
          
          # Determine target directory
          if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
            # Restore to root of job directory
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
    };
}
