#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="artifacts-oci-build-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="artifacts-oci-build"

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
job_build() {
  # Setup workspace for this job
  # Mode: BUILD - build custom image with actions
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  # Load custom image
  echo "→ Loading custom OCI image with actions (this may take a while)..."
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker load < /nix/store/219spg29r8nrmwr20fzxzwkv4hs3kffz-nixactions-alpine.tar.gz
  
  # Create and start container from custom image
  CONTAINER_ID_OCI_alpine_build=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    nixactions-alpine:latest)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_alpine_build"
  
  export CONTAINER_ID_OCI_alpine_build
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p /workspace
  
  _log_workflow executor "oci-alpine-build" container "$CONTAINER_ID_OCI_alpine_build" workspace "/workspace" event "→" "Workspace created"
  echo "  Image includes: bash, coreutils, and all action derivations"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow executor "oci-alpine-build" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_alpine_build" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/build"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build" executor "oci-alpine-build" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build ===

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
  echo "⊘ Skipping build (condition: $ACTION_CONDITION)"
else
  _log job "build" action "build" event "→" "Starting"
  
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
    /nix/store/58njqjz0y31qd1p1scwacf2pqafmw5pr-build/bin/build
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/58njqjz0y31qd1p1scwacf2pqafmw5pr-build/bin/build 2>&1 | _log_line "build" "build"
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
    _log job "build" action "build" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "build" action "build" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  # Save artifacts on HOST after job completes
_log_job "build" event "→" "Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" test -e "$JOB_DIR/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
else
  _log_workflow artifact "dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: dist → dist/ (${ARTIFACT_SIZE})"

if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" test -e "$JOB_DIR/myapp"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/myapp" \
    "$NIXACTIONS_ARTIFACTS_DIR/myapp/myapp"
else
  _log_workflow artifact "myapp" path "myapp" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/myapp" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: myapp → myapp (${ARTIFACT_SIZE})"


}


job_test() {
  # Setup workspace for this job
  # Mode: BUILD - build custom image with actions
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  # Load custom image
  echo "→ Loading custom OCI image with actions (this may take a while)..."
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker load < /nix/store/sawxcpcgki7cjpc7yljhp1irfszn9f3f-nixactions-alpine.tar.gz
  
  # Create and start container from custom image
  CONTAINER_ID_OCI_alpine_build=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    nixactions-alpine:latest)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_alpine_build"
  
  export CONTAINER_ID_OCI_alpine_build
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p /workspace
  
  _log_workflow executor "oci-alpine-build" container "$CONTAINER_ID_OCI_alpine_build" workspace "/workspace" event "→" "Workspace created"
  echo "  Image includes: bash, coreutils, and all action derivations"
fi

  
  # Restore artifacts on HOST before executing job
_log_job "test" artifacts "dist myapp" event "→" "Restoring artifacts"
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/dist" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/dist"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/"
    fi
  done
else
  _log_workflow artifact "dist" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "dist" event "✓" "Restored"

if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/myapp" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/myapp"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/"
    fi
  done
else
  _log_workflow artifact "myapp" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "myapp" event "✓" "Restored"


  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow executor "oci-alpine-build" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_alpine_build" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "test" executor "oci-alpine-build" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === test ===

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
  echo "⊘ Skipping test (condition: $ACTION_CONDITION)"
else
  _log job "test" action "test" event "→" "Starting"
  
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
    /nix/store/pqp391wcii15bbcpinkpp62qrib2p0ck-test/bin/test
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/pqp391wcii15bbcpinkpp62qrib2p0ck-test/bin/test 2>&1 | _log_line "test" "test"
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
    _log job "test" action "test" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "test" action "test" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  
}


# Main execution
main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "build" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build|success()|" || {
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

  
  
  
  # Final report
  if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
    _log_workflow failed_jobs "${FAILED_JOBS[*]}" event "✗" "Workflow failed"
    exit 1
  else
    _log_workflow event "✓" "Workflow completed successfully"
  fi
}

main "$@"
