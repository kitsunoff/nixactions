#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="docker-ci-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="docker-ci"

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
job_build-docker-image() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-docker-image"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-docker-image" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export PROJECT_NAME=hello-docker

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === create-dockerfile ===

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
  echo "⊘ Skipping create-dockerfile (condition: $ACTION_CONDITION)"
else
  _log job "build-docker-image" action "create-dockerfile" event "→" "Starting"
  
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
    /nix/store/rlsm5c8717kdpqdjgkhjsxjzmp1c3mhn-create-dockerfile/bin/create-dockerfile
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/rlsm5c8717kdpqdjgkhjsxjzmp1c3mhn-create-dockerfile/bin/create-dockerfile 2>&1 | _log_line "build-docker-image" "create-dockerfile"
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
    _log job "build-docker-image" action "create-dockerfile" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-docker-image" action "create-dockerfile" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === build-image ===

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
  echo "⊘ Skipping build-image (condition: $ACTION_CONDITION)"
else
  _log job "build-docker-image" action "build-image" event "→" "Starting"
  
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
    /nix/store/kdmykpzj7rb7vhj9qjny1cj94wymk717-build-image/bin/build-image
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/kdmykpzj7rb7vhj9qjny1cj94wymk717-build-image/bin/build-image 2>&1 | _log_line "build-docker-image" "build-image"
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
    _log job "build-docker-image" action "build-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-docker-image" action "build-image" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-docker-image" event "✗" "Job failed due to action failures"
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
export PROJECT_NAME=hello-docker

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === summary ===

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
  echo "⊘ Skipping summary (condition: $ACTION_CONDITION)"
else
  _log job "summary" action "summary" event "→" "Starting"
  
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
    /nix/store/i6rjxpjfpykj70f6h7y0nil31nv4bfgl-summary/bin/summary
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/i6rjxpjfpykj70f6h7y0nil31nv4bfgl-summary/bin/summary 2>&1 | _log_line "summary" "summary"
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
    _log job "summary" action "summary" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "summary" action "summary" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-node() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_node_20_slim_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_node_20_slim_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    node:20-slim \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_node_20_slim_mount"
  
  export CONTAINER_ID_OCI_node_20_slim_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_node_20_slim_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-node_20_slim-mount" container "$CONTAINER_ID_OCI_node_20_slim_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_node_20_slim_mount:-}" ]; then
  _log_workflow executor "oci-node_20_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_node_20_slim_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-node"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-node" executor "oci-node_20_slim-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export PROJECT_NAME=hello-docker

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === check-node ===

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
  echo "⊘ Skipping check-node (condition: $ACTION_CONDITION)"
else
  _log job "test-node" action "check-node" event "→" "Starting"
  
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
    /nix/store/ms95p0j4z3xa9gx8sccr1p60fdljvpa4-check-node/bin/check-node
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/ms95p0j4z3xa9gx8sccr1p60fdljvpa4-check-node/bin/check-node 2>&1 | _log_line "test-node" "check-node"
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
    _log job "test-node" action "check-node" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node" action "check-node" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === run-javascript ===

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
  echo "⊘ Skipping run-javascript (condition: $ACTION_CONDITION)"
else
  _log job "test-node" action "run-javascript" event "→" "Starting"
  
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
    /nix/store/g8d8b6cy6hwmamjlxxqdf5b7gimqlrsq-run-javascript/bin/run-javascript
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/g8d8b6cy6hwmamjlxxqdf5b7gimqlrsq-run-javascript/bin/run-javascript 2>&1 | _log_line "test-node" "run-javascript"
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
    _log job "test-node" action "run-javascript" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-node" action "run-javascript" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-python() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_python_3.11_slim_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_python_3.11_slim_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    python:3.11-slim \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_python_3.11_slim_mount"
  
  export CONTAINER_ID_OCI_python_3.11_slim_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_python_3.11_slim_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-python_3.11_slim-mount" container "$CONTAINER_ID_OCI_python_3.11_slim_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_python_3.11_slim_mount:-}" ]; then
  _log_workflow executor "oci-python_3.11_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_python_3.11_slim_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-python"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-python" executor "oci-python_3.11_slim-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export PROJECT_NAME=hello-docker

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === check-environment ===

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
  echo "⊘ Skipping check-environment (condition: $ACTION_CONDITION)"
else
  _log job "test-python" action "check-environment" event "→" "Starting"
  
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
    /nix/store/3fx56082dn4ri2svs6vllqlyx6x4f3by-check-environment/bin/check-environment
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/3fx56082dn4ri2svs6vllqlyx6x4f3by-check-environment/bin/check-environment 2>&1 | _log_line "test-python" "check-environment"
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
    _log job "test-python" action "check-environment" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-python" action "check-environment" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === run-python-code ===

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
  echo "⊘ Skipping run-python-code (condition: $ACTION_CONDITION)"
else
  _log job "test-python" action "run-python-code" event "→" "Starting"
  
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
    /nix/store/2ygvnsmdcq2c31slma1f00rdmbjynd2r-run-python-code/bin/run-python-code
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/2ygvnsmdcq2c31slma1f00rdmbjynd2r-run-python-code/bin/run-python-code 2>&1 | _log_line "test-python" "run-python-code"
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
    _log job "test-python" action "run-python-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-python" action "run-python-code" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-python" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


job_test-ubuntu() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_ubuntu_22.04_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_ubuntu_22.04_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    ubuntu:22.04 \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_ubuntu_22.04_mount"
  
  export CONTAINER_ID_OCI_ubuntu_22.04_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_ubuntu_22.04_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-ubuntu_22.04-mount" container "$CONTAINER_ID_OCI_ubuntu_22.04_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_ubuntu_22.04_mount:-}" ]; then
  _log_workflow executor "oci-ubuntu_22.04-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_ubuntu_22.04_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test-ubuntu" executor "oci-ubuntu_22.04-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment
export PROJECT_NAME=hello-docker

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === system-info ===

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
  echo "⊘ Skipping system-info (condition: $ACTION_CONDITION)"
else
  _log job "test-ubuntu" action "system-info" event "→" "Starting"
  
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
    /nix/store/bz7dxkc21p4fl4xr9ykidaclib7j34ng-system-info/bin/system-info
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/bz7dxkc21p4fl4xr9ykidaclib7j34ng-system-info/bin/system-info 2>&1 | _log_line "test-ubuntu" "system-info"
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
    _log job "test-ubuntu" action "system-info" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-ubuntu" action "system-info" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# === install-and-run ===

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
  echo "⊘ Skipping install-and-run (condition: $ACTION_CONDITION)"
else
  _log job "test-ubuntu" action "install-and-run" event "→" "Starting"
  
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
    /nix/store/hd5kifgqaqcc0681ixcwy07p1gqsklx4-install-and-run/bin/install-and-run
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/hd5kifgqaqcc0681ixcwy07p1gqsklx4-install-and-run/bin/install-and-run 2>&1 | _log_line "test-ubuntu" "install-and-run"
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
    _log job "test-ubuntu" action "install-and-run" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test-ubuntu" action "install-and-run" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


# Main execution
main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "test-node, test-python" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-node|success()|" \
    "test-python|success()|" || {
    _log_workflow level 0 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 1 jobs "test-ubuntu" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-ubuntu|success()|" || {
    _log_workflow level 1 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 2 jobs "build-docker-image" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build-docker-image|success()|" || {
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
