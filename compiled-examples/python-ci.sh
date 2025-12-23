#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="python-ci-cd-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="python-ci-cd"

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
job_build-image() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-image"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-image" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === checkout-code ===

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
  echo "⊘ Skipping checkout-code (condition: $ACTION_CONDITION)"
else
  _log job "build-image" action "checkout-code" event "→" "Starting"
  
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
    /nix/store/svw5qkwjaps8904ciii9d5h9dns354ig-checkout-code/bin/checkout-code
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/svw5qkwjaps8904ciii9d5h9dns354ig-checkout-code/bin/checkout-code 2>&1 | _log_line "build-image" "checkout-code"
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
    _log job "build-image" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-image" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === prepare-build-context ===

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
  echo "⊘ Skipping prepare-build-context (condition: $ACTION_CONDITION)"
else
  _log job "build-image" action "prepare-build-context" event "→" "Starting"
  
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
    /nix/store/9h7ix2ilf3iqar6n151rsjxnh197hkgq-prepare-build-context/bin/prepare-build-context
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/9h7ix2ilf3iqar6n151rsjxnh197hkgq-prepare-build-context/bin/prepare-build-context 2>&1 | _log_line "build-image" "prepare-build-context"
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
    _log job "build-image" action "prepare-build-context" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-image" action "prepare-build-context" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === build-docker-image ===

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
  echo "⊘ Skipping build-docker-image (condition: $ACTION_CONDITION)"
else
  _log job "build-image" action "build-docker-image" event "→" "Starting"
  
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
    /nix/store/7qvlkx4rlwlx1n6jgq30bz7i9i0dy6s4-build-docker-image/bin/build-docker-image
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/7qvlkx4rlwlx1n6jgq30bz7i9i0dy6s4-build-docker-image/bin/build-docker-image 2>&1 | _log_line "build-image" "build-docker-image"
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
    _log job "build-image" action "build-docker-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-image" action "build-docker-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === scan-image ===

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
  echo "⊘ Skipping scan-image (condition: $ACTION_CONDITION)"
else
  _log job "build-image" action "scan-image" event "→" "Starting"
  
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
    /nix/store/k59qwjwgyqahazfkmyxxmlsyvj5g6spx-scan-image/bin/scan-image
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/k59qwjwgyqahazfkmyxxmlsyvj5g6spx-scan-image/bin/scan-image 2>&1 | _log_line "build-image" "scan-image"
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
    _log job "build-image" action "scan-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-image" action "scan-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-image" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_cleanup() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/cleanup"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "cleanup" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === cleanup-temp-files ===

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
  echo "⊘ Skipping cleanup-temp-files (condition: $ACTION_CONDITION)"
else
  _log job "cleanup" action "cleanup-temp-files" event "→" "Starting"
  
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
    /nix/store/s6lf0sphzip0741vnl1sf8smqqsjms2c-cleanup-temp-files/bin/cleanup-temp-files
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/s6lf0sphzip0741vnl1sf8smqqsjms2c-cleanup-temp-files/bin/cleanup-temp-files 2>&1 | _log_line "cleanup" "cleanup-temp-files"
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
    _log job "cleanup" action "cleanup-temp-files" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "cleanup" action "cleanup-temp-files" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "cleanup" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_lint() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/lint"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "lint" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === checkout-code ===

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
  echo "⊘ Skipping checkout-code (condition: $ACTION_CONDITION)"
else
  _log job "lint" action "checkout-code" event "→" "Starting"
  
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
    /nix/store/c0dhi8jydadpzc58yaffxl4ixgd0hqff-checkout-code/bin/checkout-code
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/c0dhi8jydadpzc58yaffxl4ixgd0hqff-checkout-code/bin/checkout-code 2>&1 | _log_line "lint" "checkout-code"
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
    _log job "lint" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "lint" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === lint-python ===

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
  echo "⊘ Skipping lint-python (condition: $ACTION_CONDITION)"
else
  _log job "lint" action "lint-python" event "→" "Starting"
  
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
    /nix/store/lvqbr3lk1gw5r2bqmxky1k1zc3i0kw92-lint-python/bin/lint-python
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/lvqbr3lk1gw5r2bqmxky1k1zc3i0kw92-lint-python/bin/lint-python 2>&1 | _log_line "lint" "lint-python"
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
    _log job "lint" action "lint-python" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "lint" action "lint-python" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_notify-failure() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/notify-failure"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "notify-failure" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === send-failure-notification ===

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
  echo "⊘ Skipping send-failure-notification (condition: $ACTION_CONDITION)"
else
  _log job "notify-failure" action "send-failure-notification" event "→" "Starting"
  
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
    /nix/store/f815w7sw8aja53a5kfjyqicqf8nxlx7v-send-failure-notification/bin/send-failure-notification
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/f815w7sw8aja53a5kfjyqicqf8nxlx7v-send-failure-notification/bin/send-failure-notification 2>&1 | _log_line "notify-failure" "send-failure-notification"
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
    _log job "notify-failure" action "send-failure-notification" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "notify-failure" action "send-failure-notification" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_notify-success() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/notify-success"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "notify-success" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === send-success-notification ===

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
  echo "⊘ Skipping send-success-notification (condition: $ACTION_CONDITION)"
