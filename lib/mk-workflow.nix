{ pkgs, lib }:

{
  name,
  jobs,
  env ? {},
  logging ? {},  # { format = "structured"; level = "info"; }
  retry ? null,  # Workflow-level retry config
}:

assert lib.assertMsg (name != "") "Workflow name cannot be empty";
assert lib.assertMsg (builtins.isAttrs jobs) "jobs must be an attribute set";

let
  # Import logging utilities
  loggingLib = import ./logging.nix { inherit pkgs lib; };
  
  # Import retry utilities
  retryLib = import ./retry.nix { inherit lib pkgs; };
  
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
  # Also merges retry configuration from workflow -> job -> action
  toActionDerivation = jobRetry: action:
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
        
        # Extract dependencies
        actionDeps = action.deps or [];
        
        drv = pkgs.writeScriptBin actionName ''
          #!${pkgs.bash}/bin/bash
          
          # Add dependencies to PATH
          ${lib.optionalString (actionDeps != []) ''
            export PATH=${lib.makeBinPath actionDeps}:$PATH
          ''}
          
          ${actionBash}
        '';
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
  
  # Generate single job bash function
  generateJob = jobName: job:
    let
      executor = job.executor;
      
      # Merge retry config for this job: job > workflow
      jobRetry = job.retry or retry;
      
      # Convert actions to derivations (if not already)
      actionDerivations = map (toActionDerivation jobRetry) job.actions;
      
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

in pkgs.writeScriptBin name ''
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
''
