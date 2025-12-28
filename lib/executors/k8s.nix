# Kubernetes Executor
# Runs jobs in Kubernetes pods with images built via dockerTools
#
# This executor REQUIRES configuration (no defaults) because registry is mandatory.
# Usage: platform.executors.k8s { namespace = "ci"; registry = {...}; }

{ pkgs, lib, mkExecutor, linuxPkgs ? pkgs }:

let
  # Import helpers
  actionRunner = import ./action-runner.nix { inherit lib pkgs; };
  
  # Import shared image builder
  imageBuilder = import ./oci-image-builder.nix { inherit pkgs lib linuxPkgs; };
  inherit (imageBuilder) buildLinuxActions buildExecutorImage;
  inherit (imageBuilder) loggingLib retryLib runtimeHelpers timeoutLib;
in

# K8s executor is a function that takes config and returns executor
# No default instance - always requires configuration
{
  namespace ? "default",
  registry,  # Required: { url, usernameEnv, passwordEnv }
  mode ? "shared",
  copyRepo ? true,
  name ? null,
  extraPackages ? [],
  containerEnv ? {},
  kubeconfigEnv ? null,
  contextEnv ? null,
  serviceAccount ? null,
  nodeSelector ? {},
  resources ? {
    requests = { cpu = "500m"; memory = "1Gi"; };
    limits = { cpu = "2"; memory = "4Gi"; };
  },
  labels ? {},
  annotations ? {},
  podReadyTimeout ? 300,
}:

assert lib.assertMsg (registry ? url && registry.url != null) "K8s executor requires registry.url";
assert lib.assertMsg (registry ? usernameEnv && registry.usernameEnv != null) "K8s executor requires registry.usernameEnv";
assert lib.assertMsg (registry ? passwordEnv && registry.passwordEnv != null) "K8s executor requires registry.passwordEnv";

let
  executorName = if name != null then name else "k8s";
  
  # Sanitize names for bash variables
  sanitizedExecutorName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] executorName;
  
  # Kubectl command with optional kubeconfig/context
  kubectlBase = "${pkgs.kubectl}/bin/kubectl"
    + lib.optionalString (kubeconfigEnv != null) " --kubeconfig=\"\${${kubeconfigEnv}}\""
    + lib.optionalString (contextEnv != null) " --context=\"\${${contextEnv}}\"";
  
  kubectl = cmd: "${kubectlBase} ${cmd}";
  
  # Generate pod name (K8s limits labels/names to 63 chars)
  # Use short workflow ID: first 8 chars of name + timestamp suffix
  mkPodName = suffix: 
    let
      suffixPart = lib.optionalString (suffix != "") "-${suffix}";
      # Base: nixactions- (10) + exec name + suffix = variable
      # We need to keep it under 63 chars total
      # Use $WORKFLOW_SHORT_ID which is set to first 20 chars of workflow + timestamp
    in "nxa-\${WORKFLOW_SHORT_ID}-${executorName}${suffixPart}";
  
  # Generate resource overrides for kubectl run
  # kubectl run doesn't support --requests/--limits directly, use --overrides
  resourceOverrides = 
    let
      reqCpu = resources.requests.cpu or null;
      reqMem = resources.requests.memory or null;
      limCpu = resources.limits.cpu or null;
      limMem = resources.limits.memory or null;
      
      requests = lib.filterAttrs (k: v: v != null) {
        cpu = reqCpu;
        memory = reqMem;
      };
      limits = lib.filterAttrs (k: v: v != null) {
        cpu = limCpu;
        memory = limMem;
      };
      
      resourcesObj = lib.filterAttrs (k: v: v != {}) {
        inherit requests limits;
      };
    in
    if resourcesObj == {} then ""
    else " --overrides='{\"spec\":{\"containers\":[{\"name\":\"nixactions-${executorName}\",\"resources\":${builtins.toJSON resourcesObj}}]}}'";
  
  # For now, skip resources to simplify (kubectl run is limited)
  resourceArgs = "";
  
  # Generate label args
  labelArgs = lib.concatStringsSep "" (
    lib.mapAttrsToList (k: v: " -l ${k}=${v}") labels
  );
  
