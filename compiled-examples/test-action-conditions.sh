#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="test-action-conditions-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="test-action-conditions"

# Export log format (default: structured)
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

# ============================================================
# Structured Logging Functions
# ============================================================

_log_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Universal log function: _log key1 value1 key2 value2 ... message
# Last argument is always the message
# Example: _log job test action checkout duration 1.5 exit_code 0 "Completed"
_log() {
  local -A fields=()
  local message=""
  
  # Parse arguments: key-value pairs, last one is message
  while [ $# -gt 0 ]; do
    if [ $# -eq 1 ]; then
      # Last argument is the message
      message="$1"
      shift
    else
      # Key-value pair
      fields["$1"]="$2"
      shift 2
    fi
  done
  
  # Build log entry based on format
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format: just the message (or with action name)
    if [ -n "${fields[action]:-}" ]; then
      echo "${fields[event]:-→} ${fields[action]} $message" >&2
    else
      echo "$message" >&2
    fi
  elif [ "$NIXACTIONS_LOG_FORMAT" = "json" ]; then
    # JSON format
    local json="{\"timestamp\":\"$(_log_timestamp)\",\"workflow\":\"$WORKFLOW_NAME\""
    
    # Add all fields
    for key in "${!fields[@]}"; do
      local value="${fields[$key]}"
      # Check if value is a number
      if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        json="$json,\"$key\":$value"
      else
        # Escape quotes for JSON
        value=$(echo "$value" | sed 's/"/\\"/g')
        json="$json,\"$key\":\"$value\""
      fi
    done
    
    json="$json,\"message\":\"$message\"}"
    echo "$json" >&2
  else
    # Structured format (default)
    local prefix="[$(_log_timestamp)] [workflow:$WORKFLOW_NAME]"
    
    # Add job and action if present
    if [ -n "${fields[job]:-}" ]; then
      prefix="$prefix [job:${fields[job]}]"
    fi
    if [ -n "${fields[action]:-}" ]; then
      prefix="$prefix [action:${fields[action]}]"
    fi
    
    # Build details from remaining fields
    local details=""
    for key in "${!fields[@]}"; do
      if [ "$key" != "job" ] && [ "$key" != "action" ] && [ "$key" != "event" ]; then
        if [ -z "$details" ]; then
          details="($key: ${fields[$key]}"
        else
          details="$details, $key: ${fields[$key]}"
        fi
      fi
    done
    if [ -n "$details" ]; then
      details="$details)"
    fi
    
    echo "$prefix $message ${details}" >&2
  fi
}

# Wrap command output with structured logging
_log_line() {
  local job="$1"
  local action="$2"
  while IFS= read -r line; do
    _log job "$job" action "$action" event "output" "$line"
  done
}

# Log job-level events (convenience wrapper)
_log_job() {
  _log job "$@"
}

# Log workflow-level events (convenience wrapper)
_log_workflow() {
  _log "$@"
}

# Export functions so they're available in subshells and executors
export -f _log_timestamp
export -f _log
export -f _log_line
export -f _log_job
export -f _log_workflow


# Setup artifacts directory on control node
NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
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
      if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
        return 1  # Has failures
      fi
      ;;
    failure\(\))
      if [ ${#FAILED_JOBS[@]} -eq 0 ]; then
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
  local condition=${2:-success()}
  local continue_on_error=${3:-false}
  
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

# Run jobs in parallel
run_parallel() {
  local -a job_specs=("$@")
  local -a pids=()
  local failed=false
  
  # Start all jobs
  for spec in "${job_specs[@]}"; do
    IFS='|' read -r job_name condition continue_on_error <<< "$spec"
    
    # Run in background
    (
      run_job "$job_name" "$condition" "$continue_on_error"
    ) &
    pids+=($!)
  done
  
  # Wait for all jobs
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=true
    fi
  done
  
  if [ "$failed" = "true" ]; then
    # Check if we should stop
    for spec in "${job_specs[@]}"; do
      IFS='|' read -r job_name condition continue_on_error <<< "$spec"
      if [ "${JOB_STATUS[$job_name]:-unknown}" = "failure" ] && [ "$continue_on_error" != "true" ]; then
        _log_workflow failed_job "$job_name" event "⊘" "Stopping workflow due to job failure"
        return 1
      fi
    done
  fi
  
  return 0
}

# Job functions
job_test-always() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-always"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-always" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-fails ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping action1-fails (condition: $ACTION_CONDITION)"
else
  _log job "test-always" action "action1-fails" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails 2>&1 | _log_line "test-always" "action1-fails"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-always" action "action1-fails" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-always" action "action1-fails" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === action2-always-runs ===

# Check action condition
_should_run=true
ACTION_CONDITION="always()"
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
  echo "⊘ Skipping action2-always-runs (condition: $ACTION_CONDITION)"
else
  _log job "test-always" action "action2-always-runs" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/7ncw0p6ggmh42595dnhbmqf5kw93jldr-action2-always-runs/bin/action2-always-runs
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/7ncw0p6ggmh42595dnhbmqf5kw93jldr-action2-always-runs/bin/action2-always-runs 2>&1 | _log_line "test-always" "action2-always-runs"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-always" action "action2-always-runs" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-always" action "action2-always-runs" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-always" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-bash-conditions() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-bash-conditions"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-bash-conditions" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DEPLOY_ENABLED=true
export ENVIRONMENT=production

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === setup ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping setup (condition: $ACTION_CONDITION)"
else
  _log job "test-bash-conditions" action "setup" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/fk8cb0frdfr2nngqzhyfk27lv4d9jgkr-setup/bin/setup
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/fk8cb0frdfr2nngqzhyfk27lv4d9jgkr-setup/bin/setup 2>&1 | _log_line "test-bash-conditions" "setup"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-bash-conditions" action "setup" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-bash-conditions" action "setup" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === deploy-to-production ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$ENVIRONMENT" = "production" ]"
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
  echo "⊘ Skipping deploy-to-production (condition: $ACTION_CONDITION)"
else
  _log job "test-bash-conditions" action "deploy-to-production" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/6h03g3fvi300rcqgk58105a0q4kpi31n-deploy-to-production/bin/deploy-to-production
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/6h03g3fvi300rcqgk58105a0q4kpi31n-deploy-to-production/bin/deploy-to-production 2>&1 | _log_line "test-bash-conditions" "deploy-to-production"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-bash-conditions" action "deploy-to-production" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-bash-conditions" action "deploy-to-production" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === deploy-to-staging ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$ENVIRONMENT" = "staging" ]"
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
  echo "⊘ Skipping deploy-to-staging (condition: $ACTION_CONDITION)"
else
  _log job "test-bash-conditions" action "deploy-to-staging" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/1fdj6cam90kbb3vjq9s9vl04gxjk7nqa-deploy-to-staging/bin/deploy-to-staging
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/1fdj6cam90kbb3vjq9s9vl04gxjk7nqa-deploy-to-staging/bin/deploy-to-staging 2>&1 | _log_line "test-bash-conditions" "deploy-to-staging"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-bash-conditions" action "deploy-to-staging" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-bash-conditions" action "deploy-to-staging" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === notify-if-deploy-enabled ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$DEPLOY_ENABLED" = "true" ]"
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
  echo "⊘ Skipping notify-if-deploy-enabled (condition: $ACTION_CONDITION)"
else
  _log job "test-bash-conditions" action "notify-if-deploy-enabled" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/qgp5lsl1kj8mdgsm61icpyfarzx81ys4-notify-if-deploy-enabled/bin/notify-if-deploy-enabled
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/qgp5lsl1kj8mdgsm61icpyfarzx81ys4-notify-if-deploy-enabled/bin/notify-if-deploy-enabled 2>&1 | _log_line "test-bash-conditions" "notify-if-deploy-enabled"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-bash-conditions" action "notify-if-deploy-enabled" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-bash-conditions" action "notify-if-deploy-enabled" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-bash-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-complex() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-complex"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-complex" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping build (condition: $ACTION_CONDITION)"
else
  _log job "test-complex" action "build" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/vd259nzm2cq5fk0wlmp0lp8mskr03ylb-build/bin/build
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/vd259nzm2cq5fk0wlmp0lp8mskr03ylb-build/bin/build 2>&1 | _log_line "test-complex" "build"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-complex" action "build" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-complex" action "build" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === test ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping test (condition: $ACTION_CONDITION)"
else
  _log job "test-complex" action "test" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/rsiv1296dm34mzx2bbndr89v0acsfmws-test/bin/test
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/rsiv1296dm34mzx2bbndr89v0acsfmws-test/bin/test 2>&1 | _log_line "test-complex" "test"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-complex" action "test" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-complex" action "test" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === deploy-on-success ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping deploy-on-success (condition: $ACTION_CONDITION)"
else
  _log job "test-complex" action "deploy-on-success" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/g0ay3wg0dy8vad0rz0vkjamvy8ck80zy-deploy-on-success/bin/deploy-on-success
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/g0ay3wg0dy8vad0rz0vkjamvy8ck80zy-deploy-on-success/bin/deploy-on-success 2>&1 | _log_line "test-complex" "deploy-on-success"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-complex" action "deploy-on-success" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-complex" action "deploy-on-success" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === notify-on-failure ===

# Check action condition
_should_run=true
ACTION_CONDITION="failure()"
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
  echo "⊘ Skipping notify-on-failure (condition: $ACTION_CONDITION)"
else
  _log job "test-complex" action "notify-on-failure" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/pr2qy8r8i2bpk6gjxab80rrc7jgb5pvk-notify-on-failure/bin/notify-on-failure
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/pr2qy8r8i2bpk6gjxab80rrc7jgb5pvk-notify-on-failure/bin/notify-on-failure 2>&1 | _log_line "test-complex" "notify-on-failure"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-complex" action "notify-on-failure" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-complex" action "notify-on-failure" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === cleanup ===

# Check action condition
_should_run=true
ACTION_CONDITION="always()"
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
  echo "⊘ Skipping cleanup (condition: $ACTION_CONDITION)"
else
  _log job "test-complex" action "cleanup" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/yyaw5fhdqhxwa7d2cxpwrg3c9ifvhnml-cleanup/bin/cleanup
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/yyaw5fhdqhxwa7d2cxpwrg3c9ifvhnml-cleanup/bin/cleanup 2>&1 | _log_line "test-complex" "cleanup"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-complex" action "cleanup" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-complex" action "cleanup" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-complex" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-failure() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-failure"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-failure" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-fails ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping action1-fails (condition: $ACTION_CONDITION)"
else
  _log job "test-failure" action "action1-fails" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails 2>&1 | _log_line "test-failure" "action1-fails"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-failure" action "action1-fails" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-failure" action "action1-fails" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === action2-success-should-skip ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping action2-success-should-skip (condition: $ACTION_CONDITION)"
else
  _log job "test-failure" action "action2-success-should-skip" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/q4ckdpggvgp79c4nrjycmv6zcnvvww9c-action2-success-should-skip/bin/action2-success-should-skip
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/q4ckdpggvgp79c4nrjycmv6zcnvvww9c-action2-success-should-skip/bin/action2-success-should-skip 2>&1 | _log_line "test-failure" "action2-success-should-skip"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-failure" action "action2-success-should-skip" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-failure" action "action2-success-should-skip" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === action3-failure-should-run ===

# Check action condition
_should_run=true
ACTION_CONDITION="failure()"
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
  echo "⊘ Skipping action3-failure-should-run (condition: $ACTION_CONDITION)"
else
  _log job "test-failure" action "action3-failure-should-run" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/hx5f67yrvvf46vibrm45birfsggd1ikw-action3-failure-should-run/bin/action3-failure-should-run
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/hx5f67yrvvf46vibrm45birfsggd1ikw-action3-failure-should-run/bin/action3-failure-should-run 2>&1 | _log_line "test-failure" "action3-failure-should-run"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-failure" action "action3-failure-should-run" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-failure" action "action3-failure-should-run" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-failure" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-success() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-success"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-success" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-succeeds ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping action1-succeeds (condition: $ACTION_CONDITION)"
else
  _log job "test-success" action "action1-succeeds" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/i6imb4psjdmx2y3knpxwkp75l9v899vz-action1-succeeds/bin/action1-succeeds
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/i6imb4psjdmx2y3knpxwkp75l9v899vz-action1-succeeds/bin/action1-succeeds 2>&1 | _log_line "test-success" "action1-succeeds"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-success" action "action1-succeeds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-success" action "action1-succeeds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === action2-with-success-condition ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
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
  echo "⊘ Skipping action2-with-success-condition (condition: $ACTION_CONDITION)"
else
  _log job "test-success" action "action2-with-success-condition" event "→" "Starting"
  
  # Record start time
  _action_start_ns=$(date +%s%N 2>/dev/null || echo "0")
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/hvx9vkmgf588vrrc8pq1qmrgvn89jcic-action2-with-success-condition/bin/action2-with-success-condition
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/hvx9vkmgf588vrrc8pq1qmrgvn89jcic-action2-with-success-condition/bin/action2-with-success-condition 2>&1 | _log_line "test-success" "action2-with-success-condition"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  if [ "$_action_start_ns" != "0" ]; then
    _action_end_ns=$(date +%s%N 2>/dev/null || echo "0")
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | /nix/store/dyh62vfsijvlgqhkw2h3br29ib6fgwsb-bc-1.08.2/bin/bc 2>/dev/null || echo "0")
  else
    _action_duration_s="0"
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-success" action "action2-with-success-condition" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test-success" action "action2-with-success-condition" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-success" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


# Main execution
main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "test-success" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-success|success()|" || {
    _log_workflow level 0 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 1 jobs "test-failure" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-failure|success()|" || {
    _log_workflow level 1 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 2 jobs "test-always" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-always|success()|" || {
    _log_workflow level 2 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 3 jobs "test-bash-conditions" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-bash-conditions|success()|" || {
    _log_workflow level 3 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 4 jobs "test-complex" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-complex|success()|" || {
    _log_workflow level 4 event "✗" "Level failed"
    exit 1
  }

  
  
  
  # Final report
  if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
    _log_workflow failed_jobs "${FAILED_JOBS[*]}" event "✗" "Workflow failed"
    exit 1
  else
    _log_workflow event "✓" "Workflow completed successfully"
  fi
}

main "$@"
