{ pkgs, lib }:

{
  name,
  jobs,
  env ? {},
}:

assert lib.assertMsg (name != "") "Workflow name cannot be empty";
assert lib.assertMsg (builtins.isAttrs jobs) "jobs must be an attribute set";

let
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
  toActionDerivation = action:
    if builtins.isAttrs action && !(action ? type && action.type == "derivation")
    then
      # It's an attribute, convert to derivation
      let
        actionName = action.name or "action";
        actionBash = action.bash or "echo 'No bash script provided'";
        drv = pkgs.writeScriptBin actionName ''
          #!${pkgs.bash}/bin/bash
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
          };
        }
    else
      # Already a derivation - try to extract bash from it
      action // {
        passthru = (action.passthru or {}) // {
          bash = action.passthru.bash or null;
        };
      };
  
  # Generate single job bash function
  generateJob = jobName: job:
    let
      executor = job.executor;
      
      # Convert actions to derivations (if not already)
      actionDerivations = map toActionDerivation job.actions;
      
      # Job-level environment
      jobEnv = lib.attrsets.mergeAttrsList [ env (job.env or {}) ];
      
    in ''
      job_${jobName}() {
        # Setup workspace for this job
        ${executor.setupWorkspace { inherit actionDerivations; }}
        
        ${lib.optionalString ((job.inputs or []) != []) ''
          # Restore artifacts on HOST before executing job
          echo "→ Restoring artifacts: ${toString job.inputs}"
          ${lib.concatMapStringsSep "\n" (name: ''
            ${executor.restoreArtifact { inherit name jobName; }}
            echo "  ✓ Restored: ${name}"
          '') job.inputs}
          echo ""
        ''}
        
        # Execute job via executor
        ${executor.executeJob {
          inherit jobName actionDerivations;
          env = jobEnv;
        }}
        
        ${lib.optionalString ((job.outputs or {}) != {}) ''
          # Save artifacts on HOST after job completes
          echo ""
          echo "→ Saving artifacts"
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
  
  # NixActions workflow - executors own workspace (v2)
  
  # Generate workflow ID
  WORKFLOW_ID="${name}-$(date +%s)-$$"
  export WORKFLOW_ID
  
  # Setup artifacts directory on control node
  NIXACTIONS_ARTIFACTS_DIR="''${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
  export NIXACTIONS_ARTIFACTS_DIR
  
  # Job status tracking
  declare -A JOB_STATUS
  FAILED_JOBS=()
  WORKFLOW_CANCELLED=false
  
  # Trap cancellation
  trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM
  
  # Check if condition is met
  check_condition() {
    local condition=$1
    
    case "$condition" in
      success\(\))
        if [ ''${#FAILED_JOBS[@]} -gt 0 ]; then
          return 1  # Has failures
        fi
        ;;
      failure\(\))
        if [ ''${#FAILED_JOBS[@]} -eq 0 ]; then
          return 1  # No failures
        fi
        ;;
      always\(\))
        return 0  # Always run
        ;;
      cancelled\(\))
        if [ "$WORKFLOW_CANCELLED" = "false" ]; then
          return 1
        fi
        ;;
      *)
        echo "Unknown condition: $condition"
        return 1
        ;;
    esac
    
    return 0
  }
  
  # Run single job with condition check
  run_job() {
    local job_name=$1
    local condition=''${2:-success()}
    local continue_on_error=''${3:-false}
    
    # Check condition
    if ! check_condition "$condition"; then
      echo "⊘ Skipping $job_name (condition not met: $condition)"
      JOB_STATUS[$job_name]="skipped"
      return 0
    fi
    
    # Execute job in subshell (isolation by design)
    if ( job_$job_name ); then
      echo "✓ Job $job_name succeeded"
      JOB_STATUS[$job_name]="success"
      return 0
    else
      local exit_code=$?
      echo "✗ Job $job_name failed (exit code: $exit_code)"
      FAILED_JOBS+=("$job_name")
      JOB_STATUS[$job_name]="failure"
      
      if [ "$continue_on_error" = "true" ]; then
        echo "→ Continuing despite failure (continueOnError: true)"
        return 0
      else
        return $exit_code
      fi
    fi
  }
  
  # Run jobs in parallel
  run_parallel() {
    local -a job_specs=("$@")
    local -a pids=()
    local failed=false
    
    # Start all jobs
    for spec in "''${job_specs[@]}"; do
      IFS='|' read -r job_name condition continue_on_error <<< "$spec"
      
      # Run in background
      (
        run_job "$job_name" "$condition" "$continue_on_error"
      ) &
      pids+=($!)
    done
    
    # Wait for all jobs
    for pid in "''${pids[@]}"; do
      if ! wait "$pid"; then
        failed=true
      fi
    done
    
    if [ "$failed" = "true" ]; then
      # Check if we should stop
      for spec in "''${job_specs[@]}"; do
        IFS='|' read -r job_name condition continue_on_error <<< "$spec"
        if [ "''${JOB_STATUS[$job_name]:-unknown}" = "failure" ] && [ "$continue_on_error" != "true" ]; then
          echo "⊘ Stopping workflow due to job failure: $job_name"
          return 1
        fi
      done
    fi
    
    return 0
  }
  
  # Job functions
  ${lib.concatStringsSep "\n\n" 
    (lib.mapAttrsToList generateJob jobs)}
  
  # Main execution
  main() {
    echo "════════════════════════════════════════"
    echo " Workflow: ${name}"
    echo " Execution: GitHub Actions style (parallel)"
    echo " Levels: ${toString (maxDepth + 1)}"
    echo "════════════════════════════════════════"
    echo ""
    
    # Execute level by level
    ${lib.concatMapStringsSep "\n\n" (levelIdx:
      let
        level = lib.elemAt levels levelIdx;
        levelJobs = lib.attrNames level;
      in
        if levelJobs == [] then ""
        else ''
          echo "→ Level ${toString levelIdx}: ${lib.concatStringsSep ", " levelJobs}"
          
          # Build job specs (name|condition|continueOnError)
          run_parallel \
             ${lib.concatMapStringsSep " \\\n    " (jobName:
              let
                job = level.${jobName};
                condition = job."if" or "success()";
                continueOnError = toString (job.continueOnError or false);
              in
                ''"${jobName}|${condition}|${continueOnError}"''
            ) levelJobs} || {
              echo "⊘ Level ${toString levelIdx} failed"
              exit 1
            }
          
          echo ""
        ''
    ) (lib.range 0 maxDepth)}
    
    # Final report
    echo "════════════════════════════════════════"
    if [ ''${#FAILED_JOBS[@]} -gt 0 ]; then
      echo "✗ Workflow failed"
      echo ""
      echo "Failed jobs:"
      printf '  - %s\n' "''${FAILED_JOBS[@]}"
      echo ""
      echo "Job statuses:"
      for job in ${lib.concatStringsSep " " (lib.attrNames jobs)}; do
        echo "  $job: ''${JOB_STATUS[$job]:-unknown}"
      done
      exit 1
    else
      echo "✓ Workflow completed successfully"
      echo ""
      echo "All jobs succeeded:"
      for job in ${lib.concatStringsSep " " (lib.attrNames jobs)}; do
        if [ "''${JOB_STATUS[$job]:-unknown}" = "success" ]; then
          echo "  ✓ $job"
        elif [ "''${JOB_STATUS[$job]:-unknown}" = "skipped" ]; then
          echo "  ⊘ $job (skipped)"
        fi
      done
    fi
    echo "════════════════════════════════════════"
  }
  
  main "$@"
''
