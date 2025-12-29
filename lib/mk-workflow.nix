{ pkgs, lib }:

{
  name,
  jobs,
  env ? {},
  envFrom ? [],  # List of environment provider derivations
  logging ? {},  # { format = "structured"; level = "info"; }
  retry ? null,  # Workflow-level retry config
  timeout ? null,  # Workflow-level timeout (e.g., "30m", "1h", "120s")
  extensions ? [],  # List of workflow transformers: workflow -> workflow
}:

# Apply extensions to raw workflow config
let
  rawWorkflow = { inherit name jobs env envFrom logging retry timeout; };
  workflow = lib.pipe rawWorkflow extensions;
in

assert lib.assertMsg (workflow.name != "") "Workflow name cannot be empty";
assert lib.assertMsg (builtins.isAttrs workflow.jobs) "jobs must be an attribute set";
assert lib.assertMsg (builtins.isList workflow.envFrom) "envFrom must be a list of provider derivations";

let
  # Extract values from (possibly transformed) workflow
  inherit (workflow) name jobs env envFrom logging retry timeout;
  # Import runtime libraries
  runtimeLibs = import ./runtime-libs { inherit pkgs lib; };
  loggingLib = runtimeLibs.logging;
  retryLib = runtimeLibs.retry;
  timeoutLib = runtimeLibs.timeout;
  runtimeHelpers = runtimeLibs.runtimeHelpers;
  
  # Create logger for this workflow
  logger = loggingLib.mkLogger {
    workflow = name;
    format = logging.format or "structured";
    level = logging.level or "info";
  };
  
  # Filter out empty jobs created by lib.optionalAttrs
  # This happens when job templates use lib.optionalAttrs with false condition
  # Support both 'steps' (new) and 'actions' (deprecated) for backward compatibility
  nonEmptyJobs = lib.filterAttrs (name: job: 
    job != {} && ((job.steps or null) != null || (job.actions or null) != null)
  ) jobs;
  
  # Helper to get steps from job (supports both 'steps' and deprecated 'actions')
  getJobSteps = job: job.steps or job.actions or [];
  
  # Validate unique artifact names across all jobs
  allOutputs = lib.flatten (
    lib.mapAttrsToList (jobName: job: 
      lib.attrNames (job.outputs or {})
    ) nonEmptyJobs
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
    else 1 + lib.foldl' lib.max 0 (map (dep: calcDepth dep nonEmptyJobs.${dep}) needs);
  
  # Depths for all jobs
  depths = lib.mapAttrs (name: job: calcDepth name job) nonEmptyJobs;
  
  # Max depth
  maxDepth = lib.foldl' lib.max 0 (lib.attrValues depths);
  
  # Group jobs by level
  levels = lib.genList (level:
    lib.filterAttrs (name: job: depths.${name} == level) nonEmptyJobs
  ) (maxDepth + 1);
  
  # Extract deps from steps
  extractDeps = steps: 
    lib.unique (lib.concatMap (a: a.deps or []) steps);
  
  # Convert step attribute to derivation if needed
  # Also merges retry and timeout configuration from workflow -> job -> step
  toStepDerivation = jobRetry: jobTimeout: step:
    if builtins.isAttrs step && !(step ? type && step.type == "derivation")
    then
      # It's an attribute, convert to derivation
      let
        stepName = step.name or "step";
        stepBash = step.bash or "echo 'No bash script provided'";
        
        # Merge retry configs: step > job > workflow
        stepRetry = retryLib.mergeRetryConfigs {
          workflow = retry;
          job = jobRetry;
          action = step.retry or null;  # Keep 'action' key for retryLib compatibility
        };
        
        # Merge timeout configs: step > job > workflow
        stepTimeout = timeoutLib.mergeTimeoutConfigs {
          workflow = timeout;
          job = jobTimeout;
          action = step.timeout or null;  # Keep 'action' key for timeoutLib compatibility
        };
        
        # Extract dependencies
        stepDeps = step.deps or [];
        
        drv = pkgs.writeShellApplication {
          name = stepName;
          runtimeInputs = stepDeps;
          text = stepBash;
        };
      in
        drv // {
          passthru = (drv.passthru or {}) // {
            name = stepName;
            bash = stepBash;
            deps = step.deps or [];
            env = step.env or {};
            workdir = step.workdir or null;
            condition = step.condition or null;
            retry = stepRetry;  # Merged retry config
            timeout = stepTimeout;  # Merged timeout config
          };
        }
    else
      # Already a derivation - try to extract bash from it
      step // {
        passthru = (step.passthru or {}) // {
          bash = step.passthru.bash or null;
        };
      };
  
  # Normalize input specification to { name, path } format
  normalizeInput = input:
    if builtins.isString input
    then { name = input; path = "."; }  # Simple string -> default path
    else input;  # Already attribute set
  
  # Collect all step derivations from all jobs
  allStepDerivations = lib.unique (lib.flatten (
    lib.mapAttrsToList (jobName: job:
      let
        jobRetry = job.retry or retry;
        jobTimeout = job.timeout or timeout;
      in
        map (toStepDerivation jobRetry jobTimeout) (getJobSteps job)
    ) nonEmptyJobs
  ));
  
  # Collect all unique executors (by name) for cleanup
  # We need to deduplicate by executor.name, not by reference
  allExecutors = 
    let
      executorsByName = lib.foldl' (acc: job:
        if acc ? ${job.executor.name}
        then acc  # Already have this executor
        else acc // { ${job.executor.name} = job.executor; }
      ) {} (lib.attrValues nonEmptyJobs);
    in
      lib.attrValues executorsByName;
  
  # For each unique executor, collect its step derivations
  # This is needed for setupWorkspace({ stepDerivations })
  executorStepDerivations = lib.listToAttrs (
    map (executor:
      let
        # Find all jobs using this executor (by name)
        jobsUsingExecutor = lib.filterAttrs (jobName: job: job.executor.name == executor.name) nonEmptyJobs;
        # Collect all step derivations from those jobs
        execStepDerivs = lib.unique (lib.flatten (
          lib.mapAttrsToList (jobName: job:
            let
              jobRetry = job.retry or retry;
              jobTimeout = job.timeout or timeout;
            in
              map (toStepDerivation jobRetry jobTimeout) (getJobSteps job)
          ) jobsUsingExecutor
        ));
      in {
        name = executor.name;
        value = execStepDerivs;
      }
    ) allExecutors
  );
  
  # Generate single job bash function
  generateJob = jobName: job:
    let
      executor = job.executor;
      
      # Merge retry config for this job: job > workflow
      jobRetry = job.retry or retry;
      
      # Merge timeout config for this job: job > workflow
      jobTimeout = job.timeout or timeout;
      
      # Convert steps to derivations (if not already)
      # actionDerivations name kept for executor API compatibility
      actionDerivations = map (toStepDerivation jobRetry jobTimeout) (getJobSteps job);
      
      # Job-level environment (static, from Nix)
      jobEnv = lib.attrsets.mergeAttrsList [ env (job.env or {}) ];
      
      # Job-level envFrom providers
      jobEnvFrom = job.envFrom or [];
      
      # Normalize inputs to { name, path } format
      normalizedInputs = map normalizeInput (job.inputs or []);
      
    in ''
      job_${jobName}() {
        # Create job-specific env file (starts with workflow-level providers)
        NIXACTIONS_JOB_ENV_FILE="''${NIXACTIONS_ARTIFACTS_DIR}/../.env-job-${jobName}"
        if [ -f "$NIXACTIONS_ENV_FILE" ]; then
          cp "$NIXACTIONS_ENV_FILE" "$NIXACTIONS_JOB_ENV_FILE"
        else
          : > "$NIXACTIONS_JOB_ENV_FILE"
        fi
        chmod 600 "$NIXACTIONS_JOB_ENV_FILE"
        export NIXACTIONS_JOB_ENV_FILE
        
        ${lib.optionalString (jobEnvFrom != []) ''
        # Execute job-level envFrom providers
        _log_job "${jobName}" event "→" "Loading job environment providers"
        ${lib.concatMapStringsSep "\n" (provider: ''
        _provider="${provider}/bin/$(ls ${provider}/bin | head -1)"
        _provider_name=$(basename "$_provider")
        _output=$("$_provider" 2>&1) || {
          _log_job "${jobName}" provider "$_provider_name" event "✗" "Provider failed"
          echo "$_output" >&2
          exit 1
        }
        # Append valid exports to job env file
        echo "$_output" | grep -E '^export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=' >> "$NIXACTIONS_JOB_ENV_FILE" || true
        # Source after each provider so subsequent providers can see/validate these vars
        source "$NIXACTIONS_JOB_ENV_FILE"
        '') jobEnvFrom}
        _log_job "${jobName}" event "✓" "Job environment loaded"
        ''}
        
        # Source job outputs from dependency jobs (SDK feature)
        if [ -n "''${NIXACTIONS_JOB_OUTPUTS:-}" ] && [ -s "$NIXACTIONS_JOB_OUTPUTS" ]; then
          source "$NIXACTIONS_JOB_OUTPUTS"
        fi
        
        ${executor.setupJob { inherit jobName actionDerivations; }}
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
          envFile = "NIXACTIONS_JOB_ENV_FILE";  # Pass env file path variable name
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
        ${executor.cleanupJob { inherit jobName; }}
      }
    '';

