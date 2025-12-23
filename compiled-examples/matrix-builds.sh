#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="matrix-demo-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="matrix-demo"

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
job_build-arch-amd64-distro-alpine() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-amd64-distro-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-arch-amd64-distro-alpine" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-amd64-alpine ===

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
  echo "⊘ Skipping build-amd64-alpine (condition: $ACTION_CONDITION)"
else
  _log job "build-arch-amd64-distro-alpine" action "build-amd64-alpine" event "→" "Starting"
  
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
    /nix/store/1hj1gq4jmxzhphqslqsaabfh80kwz55c-build-amd64-alpine/bin/build-amd64-alpine
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/1hj1gq4jmxzhphqslqsaabfh80kwz55c-build-amd64-alpine/bin/build-amd64-alpine 2>&1 | _log_line "build-arch-amd64-distro-alpine" "build-amd64-alpine"
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
    _log job "build-arch-amd64-distro-alpine" action "build-amd64-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-arch-amd64-distro-alpine" action "build-amd64-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-amd64-distro-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  # Save artifacts on HOST after job completes
_log_job "build-arch-amd64-distro-alpine" event "→" "Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-amd64-distro-alpine"
if [ -e "$JOB_DIR/build-amd64-alpine/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "build-amd64-alpine/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/build-amd64-alpine/" "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine/build-amd64-alpine/"
else
  _log_workflow artifact "build-amd64-alpine" path "build-amd64-alpine/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-amd64-alpine → build-amd64-alpine/ (${ARTIFACT_SIZE})"


}


job_build-arch-amd64-distro-debian() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-amd64-distro-debian"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-arch-amd64-distro-debian" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-amd64-debian ===

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
  echo "⊘ Skipping build-amd64-debian (condition: $ACTION_CONDITION)"
else
  _log job "build-arch-amd64-distro-debian" action "build-amd64-debian" event "→" "Starting"
  
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
    /nix/store/f7jfvy3rqqz79b767cj16sgh663xy3ss-build-amd64-debian/bin/build-amd64-debian
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/f7jfvy3rqqz79b767cj16sgh663xy3ss-build-amd64-debian/bin/build-amd64-debian 2>&1 | _log_line "build-arch-amd64-distro-debian" "build-amd64-debian"
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
    _log job "build-arch-amd64-distro-debian" action "build-amd64-debian" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-arch-amd64-distro-debian" action "build-amd64-debian" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-amd64-distro-debian" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  # Save artifacts on HOST after job completes
_log_job "build-arch-amd64-distro-debian" event "→" "Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-amd64-distro-debian"
if [ -e "$JOB_DIR/build-amd64-debian/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "build-amd64-debian/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/build-amd64-debian/" "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian/build-amd64-debian/"
else
  _log_workflow artifact "build-amd64-debian" path "build-amd64-debian/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-amd64-debian → build-amd64-debian/ (${ARTIFACT_SIZE})"


}


job_build-arch-arm64-distro-alpine() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-arm64-distro-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-arch-arm64-distro-alpine" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-arm64-alpine ===

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
  echo "⊘ Skipping build-arm64-alpine (condition: $ACTION_CONDITION)"
else
  _log job "build-arch-arm64-distro-alpine" action "build-arm64-alpine" event "→" "Starting"
  
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
    /nix/store/8di988vxb5q89kzg6zx9pa80cs1rzzny-build-arm64-alpine/bin/build-arm64-alpine
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/8di988vxb5q89kzg6zx9pa80cs1rzzny-build-arm64-alpine/bin/build-arm64-alpine 2>&1 | _log_line "build-arch-arm64-distro-alpine" "build-arm64-alpine"
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
    _log job "build-arch-arm64-distro-alpine" action "build-arm64-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-arch-arm64-distro-alpine" action "build-arm64-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-arm64-distro-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  # Save artifacts on HOST after job completes
_log_job "build-arch-arm64-distro-alpine" event "→" "Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-arm64-distro-alpine"
if [ -e "$JOB_DIR/build-arm64-alpine/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "build-arm64-alpine/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/build-arm64-alpine/" "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine/build-arm64-alpine/"
else
  _log_workflow artifact "build-arm64-alpine" path "build-arm64-alpine/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-arm64-alpine → build-arm64-alpine/ (${ARTIFACT_SIZE})"


}