else
  _log job "notify-success" action "send-success-notification" event "→" "Starting"
  
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
    /nix/store/6hi0c44ykwh1wydhvjcvp5mq4f620ib2-send-success-notification/bin/send-success-notification
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/6hi0c44ykwh1wydhvjcvp5mq4f620ib2-send-success-notification/bin/send-success-notification 2>&1 | _log_line "notify-success" "send-success-notification"
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
    _log job "notify-success" action "send-success-notification" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "notify-success" action "send-success-notification" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_push-image() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/push-image"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "push-image" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === push-to-registry ===

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
  echo "⊘ Skipping push-to-registry (condition: $ACTION_CONDITION)"
else
  _log job "push-image" action "push-to-registry" event "→" "Starting"
  
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
    /nix/store/rza33asqiczadan9h4d3anq9vjy811l4-push-to-registry/bin/push-to-registry
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/rza33asqiczadan9h4d3anq9vjy811l4-push-to-registry/bin/push-to-registry 2>&1 | _log_line "push-image" "push-to-registry"
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
    _log job "push-image" action "push-to-registry" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "push-image" action "push-to-registry" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "push-image" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === checkout-code ===

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
  echo "⊘ Skipping checkout-code (condition: $ACTION_CONDITION)"
else
  _log job "test" action "checkout-code" event "→" "Starting"
  
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
    /nix/store/y509h1x395wk9saaxlhs3pa6sn3vp68r-checkout-code/bin/checkout-code
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/y509h1x395wk9saaxlhs3pa6sn3vp68r-checkout-code/bin/checkout-code 2>&1 | _log_line "test" "checkout-code"
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
    _log job "test" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test" action "checkout-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === install-dependencies ===

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
  echo "⊘ Skipping install-dependencies (condition: $ACTION_CONDITION)"
else
  _log job "test" action "install-dependencies" event "→" "Starting"
  
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
    /nix/store/zxg75zf1ahbg19p12rs3rg8r9434pgvh-install-dependencies/bin/install-dependencies
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/zxg75zf1ahbg19p12rs3rg8r9434pgvh-install-dependencies/bin/install-dependencies 2>&1 | _log_line "test" "install-dependencies"
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
    _log job "test" action "install-dependencies" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test" action "install-dependencies" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === run-unit-tests ===

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
  echo "⊘ Skipping run-unit-tests (condition: $ACTION_CONDITION)"
else
  _log job "test" action "run-unit-tests" event "→" "Starting"
  
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
    /nix/store/nx55vq678ipkzrv4inf8nziig1chzzmj-run-unit-tests/bin/run-unit-tests
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/nx55vq678ipkzrv4inf8nziig1chzzmj-run-unit-tests/bin/run-unit-tests 2>&1 | _log_line "test" "run-unit-tests"
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
    _log job "test" action "run-unit-tests" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test" action "run-unit-tests" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === test-app-execution ===

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
  echo "⊘ Skipping test-app-execution (condition: $ACTION_CONDITION)"
else
  _log job "test" action "test-app-execution" event "→" "Starting"
  
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
    /nix/store/r6byhsbmb280yjrm4x9b0cxsf1kdn31w-test-app-execution/bin/test-app-execution
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/r6byhsbmb280yjrm4x9b0cxsf1kdn31w-test-app-execution/bin/test-app-execution 2>&1 | _log_line "test" "test-app-execution"
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
    _log job "test" action "test-app-execution" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "test" action "test-app-execution" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_type-check() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/type-check"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "type-check" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === setup-code-for-typecheck ===

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
  echo "⊘ Skipping setup-code-for-typecheck (condition: $ACTION_CONDITION)"
else
  _log job "type-check" action "setup-code-for-typecheck" event "→" "Starting"
  
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
    /nix/store/r5fk48am7gha455sjqi3515pmr4naxz0-setup-code-for-typecheck/bin/setup-code-for-typecheck
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/r5fk48am7gha455sjqi3515pmr4naxz0-setup-code-for-typecheck/bin/setup-code-for-typecheck 2>&1 | _log_line "type-check" "setup-code-for-typecheck"
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
    _log job "type-check" action "setup-code-for-typecheck" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "type-check" action "setup-code-for-typecheck" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === run-mypy ===

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
  echo "⊘ Skipping run-mypy (condition: $ACTION_CONDITION)"
else
  _log job "type-check" action "run-mypy" event "→" "Starting"
  
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
    /nix/store/mlkn0qyj09f3kn5qag3mnwlk9w06bf0k-run-mypy/bin/run-mypy
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/mlkn0qyj09f3kn5qag3mnwlk9w06bf0k-run-mypy/bin/run-mypy 2>&1 | _log_line "type-check" "run-mypy"
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
    _log job "type-check" action "run-mypy" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "type-check" action "run-mypy" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "type-check" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


# Main execution
main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "lint, type-check" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "lint|success()|" \
    "type-check|success()|" || {
    _log_workflow level 0 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 1 jobs "test" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test|success()|" || {
    _log_workflow level 1 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 2 jobs "build-image" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build-image|success()|" || {
    _log_workflow level 2 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 3 jobs "notify-failure, notify-success, push-image" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "notify-failure|failure()|" \
    "notify-success|success()|" \
    "push-image|success()|" || {
    _log_workflow level 3 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 4 jobs "cleanup" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "cleanup|always()|" || {
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