in (pkgs.writeScriptBin name ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  WORKFLOW_ID="${name}-$(date +%s)-$$"
  # Short ID for K8s pod names (must be <63 chars total)
  # Format: first 15 chars of name + last 8 chars of timestamp+pid
  WORKFLOW_SHORT_ID="$(echo "${name}" | cut -c1-15)-$(echo "$(date +%s)-$$" | tail -c 12)"
  export WORKFLOW_ID WORKFLOW_SHORT_ID WORKFLOW_NAME="${name}"
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
  
  # Cleanup function for workspaces (includes job status files)
  cleanup_all() {
    # Cleanup all executor workspaces (this removes everything including .job-status/)
    ${lib.concatMapStringsSep "\n" (executor: 
      executor.cleanupWorkspace { 
        actionDerivations = executorStepDerivations.${executor.name}; 
      }
    ) allExecutors}
  }
  
  # Trap to cleanup on exit (success, error, or signal)
  trap 'cleanup_all' EXIT
  trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; cleanup_all; exit 130' SIGINT SIGTERM
  
  # ============================================
  # Environment Provider Execution
  # ============================================
  
  # Environment file for provider variables (shared with executors)
  NIXACTIONS_ENV_FILE="''${NIXACTIONS_ARTIFACTS_DIR}/../.env-providers"
  mkdir -p "$(dirname "$NIXACTIONS_ENV_FILE")"
  : > "$NIXACTIONS_ENV_FILE"  # Create/truncate file
  chmod 600 "$NIXACTIONS_ENV_FILE"  # Secure permissions
  export NIXACTIONS_ENV_FILE
  
  # Job outputs file for SDK typed jobs (persists OUTPUT_* between jobs)
  NIXACTIONS_JOB_OUTPUTS="''${NIXACTIONS_ARTIFACTS_DIR}/../.job-outputs"
  : > "$NIXACTIONS_JOB_OUTPUTS"  # Create/truncate file
  chmod 600 "$NIXACTIONS_JOB_OUTPUTS"
  export NIXACTIONS_JOB_OUTPUTS
  
  # Helper: Execute provider and write exports to file
  # After writing, source the file so subsequent providers see the variables
  # (e.g., "required" provider needs to validate that previous providers set vars)
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
    
    # Write valid exports to env file
    # Runtime environment (already in shell) has highest priority
    local vars_set=0
    local vars_from_runtime=0
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        local key="''${BASH_REMATCH[1]}"
        
        # Check if variable was set from runtime (before provider execution started)
        if [[ " ''${RUNTIME_ENV_KEYS} " =~ " ''${key} " ]]; then
          # Runtime env has highest priority - skip
          vars_from_runtime=$((vars_from_runtime + 1))
        else
          # Write to env file
          echo "$line" >> "$NIXACTIONS_ENV_FILE"
          vars_set=$((vars_set + 1))
        fi
      fi
    done <<< "$output"
    
    # Source env file so subsequent providers can see/validate these variables
    # This is necessary for providers like "required" that check if vars are set
    if [ -s "$NIXACTIONS_ENV_FILE" ]; then
      source "$NIXACTIONS_ENV_FILE"
    fi
    
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
    (lib.mapAttrsToList generateJob nonEmptyJobs)}
  
  main() {
    _log_workflow levels ${toString (maxDepth + 1)} event "▶" "Workflow starting"
    
    # Setup workspaces for all unique executors
    ${lib.concatMapStringsSep "\n" (executor: 
      executor.setupWorkspace { 
        actionDerivations = executorStepDerivations.${executor.name}; 
      }
    ) allExecutors}
    
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
              continueOnError = if (job.continueOnError or false) then "true" else "false";
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
  # Add all step derivations and env providers as build-time dependencies
  # This ensures Nix knows about them and includes them in closures
  buildInputs = (old.buildInputs or []) ++ allStepDerivations ++ envFrom ++ [
    loggingLib.loggingHelpers
    retryLib.retryHelpers
    timeoutLib.timeoutHelpers
    runtimeHelpers
  ];
})