job_build-arch-arm64-distro-debian() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-arm64-distro-debian"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-arch-arm64-distro-debian" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-arm64-debian ===

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
  echo "⊘ Skipping build-arm64-debian (condition: $ACTION_CONDITION)"
else
  _log job "build-arch-arm64-distro-debian" action "build-arm64-debian" event "→" "Starting"
  
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
    /nix/store/kd8p8rj2apf0ncfqzqx8p0jisf117nlg-build-arm64-debian/bin/build-arm64-debian
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/kd8p8rj2apf0ncfqzqx8p0jisf117nlg-build-arm64-debian/bin/build-arm64-debian 2>&1 | _log_line "build-arch-arm64-distro-debian" "build-arm64-debian"
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
    _log job "build-arch-arm64-distro-debian" action "build-arm64-debian" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-arch-arm64-distro-debian" action "build-arm64-debian" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-arm64-distro-debian" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  # Save artifacts on HOST after job completes
_log_job "build-arch-arm64-distro-debian" event "→" "Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-arch-arm64-distro-debian"
if [ -e "$JOB_DIR/build-arm64-debian/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "build-arm64-debian/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/build-arm64-debian/" "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian/build-arm64-debian/"
else
  _log_workflow artifact "build-arm64-debian" path "build-arm64-debian/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-arm64-debian → build-arm64-debian/ (${ARTIFACT_SIZE})"


}


job_deploy() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  # Restore artifacts on HOST before executing job
_log_job "deploy" artifacts "build-amd64-debian build-amd64-alpine build-arm64-debian build-arm64-alpine" event "→" "Restoring artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/deploy"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "build-amd64-debian" event "✗" "Artifact not found"
  return 1
fi

_log_job "deploy" artifact "build-amd64-debian" event "✓" "Restored"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/deploy"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "build-amd64-alpine" event "✗" "Artifact not found"
  return 1
fi

_log_job "deploy" artifact "build-amd64-alpine" event "✓" "Restored"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/deploy"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "build-arm64-debian" event "✗" "Artifact not found"
  return 1
fi

_log_job "deploy" artifact "build-arm64-debian" event "✓" "Restored"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/deploy"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "build-arm64-alpine" event "✗" "Artifact not found"
  return 1
fi

_log_job "deploy" artifact "build-arm64-alpine" event "✓" "Restored"


  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/deploy"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "deploy" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === deploy-all-builds ===

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
  echo "⊘ Skipping deploy-all-builds (condition: $ACTION_CONDITION)"
else
  _log job "deploy" action "deploy-all-builds" event "→" "Starting"
  
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
    /nix/store/gd0kgpih366gyidcqzjgbmvnyx8xwbbc-deploy-all-builds/bin/deploy-all-builds
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/gd0kgpih366gyidcqzjgbmvnyx8xwbbc-deploy-all-builds/bin/deploy-all-builds 2>&1 | _log_line "deploy" "deploy-all-builds"
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
    _log job "deploy" action "deploy-all-builds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "deploy" action "deploy-all-builds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_summary() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/summary"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "summary" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === workflow-summary ===

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
  echo "⊘ Skipping workflow-summary (condition: $ACTION_CONDITION)"
else
  _log job "summary" action "workflow-summary" event "→" "Starting"
  
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
    /nix/store/5hrs7z5a6b8p8hrj3hfyfph0rwz0kshc-workflow-summary/bin/workflow-summary
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/5hrs7z5a6b8p8hrj3hfyfph0rwz0kshc-workflow-summary/bin/workflow-summary 2>&1 | _log_line "summary" "workflow-summary"
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
    _log job "summary" action "workflow-summary" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "summary" action "workflow-summary" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-node-18-os-alpine() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_18_alpine_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_18_alpine_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:18-alpine \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_18_alpine_mount"
  
  export CONTAINER_ID_OCI_node_18_alpine_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_18_alpine_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_18_alpine-mount" container "$CONTAINER_ID_OCI_node_18_alpine_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_18_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_18_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_18_alpine_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-18-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-18-os-alpine" executor "oci-node_18_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-18-on-alpine ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-18-on-alpine (condition: $ACTION_CONDITION)"
