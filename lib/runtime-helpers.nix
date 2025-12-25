{ pkgs, lib }:

# Runtime helpers - bash functions compiled into derivation
# This reduces codegen size by moving common logic into a reusable script

pkgs.writeScriptBin "nixactions-runtime" ''
  #!${pkgs.bash}/bin/bash
  
  # ============================================================
  # Job Status Tracking
  # ============================================================
  
  # Note: Job tracking arrays (JOB_STATUS, FAILED_JOBS) must be initialized
  # in the main workflow script, not here, because bash arrays cannot be
  # exported to sourced scripts via export -f
  
  # ============================================================
  # Action Execution
  # ============================================================
  
  # Execute single action with condition checking, retry, and timing
  # Usage: run_action JOB_NAME ACTION_NAME ACTION_BINARY ACTION_CONDITION [TIMING_COMMAND]
  # Expects: $ACTION_FAILED, $JOB_ENV, $NIXACTIONS_LOG_FORMAT
  # Sets: $ACTION_FAILED (if action fails)
  run_action() {
    local job_name=$1
    local action_name=$2
    local action_binary=$3
    local action_condition=''${4:-success()}
    local timing_command=''${5:-"date +%s%N 2>/dev/null || echo \"0\""}
    
    # Check action condition
    local _should_run=true
    case "$action_condition" in
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
        if ! eval "$action_condition"; then
          _should_run=false
        fi
        ;;
    esac
    
    if [ "$_should_run" = "false" ]; then
      echo "⊘ Skipping $action_name (condition: $action_condition)"
      return 0
    fi
    
    _log job "$job_name" action "$action_name" event "→" "Starting"
    
    # Record start time
    local _action_start_ns=$(eval "$timing_command")
    
    # Source JOB_ENV and export all variables before running action
    set -a
    [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
    set +a
    
    # Define action execution function for retry wrapper
    _execute_action() {
      if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
        # Simple format - pass through unchanged
        "$action_binary"
      else
        # Structured/JSON format - wrap each line
        "$action_binary" 2>&1 | _log_line "$job_name" "$action_name"
        return ''${PIPESTATUS[0]}
      fi
    }
    
    # Execute action with retry wrapper (handles retry if configured)
    set +e
    retry_command _execute_action
    local _action_exit_code=$?
    set -e
    
    # Calculate duration
    local _action_duration_s="0"
    if [ "$_action_start_ns" != "0" ]; then
      local _action_end_ns=$(eval "$timing_command")
      if echo "$_action_start_ns" | grep -q "N"; then
        # Fallback: seconds only (no nanoseconds available)
        _action_duration_s=$((_action_end_ns - _action_start_ns))
      else
        # Nanoseconds available
        local _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
        _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
      fi
    fi
    
    # Log result and track failure for subsequent actions
    if [ $_action_exit_code -ne 0 ]; then
      ACTION_FAILED=true
      _log job "$job_name" action "$action_name" duration "''${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
      # Don't exit immediately - let conditions handle flow
    else
      _log job "$job_name" action "$action_name" duration "''${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
    fi
    
    return $_action_exit_code
  }
  
  # ============================================================
  # Condition Checking
  # ============================================================
  
  # Check if condition is met
  # Usage: check_condition "success()" || echo "skip"
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
        # Bash expression condition - evaluate it
        if eval "$condition"; then
          return 0
        else
          return 1
        fi
        ;;
    esac
    
    return 0
  }
  
  # ============================================================
  # Job Execution
  # ============================================================
  
  # Run single job with condition check
  # Usage: run_job "job_name" "success()" "false"
  run_job() {
    local job_name=$1
    local condition=''${2:-success()}
    local continue_on_error=''${3:-false}
    
    # Check condition
    if ! check_condition "$condition"; then
      _log_job "$job_name" condition "$condition" event "⊘" "Skipped"
      JOB_STATUS[$job_name]="skipped"
      return 0
    fi
    
    # Execute job in subshell (isolation by design)
    if ( job_$job_name ); then
      _log_job "$job_name" event "✓" "Job succeeded"
      JOB_STATUS[$job_name]="success"
      return 0
    else
      local exit_code=$?
      _log_job "$job_name" exit_code $exit_code event "✗" "Job failed"
      FAILED_JOBS+=("$job_name")
      JOB_STATUS[$job_name]="failure"
      
      if [ "$continue_on_error" = "true" ]; then
        _log_job "$job_name" continue_on_error true event "→" "Continuing despite failure"
        return 0
      else
        return $exit_code
      fi
    fi
  }
  
  # ============================================================
  # Parallel Execution
  # ============================================================
  
  # Run jobs in parallel
  # Usage: run_parallel "job1|success()|false" "job2|always()|true"
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
          _log_workflow failed_job "$job_name" event "⊘" "Stopping workflow due to job failure"
          return 1
        fi
      done
    fi
    
    return 0
  }
  
  # ============================================================
  # Workflow Summary
  # ============================================================
  
  # Print final workflow report
  workflow_summary() {
    if [ ''${#FAILED_JOBS[@]} -gt 0 ]; then
      _log_workflow failed_jobs "''${FAILED_JOBS[*]}" event "✗" "Workflow failed"
      return 1
    else
      _log_workflow event "✓" "Workflow completed successfully"
      return 0
    fi
  }
  
  # ============================================================
  # Export functions for use in workflow
  # ============================================================
  
  export -f check_condition
  export -f run_job
  export -f run_parallel
  export -f workflow_summary
  export -f run_action
''