in
mkExecutor {
  inherit copyRepo;
  name = executorName;
  
  # === WORKSPACE LEVEL ===
  
  setupWorkspace = { actionDerivations }:
    let
      image = buildExecutorImage {
        inherit actionDerivations executorName extraPackages containerEnv;
      };
      fullImageName = "${registry.url}/nixactions-${executorName}:${image.imageTag}";
      podName = mkPodName "";
    in
    if mode == "shared" then ''
      # === K8s Shared Mode: Setup Workspace ===
      _log_workflow executor "${executorName}" mode "shared" event "→" "Setting up K8s workspace"
      
      # Store image info for later use
      K8S_IMAGE_${sanitizedExecutorName}="${fullImageName}"
      K8S_POD_${sanitizedExecutorName}="${podName}"
      export K8S_IMAGE_${sanitizedExecutorName} K8S_POD_${sanitizedExecutorName}
      
      # 1. Load image locally
      _log_workflow executor "${executorName}" event "→" "Loading OCI image locally"
      ${pkgs.gzip}/bin/zcat ${image.imageTarball} | ${pkgs.docker}/bin/docker load >&2
      
      # 2. Tag for registry
      _log_workflow executor "${executorName}" event "→" "Tagging image for registry"
      ${pkgs.docker}/bin/docker tag ${image.imageName}:${image.imageTag} ${fullImageName} >&2
      
      # 3. Login to registry
      _log_workflow executor "${executorName}" registry "${registry.url}" event "→" "Logging in to registry"
      echo "''${${registry.passwordEnv}}" | ${pkgs.docker}/bin/docker login ${registry.url} \
        -u "''${${registry.usernameEnv}}" --password-stdin >&2
      
      # 4. Push image
      _log_workflow executor "${executorName}" image "${fullImageName}" event "→" "Pushing image to registry"
      ${pkgs.docker}/bin/docker push ${fullImageName} >&2
      
      # 5. Create pod
      _log_workflow executor "${executorName}" pod "${podName}" namespace "${namespace}" event "→" "Creating pod"
      ${kubectl "run ${podName}"} \
        --namespace=${namespace} \
        --image=${fullImageName} \
        --restart=Never \
        ${resourceArgs} \
        ${labelArgs} \
        ${lib.optionalString (serviceAccount != null) "--serviceaccount=${serviceAccount}"} \
        -- sleep infinity >&2
      
      # 6. Wait for pod to be ready
      _log_workflow executor "${executorName}" pod "${podName}" timeout "${toString podReadyTimeout}s" event "→" "Waiting for pod to be ready"
      if ! ${kubectl "wait"} \
        --namespace=${namespace} \
        --for=condition=Ready \
        pod/${podName} \
        --timeout=${toString podReadyTimeout}s >&2; then
        _log_workflow executor "${executorName}" pod "${podName}" event "✗" "Pod failed to become ready within ${toString podReadyTimeout}s"
        ${kubectl "logs"} --namespace=${namespace} ${podName} >&2 || true
        ${kubectl "describe pod"} --namespace=${namespace} ${podName} >&2 || true
        exit 1
      fi
      
      _log_workflow executor "${executorName}" pod "${podName}" event "✓" "Pod is ready"
      
      # 7. Copy golden standard (repository)
      if [ "''${NIXACTIONS_COPY_REPO:-${if copyRepo then "true" else "false"}}" = "true" ]; then
        _log_workflow executor "${executorName}" event "→" "Copying repository to pod (golden standard)"
        
        # Create .golden directory
        ${kubectl "exec"} --namespace=${namespace} ${podName} -- mkdir -p /workspace/.golden >&2
        
        # Copy current directory to pod
        # kubectl cp requires tar in the container (we have gnutar)
        ${kubectlBase} cp "$PWD/." ${namespace}/${podName}:/workspace/.golden >&2
        
        _log_workflow executor "${executorName}" event "✓" "Golden standard copied"
      fi
    '' else ''
      # === K8s Dedicated Mode: Setup Workspace ===
      # In dedicated mode, we only build and push the image here
      # Pods are created per-job in setupJob
      
      _log_workflow executor "${executorName}" mode "dedicated" event "→" "Setting up K8s workspace (dedicated mode)"
      
      # Store image info for later use
      K8S_IMAGE_${sanitizedExecutorName}="${fullImageName}"
      export K8S_IMAGE_${sanitizedExecutorName}
      
      # 1. Load image locally
      _log_workflow executor "${executorName}" event "→" "Loading OCI image locally"
      ${pkgs.gzip}/bin/zcat ${image.imageTarball} | ${pkgs.docker}/bin/docker load >&2
      
      # 2. Tag for registry
      _log_workflow executor "${executorName}" event "→" "Tagging image for registry"
      ${pkgs.docker}/bin/docker tag ${image.imageName}:${image.imageTag} ${fullImageName} >&2
      
      # 3. Login to registry
      _log_workflow executor "${executorName}" registry "${registry.url}" event "→" "Logging in to registry"
      echo "''${${registry.passwordEnv}}" | ${pkgs.docker}/bin/docker login ${registry.url} \
        -u "''${${registry.usernameEnv}}" --password-stdin >&2
      
      # 4. Push image
      _log_workflow executor "${executorName}" image "${fullImageName}" event "→" "Pushing image to registry"
      ${pkgs.docker}/bin/docker push ${fullImageName} >&2
      
      _log_workflow executor "${executorName}" event "✓" "Image ready in registry"
    '';
  
  cleanupWorkspace = { actionDerivations }:
    let
      podName = mkPodName "";
    in
    if mode == "shared" then ''
      # === K8s Shared Mode: Cleanup Workspace ===
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_workflow executor "${executorName}" pod "${podName}" event "→" "Deleting pod"
        ${kubectl "delete pod"} --namespace=${namespace} ${podName} --ignore-not-found >&2 || true
      else
        _log_workflow executor "${executorName}" pod "${podName}" event "→" "Pod preserved (NIXACTIONS_KEEP_WORKSPACE=1)"
      fi
    '' else ''
      # === K8s Dedicated Mode: Cleanup Workspace ===
      # Pods are cleaned up in cleanupJob, nothing to do here
      _log_workflow executor "${executorName}" event "→" "Workspace cleanup complete (dedicated mode)"
    '';
  
  # === JOB LEVEL ===
  
  setupJob = { jobName, actionDerivations }:
    let
      sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
      podName = mkPodName "";
      jobPodName = mkPodName jobName;
      
      # For dedicated mode, we need to build the image
      image = buildExecutorImage {
        inherit actionDerivations executorName extraPackages containerEnv;
      };
      fullImageName = "${registry.url}/nixactions-${executorName}:${image.imageTag}";
    in
    if mode == "shared" then ''
      # === K8s Shared Mode: Setup Job ===
      _log_job "${jobName}" executor "${executorName}" event "→" "Setting up job directory"
      
      # Create jobs directory and copy from golden standard
      ${kubectl "exec"} --namespace=${namespace} ${podName} -- \
        mkdir -p /workspace/jobs >&2
      ${kubectl "exec"} --namespace=${namespace} ${podName} -- \
        cp -r /workspace/.golden /workspace/jobs/${jobName} >&2
      
      _log_job "${jobName}" executor "${executorName}" workdir "/workspace/jobs/${jobName}" event "▶" "Job starting"
    '' else ''
      # === K8s Dedicated Mode: Setup Job ===
      _log_job "${jobName}" executor "${executorName}" event "→" "Creating dedicated pod for job"
      
      # Store pod name for this job
      K8S_JOB_POD_${sanitizedExecutorName}_${sanitizedJobName}="${jobPodName}"
      export K8S_JOB_POD_${sanitizedExecutorName}_${sanitizedJobName}
      
      # Create pod for this job
      ${kubectl "run ${jobPodName}"} \
        --namespace=${namespace} \
        --image="$K8S_IMAGE_${sanitizedExecutorName}" \
        --restart=Never \
        ${resourceArgs} \
        ${labelArgs} \
        ${lib.optionalString (serviceAccount != null) "--serviceaccount=${serviceAccount}"} \
        -- sleep infinity >&2
      
      # Wait for pod to be ready
      _log_job "${jobName}" executor "${executorName}" pod "${jobPodName}" timeout "${toString podReadyTimeout}s" event "→" "Waiting for pod"
      if ! ${kubectl "wait"} \
        --namespace=${namespace} \
        --for=condition=Ready \
        pod/${jobPodName} \
        --timeout=${toString podReadyTimeout}s >&2; then
        _log_job "${jobName}" executor "${executorName}" pod "${jobPodName}" event "✗" "Pod failed to become ready"
        ${kubectl "logs"} --namespace=${namespace} ${jobPodName} >&2 || true
        exit 1
      fi
      
      _log_job "${jobName}" executor "${executorName}" pod "${jobPodName}" event "✓" "Pod is ready"
      
      # Copy repository to pod
      if [ "''${NIXACTIONS_COPY_REPO:-${if copyRepo then "true" else "false"}}" = "true" ]; then
        _log_job "${jobName}" event "→" "Copying repository to pod"
        ${kubectl "exec"} --namespace=${namespace} ${jobPodName} -- mkdir -p /workspace >&2
        ${kubectlBase} cp "$PWD/." ${namespace}/${jobPodName}:/workspace >&2
        _log_job "${jobName}" event "✓" "Repository copied"
      fi
      
      _log_job "${jobName}" executor "${executorName}" workdir "/workspace" event "▶" "Job starting"
    '';
  
  executeJob = { jobName, actionDerivations, env, envFile ? null }:
    let
      sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
      podName = mkPodName "";
      
      # Pod variable depends on mode
      podVar = if mode == "shared"
        then "\"${podName}\""
        else "\"$K8S_JOB_POD_${sanitizedExecutorName}_${sanitizedJobName}\"";
      
      # Working directory inside pod
      workdir = if mode == "shared"
        then "/workspace/jobs/${jobName}"
        else "/workspace";
      
      # Rebuild actions for Linux
      linuxActionDerivations = buildLinuxActions actionDerivations;
    in ''
      # === K8s: Transfer environment to pod ===
      _K8S_ENV_FILE=$(mktemp)
      trap "rm -f '$_K8S_ENV_FILE'" RETURN
      
      # Start with env providers file (workflow + job level)
      if [ -n "''${${if envFile != null then envFile else "NIXACTIONS_ENV_FILE"}:-}" ] && \
         [ -f "''${${if envFile != null then envFile else "NIXACTIONS_ENV_FILE"}}" ]; then
        cp "''${${if envFile != null then envFile else "NIXACTIONS_ENV_FILE"}}" "$_K8S_ENV_FILE"
      else
        : > "$_K8S_ENV_FILE"
      fi
      
      # Add static job-level env vars (these override providers)
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: 
          ''echo "export ${k}=${lib.escapeShellArg (toString v)}" >> "$_K8S_ENV_FILE"''
        ) env
      )}
      
      # Copy env file to pod
      ${kubectlBase} cp "$_K8S_ENV_FILE" ${namespace}/${podVar}:${workdir}/.nixactions-env >&2
      
      # === K8s: Execute Job ===
      ${kubectl "exec"} --namespace=${namespace} ${podVar} -- \
        env WORKFLOW_NAME="$WORKFLOW_NAME" WORKFLOW_ID="$WORKFLOW_ID" NIXACTIONS_LOG_FORMAT="$NIXACTIONS_LOG_FORMAT" \
        bash -c ${lib.escapeShellArg ''
          set -uo pipefail
          cd ${workdir}
          
          # Source helpers
          source ${loggingLib.loggingHelpers}/bin/nixactions-logging
          source ${retryLib.retryHelpers}/bin/nixactions-retry
          source ${runtimeHelpers}/bin/nixactions-runtime
          
          JOB_ENV="${workdir}/.job-env"
          touch "$JOB_ENV"
          export JOB_ENV
          
          # Load environment from providers file
          if [ -f "${workdir}/.nixactions-env" ]; then
            source "${workdir}/.nixactions-env"
          fi
          
          ACTION_FAILED=false
          ${lib.concatMapStringsSep "\n" (action:
            let
              originalName = action.passthru.originalName or action.passthru.name or "action";
              drvName = action.name or (builtins.baseNameOf action);
            in
              actionRunner.generateActionExecution {
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
  
  cleanupJob = { jobName }:
    let
      sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
      jobPodName = mkPodName jobName;
    in
    if mode == "shared" then ''
      # === K8s Shared Mode: Cleanup Job ===
      # Pod stays running, nothing to do
      true
    '' else ''
      # === K8s Dedicated Mode: Cleanup Job ===
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_job "${jobName}" executor "${executorName}" pod "${jobPodName}" event "→" "Deleting pod"
        ${kubectl "delete pod"} --namespace=${namespace} ${jobPodName} --ignore-not-found >&2 || true
      else
        _log_job "${jobName}" executor "${executorName}" pod "${jobPodName}" event "→" "Pod preserved"
      fi
    '';
  
  # === ARTIFACTS ===
  
  saveArtifact = { name, path, jobName }:
    let
      sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
      podName = mkPodName "";
      
      podVar = if mode == "shared"
        then "\"${podName}\""
        else "\"$K8S_JOB_POD_${sanitizedExecutorName}_${sanitizedJobName}\"";
      
      workdir = if mode == "shared"
        then "/workspace/jobs/${jobName}"
        else "/workspace";
    in ''
      # === K8s: Save Artifact ===
      _log_workflow artifact "${name}" path "${path}" event "→" "Saving artifact from pod"
      
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      # Copy from pod to host
      ${kubectlBase} cp ${namespace}/${podVar}:${workdir}/${path} "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}" >&2
      
      _log_workflow artifact "${name}" event "✓" "Artifact saved"
    '';
  
  restoreArtifact = { name, path ? ".", jobName }:
    let
      sanitizedJobName = builtins.replaceStrings ["-" "/" ":" "."] ["_" "_" "_" "_"] jobName;
      podName = mkPodName "";
      
      podVar = if mode == "shared"
        then "\"${podName}\""
        else "\"$K8S_JOB_POD_${sanitizedExecutorName}_${sanitizedJobName}\"";
      
      workdir = if mode == "shared"
        then "/workspace/jobs/${jobName}"
        else "/workspace";
    in ''
      # === K8s: Restore Artifact ===
      if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
        _log_workflow artifact "${name}" path "${path}" event "→" "Restoring artifact to pod"
        
        # Determine target directory
        if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
          TARGET_PATH="${workdir}"
        else
          TARGET_PATH="${workdir}/${path}"
          ${kubectl "exec"} --namespace=${namespace} ${podVar} -- mkdir -p "$TARGET_PATH" >&2
        fi
        
        # Copy from host to pod
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            ${kubectlBase} cp "$item" ${namespace}/${podVar}:"$TARGET_PATH/" >&2
          fi
        done
        
        _log_workflow artifact "${name}" event "✓" "Artifact restored"
      else
        _log_workflow artifact "${name}" event "✗" "Artifact not found"
        return 1
      fi
    '';
}