else
  _log job "test-node-18-os-alpine" action "test-node-18-on-alpine" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/jafskyk77g76fmgk5c6044dlc5ldyrs3-test-node-18-on-alpine/bin/test-node-18-on-alpine
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/jafskyk77g76fmgk5c6044dlc5ldyrs3-test-node-18-on-alpine/bin/test-node-18-on-alpine 2>&1 | _log_line "test-node-18-os-alpine" "test-node-18-on-alpine"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-18-os-alpine" action "test-node-18-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-18-os-alpine" action "test-node-18-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-18-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-node-18-os-ubuntu() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_18_ubuntu_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_18_ubuntu_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:18-ubuntu \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_18_ubuntu_mount"
  
  export CONTAINER_ID_OCI_node_18_ubuntu_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_18_ubuntu_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_18_ubuntu-mount" container "$CONTAINER_ID_OCI_node_18_ubuntu_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_18_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_18_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_18_ubuntu_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-18-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-18-os-ubuntu" executor "oci-node_18_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-18-on-ubuntu ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-18-on-ubuntu (condition: $ACTION_CONDITION)"
else
  _log job "test-node-18-os-ubuntu" action "test-node-18-on-ubuntu" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/jhbv8ks32bsv9frqp4k0mggwics51vwf-test-node-18-on-ubuntu/bin/test-node-18-on-ubuntu
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/jhbv8ks32bsv9frqp4k0mggwics51vwf-test-node-18-on-ubuntu/bin/test-node-18-on-ubuntu 2>&1 | _log_line "test-node-18-os-ubuntu" "test-node-18-on-ubuntu"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-18-os-ubuntu" action "test-node-18-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-18-os-ubuntu" action "test-node-18-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-18-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-node-20-os-alpine() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_20_alpine_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_20_alpine_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:20-alpine \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_20_alpine_mount"
  
  export CONTAINER_ID_OCI_node_20_alpine_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_20_alpine_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_20_alpine-mount" container "$CONTAINER_ID_OCI_node_20_alpine_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_20_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_20_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_20_alpine_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-20-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-20-os-alpine" executor "oci-node_20_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-20-on-alpine ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-20-on-alpine (condition: $ACTION_CONDITION)"
else
  _log job "test-node-20-os-alpine" action "test-node-20-on-alpine" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/8f98h029bfjrnlf75wid1g42ayp6j50l-test-node-20-on-alpine/bin/test-node-20-on-alpine
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/8f98h029bfjrnlf75wid1g42ayp6j50l-test-node-20-on-alpine/bin/test-node-20-on-alpine 2>&1 | _log_line "test-node-20-os-alpine" "test-node-20-on-alpine"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-20-os-alpine" action "test-node-20-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-20-os-alpine" action "test-node-20-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-20-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-node-20-os-ubuntu() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_20_ubuntu_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_20_ubuntu_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:20-ubuntu \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_20_ubuntu_mount"
  
  export CONTAINER_ID_OCI_node_20_ubuntu_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_20_ubuntu_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_20_ubuntu-mount" container "$CONTAINER_ID_OCI_node_20_ubuntu_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_20_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_20_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_20_ubuntu_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-20-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-20-os-ubuntu" executor "oci-node_20_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-20-on-ubuntu ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-20-on-ubuntu (condition: $ACTION_CONDITION)"
else
  _log job "test-node-20-os-ubuntu" action "test-node-20-on-ubuntu" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/2y4saba4rrn36bhgxmp9sa2pl1zisb6k-test-node-20-on-ubuntu/bin/test-node-20-on-ubuntu
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/2y4saba4rrn36bhgxmp9sa2pl1zisb6k-test-node-20-on-ubuntu/bin/test-node-20-on-ubuntu 2>&1 | _log_line "test-node-20-os-ubuntu" "test-node-20-on-ubuntu"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-20-os-ubuntu" action "test-node-20-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-20-os-ubuntu" action "test-node-20-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-20-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-node-22-os-alpine() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_22_alpine_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_22_alpine_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:22-alpine \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_22_alpine_mount"
  
  export CONTAINER_ID_OCI_node_22_alpine_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_22_alpine_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_22_alpine-mount" container "$CONTAINER_ID_OCI_node_22_alpine_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_22_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_22_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_22_alpine_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-22-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-22-os-alpine" executor "oci-node_22_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-22-on-alpine ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-22-on-alpine (condition: $ACTION_CONDITION)"
