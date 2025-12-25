{ pkgs, lib }:

{
  name,
  jobs,
  env ? {},
  envFrom ? [],  # List of environment provider derivations
  logging ? {},  # { format = "structured"; level = "info"; }
  retry ? null,  # Workflow-level retry config
  timeout ? null,  # Workflow-level timeout (e.g., "30m", "1h", "120s")
}:

assert lib.assertMsg (name != "") "Workflow name cannot be empty";
assert lib.assertMsg (builtins.isAttrs jobs) "jobs must be an attribute set";
assert lib.assertMsg (builtins.isList envFrom) "envFrom must be a list of provider derivations";

let
  # Import logging utilities
  loggingLib = import ./logging.nix { inherit pkgs lib; };
  
  # Import retry utilities
  retryLib = import ./retry.nix { inherit lib pkgs; };
  
  # Import timeout utilities
  timeoutLib = import ./timeout.nix { inherit pkgs lib; };
  
  # Import runtime helpers (derivation)
  runtimeHelpers = import ./runtime-helpers.nix { inherit pkgs lib; };
  
  # Create logger for this workflow
  logger = loggingLib.mkLogger {
    workflow = name;
    format = logging.format or "structured";
    level = logging.level or "info";
  };
  # Validate unique artifact names across all jobs
  allOutputs = lib.flatten (
    lib.mapAttrsToList (jobName: job: 
      lib.attrNames (job.outputs or {})
    ) jobs
  );
  
  duplicateArtifacts = lib.filter 
    (name: (lib.count (x: x == name) allOutputs) > 1) 
    (lib.unique allOutputs);
in

assert lib.assertMsg (duplicateArtifacts == []) 
  "Duplicate artifact names found: ${toString duplicateArtifacts}. Each artifact name must be unique across all jobs.";

let
  # Calculate dependency depth for each job
  calcDepth = jobName: job:
    let
      needs = job.needs or [];
    in
    if needs == []
    then 0
    else 1 + lib.foldl' lib.max 0 (map (dep: calcDepth dep jobs.${dep}) needs);
  
  # Depths for all jobs
  depths = lib.mapAttrs (name: job: calcDepth name job) jobs;
  
  # Max depth
  maxDepth = lib.foldl' lib.max 0 (lib.attrValues depths);
  
  # Group jobs by level
  levels = lib.genList (level:
    lib.filterAttrs (name: job: depths.${name} == level) jobs
  ) (maxDepth + 1);
  
  # Extract deps from actions
  extractDeps = actions: 
    lib.unique (lib.concatMap (a: a.deps or []) actions);
  
  # Convert action attribute to derivation if needed
  # Also merges retry and timeout configuration from workflow -> job -> action
  toActionDerivation = jobRetry: jobTimeout: action:
    if builtins.isAttrs action && !(action ? type && action.type == "derivation")
    then
      # It's an attribute, convert to derivation
      let
        actionName = action.name or "action";
        actionBash = action.bash or "echo 'No bash script provided'";
        
        # Merge retry configs: action > job > workflow
        actionRetry = retryLib.mergeRetryConfigs {
          workflow = retry;
          job = jobRetry;
          action = action.retry or null;
        };
        
        # Merge timeout configs: action > job > workflow
        actionTimeout = timeoutLib.mergeTimeoutConfigs {
          workflow = timeout;
          job = jobTimeout;
          action = action.timeout or null;
        };
        
        # Extract dependencies
        actionDeps = action.deps or [];
        
        drv = pkgs.writeShellApplication {
          name = actionName;
          runtimeInputs = actionDeps;
          text = actionBash;
        };
      in
        drv // {
          passthru = (drv.passthru or {}) // {
            name = actionName;
            bash = actionBash;
            deps = action.deps or [];
            env = action.env or {};
            workdir = action.workdir or null;
            condition = action.condition or null;
            retry = actionRetry;  # Merged retry config
            timeout = actionTimeout;  # Merged timeout config
          };
        }
    else
      # Already a derivation - try to extract bash from it
      action // {
        passthru = (action.passthru or {}) // {
          bash = action.passthru.bash or null;
        };
      };
  
  # Normalize input specification to { name, path } format
  normalizeInput = input:
    if builtins.isString input
    then { name = input; path = "."; }  # Simple string -> default path
    else input;  # Already attribute set
  
  # Collect all action derivations from all jobs
  allActionDerivations = lib.unique (lib.flatten (
    lib.mapAttrsToList (jobName: job:
      let
        jobRetry = job.retry or retry;
        jobTimeout = job.timeout or timeout;
      in
        map (toActionDerivation jobRetry jobTimeout) job.actions
    ) jobs
  ));
  
  # Generate single job bash function
  generateJob = jobName: job:
    let
      executor = job.executor;
      
      # Merge retry config for this job: job > workflow
      jobRetry = job.retry or retry;
      
      # Merge timeout config for this job: job > workflow
      jobTimeout = job.timeout or timeout;
      
      # Convert actions to derivations (if not already)
      actionDerivations = map (toActionDerivation jobRetry jobTimeout) job.actions;
      
      # Job-level environment
      jobEnv = lib.attrsets.mergeAttrsList [ env (job.env or {}) ];
      
      # Normalize inputs to { name, path } format
      normalizedInputs = map normalizeInput (job.inputs or []);
      
    in ''
      job_${jobName}() {
        ${executor.setupWorkspace { inherit actionDerivations; }}
        ${lib.optionalString (normalizedInputs != []) ''
        # Restore artifacts
        _log_job "${jobName}" artifacts "${toString (map (i: i.name) normalizedInputs)}" event "→" "Restoring artifacts"
        ${lib.concatMapStringsSep "\n" (input: ''
        ${executor.restoreArtifact { 
          name = input.name; 
          path = input.path; 
          inherit jobName; 
        }}
        _log_job "${jobName}" artifact "${input.name}" path "${input.path}" event "✓" "Restored"
        '') normalizedInputs}
        ''}
        ${executor.executeJob {
          inherit jobName actionDerivations;
          env = jobEnv;
        }}
        ${lib.optionalString ((job.outputs or {}) != {}) ''
        # Save artifacts
        _log_job "${jobName}" event "→" "Saving artifacts"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: path: ''
        ${executor.saveArtifact { inherit name path jobName; }}
        ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/${name}" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  ✓ Saved: ${name} → ${path} (''${ARTIFACT_SIZE})"
        '') job.outputs
        )}
        ''}
      }
    '';

