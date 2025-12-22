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
        
        echo "→ OCI workspace (mount): container $CONTAINER_ID_OCI_${safeName}_${mode}:/workspace"
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
          
          echo "→ OCI workspace (build): container $CONTAINER_ID_OCI_${safeName}_${mode}:/workspace"
          echo "  Image includes: bash, coreutils, and all action derivations"
        fi
      '';
  
  # Cleanup container
  cleanupWorkspace = ''
    if [ -n "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      echo ""
      echo "→ Stopping and removing OCI container: $CONTAINER_ID_OCI_${safeName}_${mode}"
      ${pkgs.docker}/bin/docker stop "$CONTAINER_ID_OCI_${safeName}_${mode}" >/dev/null 2>&1 || true
      ${pkgs.docker}/bin/docker rm "$CONTAINER_ID_OCI_${safeName}_${mode}" >/dev/null 2>&1 || true
    fi
  '';
  
  # Execute job in container
  executeJob = { jobName, actionDerivations, env }: ''
    # Ensure workspace is initialized
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      echo "Error: OCI workspace not initialized for ${image} (mode: ${mode})"
      exit 1
    fi
    
    ${pkgs.docker}/bin/docker exec \
      ${lib.concatMapStringsSep " " (k: "-e ${k}") (lib.attrNames env)} \
      "$CONTAINER_ID_OCI_${safeName}_${mode}" \
      bash -c ${lib.escapeShellArg ''
        set -euo pipefail
        
        # Create job directory
        JOB_DIR="/workspace/jobs/${jobName}"
        mkdir -p "$JOB_DIR"
        cd "$JOB_DIR"
        
        # Create job-specific env file INSIDE container workspace
        JOB_ENV="$JOB_DIR/.job-env"
        touch "$JOB_ENV"
        export JOB_ENV
        
        echo "╔════════════════════════════════════════╗"
        echo "║ JOB: ${jobName}"
        echo "║ EXECUTOR: oci-${safeName}-${mode}"
        echo "║ WORKDIR: $JOB_DIR"
        echo "╚════════════════════════════════════════╝"
        
        # Set job-level environment
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: 
            "export ${k}=${lib.escapeShellArg (toString v)}"
          ) env
        )}
        
        # Execute action derivations as separate processes
        ${lib.concatMapStringsSep "\n\n" (action: 
          let
            actionName = action.passthru.name or (builtins.baseNameOf action);
          in ''
            # === ${actionName} ===
            echo "→ ${actionName}"
            
            # Source JOB_ENV and export all variables before running action
            set -a
            [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
            set +a
            
            # Execute action as separate process
            ${action}/bin/${lib.escapeShellArg actionName}
          ''
        ) actionDerivations}
      ''}
  '';
  
  fetchArtifacts = null;
  pushArtifacts = null;
  
  # Save artifact (executed on HOST after job completes)
  # Uses docker cp to copy from container to host
  saveArtifact = { name, path, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      echo "  ✗ Container not initialized"
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
      echo "  ✗ Path not found: ${path}"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  # Uses docker cp to copy from host to container
  restoreArtifact = { name, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${safeName}_${mode}:-}" ]; then
      echo "  ✗ Container not initialized"
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
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