else
  _log job "test-node-22-os-alpine" action "test-node-22-on-alpine" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/9pf55rxni1rf8vck13r0mmzhnccvxgyj-test-node-22-on-alpine/bin/test-node-22-on-alpine
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/9pf55rxni1rf8vck13r0mmzhnccvxgyj-test-node-22-on-alpine/bin/test-node-22-on-alpine 2>&1 | _log_line "test-node-22-os-alpine" "test-node-22-on-alpine"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-22-os-alpine" action "test-node-22-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-22-os-alpine" action "test-node-22-on-alpine" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-22-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-node-22-os-ubuntu() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_22_ubuntu_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_22_ubuntu_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:22-ubuntu \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_22_ubuntu_mount"
  
  export CONTAINER_ID_OCI_node_22_ubuntu_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_22_ubuntu_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_22_ubuntu-mount" container "$CONTAINER_ID_OCI_node_22_ubuntu_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_22_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_22_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_node_22_ubuntu_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node-22-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node-22-os-ubuntu" executor "oci-node_22_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test-node-22-on-ubuntu ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  '\''always()'\'')
    # Always run
    ;;
  '\''success()'\'')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  '\''failure()'\'')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  '\''cancelled()'\'')
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
  echo "⊘ Skipping test-node-22-on-ubuntu (condition: $ACTION_CONDITION)"
else
  _log job "test-node-22-os-ubuntu" action "test-node-22-on-ubuntu" event "→" "Starting"
  
  # Record start time (use fallback if nanoseconds not available)
  _action_start_ns=$(date +%s%N 2>/dev/null || date +%s)
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process with output wrapping
  set +e
  if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
    # Simple format - pass through unchanged
    /nix/store/2kvwp1khz2y766xs809dzi7912bm4h6r-test-node-22-on-ubuntu/bin/test-node-22-on-ubuntu
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/2kvwp1khz2y766xs809dzi7912bm4h6r-test-node-22-on-ubuntu/bin/test-node-22-on-ubuntu 2>&1 | _log_line "test-node-22-os-ubuntu" "test-node-22-on-ubuntu"
    _action_exit_code=${PIPESTATUS[0]}
  fi
  set -e
  
  # Calculate duration
  _action_end_ns=$(date +%s%N 2>/dev/null || date +%s)
  if echo "$_action_start_ns" | grep -q "N"; then
    # Fallback: seconds only
    _action_duration_s=$((_action_end_ns - _action_start_ns))
    _action_duration_ms=$((_action_duration_s * 1000))
  else
    # Nanoseconds available
    _action_duration_ms=$(( (_action_end_ns - _action_start_ns) / 1000000 ))
    _action_duration_s=$(echo "scale=3; $_action_duration_ms / 1000" | bc 2>/dev/null || echo $((_action_duration_ms / 1000)))
  fi
  
  # Log result and track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    _log job "test-node-22-os-ubuntu" action "test-node-22-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node-22-os-ubuntu" action "test-node-22-on-ubuntu" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-22-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


# Main execution
main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "test-node-18-os-alpine, test-node-18-os-ubuntu, test-node-20-os-alpine, test-node-20-os-ubuntu, test-node-22-os-alpine, test-node-22-os-ubuntu" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-node-18-os-alpine|success()|" \
    "test-node-18-os-ubuntu|success()|" \
    "test-node-20-os-alpine|success()|" \
    "test-node-20-os-ubuntu|success()|" \
    "test-node-22-os-alpine|success()|" \
    "test-node-22-os-ubuntu|success()|" || {
    _log_workflow level 0 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 1 jobs "build-arch-amd64-distro-alpine, build-arch-amd64-distro-debian, build-arch-arm64-distro-alpine, build-arch-arm64-distro-debian" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build-arch-amd64-distro-alpine|success()|" \
    "build-arch-amd64-distro-debian|success()|" \
    "build-arch-arm64-distro-alpine|success()|" \
    "build-arch-arm64-distro-debian|success()|" || {
    _log_workflow level 1 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 2 jobs "deploy" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "deploy|success()|" || {
    _log_workflow level 2 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 3 jobs "summary" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "summary|always()|" || {
    _log_workflow level 3 event "✗" "Level failed"
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