in (pkgs.writeScriptBin name ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  WORKFLOW_ID="${name}-$(date +%s)-$$"
  export WORKFLOW_ID WORKFLOW_NAME="${name}"
  export NIXACTIONS_LOG_FORMAT=''${NIXACTIONS_LOG_FORMAT:-${logging.format or "structured"}}
  
  source ${loggingLib.loggingHelpers}/bin/nixactions-logging
  source ${retryLib.retryHelpers}/bin/nixactions-retry
  source ${runtimeHelpers}/bin/nixactions-runtime
  
  NIXACTIONS_ARTIFACTS_DIR="''${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
  export NIXACTIONS_ARTIFACTS_DIR
  
  declare -A JOB_STATUS
  FAILED_JOBS=()
  WORKFLOW_CANCELLED=false
  trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM
  
  # ============================================
  # Environment Provider Execution
  # ============================================
  
  # Helper: Execute provider and apply exports
  run_provider() {
    local provider=$1
    local provider_name=$(basename "$provider")
    
    _log_workflow provider "$provider_name" event "→" "Loading environment"
    
    # Execute provider, capture output
    local output
    if ! output=$("$provider" 2>&1); then
      local exit_code=$?
      _log_workflow provider "$provider_name" event "✗" "Provider failed (exit $exit_code)"
      echo "$output" >&2
      exit $exit_code
    fi
    
    # Apply exports - providers always override previous values
    # Runtime environment (already in shell) has highest priority
    local vars_set=0
    local vars_from_runtime=0
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        local key="''${BASH_REMATCH[1]}"
        
        # Check if variable was set from runtime (before provider execution started)
        # We detect this by checking if it's in our RUNTIME_ENV_KEYS list
        if [[ " ''${RUNTIME_ENV_KEYS} " =~ " ''${key} " ]]; then
          # Runtime env has highest priority - skip
          vars_from_runtime=$((vars_from_runtime + 1))
        else
          # Apply provider value (may override previous provider)
          eval "$line"
          vars_set=$((vars_set + 1))
        fi
      fi
    done <<< "$output"
    
    if [ $vars_set -gt 0 ]; then
      _log_workflow provider "$provider_name" vars_set "$vars_set" event "✓" "Variables loaded"
    fi
    if [ $vars_from_runtime -gt 0 ]; then
      _log_workflow provider "$provider_name" vars_from_runtime "$vars_from_runtime" event "⊘" "Variables skipped (runtime override)"
    fi
  }
  
  # Execute envFrom providers in order
  ${lib.optionalString (envFrom != []) ''
  # Capture runtime environment keys (highest priority)
  RUNTIME_ENV_KEYS=$(compgen -e | tr '\n' ' ')
  
  _log_workflow event "→" "Loading environment from providers"
  ${lib.concatMapStringsSep "\n" (provider: ''
  run_provider "${provider}/bin/$(ls ${provider}/bin | head -1)"
  '') envFrom}
  _log_workflow event "✓" "Environment loaded"
  ''}
  
  # Apply workflow-level env (hardcoded, lowest priority)
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
  if [ -z "''${${k}+x}" ]; then
    export ${k}=${lib.escapeShellArg (toString v)}
  fi'') env)}
  
  # ============================================
  # Job Functions
  # ============================================
  
  ${lib.concatStringsSep "\n" 
    (lib.mapAttrsToList generateJob jobs)}
  
  main() {
    _log_workflow levels ${toString (maxDepth + 1)} event "▶" "Workflow starting"
    ${lib.concatMapStringsSep "\n" (levelIdx:
      let
        level = lib.elemAt levels levelIdx;
        levelJobs = lib.attrNames level;
      in
        if levelJobs == [] then ""
        else ''
          _log_workflow level ${toString levelIdx} jobs "${lib.concatStringsSep ", " levelJobs}" event "→" "Starting level"
          run_parallel ${lib.concatMapStringsSep " " (jobName:
            let
              job = level.${jobName};
              condition = job."if" or "success()";
              continueOnError = toString (job.continueOnError or false);
            in
              ''"${jobName}|${condition}|${continueOnError}"''
          ) levelJobs} || {
            _log_workflow level ${toString levelIdx} event "✗" "Level failed"
            exit 1
          }
        ''
    ) (lib.range 0 maxDepth)}
    workflow_summary || exit 1
  }
  
  main "$@"
'').overrideAttrs (old: {
  # Add all action derivations and env providers as build-time dependencies
  # This ensures Nix knows about them and includes them in closures
  buildInputs = (old.buildInputs or []) ++ allActionDerivations ++ envFrom ++ [
    loggingLib.loggingHelpers
    retryLib.retryHelpers
    timeoutLib.timeoutHelpers
    runtimeHelpers
  ];
})
