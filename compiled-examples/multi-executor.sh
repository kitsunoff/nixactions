#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="multi-executor-demo-$(date +%s)-$$"
export WORKFLOW_ID

# Export workflow name for logging
export WORKFLOW_NAME="multi-executor-demo"

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
job_build-local() {
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
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-local"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-local" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-local ===

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
  echo "⊘ Skipping build-local (condition: $ACTION_CONDITION)"
else
  _log job "build-local" action "build-local" event "→" "Starting"
  
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
    /nix/store/3mfz8nj0a23gz1ljyd8krb71hq3i9c95-build-local/bin/build-local
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/3mfz8nj0a23gz1ljyd8krb71hq3i9c95-build-local/bin/build-local 2>&1 | _log_line "build-local" "build-local"
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
    _log job "build-local" action "build-local" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "build-local" action "build-local" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-local" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  # Save artifacts on HOST after job completes
_log_job "build-local" event "→" "Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build-local"
if [ -e "$JOB_DIR/dist/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/local-dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/local-dist"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/local-dist/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/dist/" "$NIXACTIONS_ARTIFACTS_DIR/local-dist/dist/"
else
  _log_workflow artifact "local-dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/local-dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: local-dist → dist/ (${ARTIFACT_SIZE})"


}


job_build-oci() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_nixos_nix_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    nixos/nix \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_nixos_nix_mount"
  
  export CONTAINER_ID_OCI_nixos_nix_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p /workspace
  
  _log_workflow executor "oci-nixos_nix-mount" container "$CONTAINER_ID_OCI_nixos_nix_mount" workspace "/workspace" event "→" "Workspace created"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow executor "oci-nixos_nix-mount" event "✗" "Workspace not initialized"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_nixos_nix_mount" \
  bash -c 'set -uo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/build-oci"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "build-oci" executor "oci-nixos_nix-mount" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build-oci ===

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
  echo "⊘ Skipping build-oci (condition: $ACTION_CONDITION)"
else
  _log job "build-oci" action "build-oci" event "→" "Starting"
  
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
    /nix/store/2a693hkj5784ha08fjdf2fxdhw38qy5d-build-oci/bin/build-oci
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/2a693hkj5784ha08fjdf2fxdhw38qy5d-build-oci/bin/build-oci 2>&1 | _log_line "build-oci" "build-oci"
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
    _log job "build-oci" action "build-oci" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don'\''t exit immediately - let conditions handle flow
  else
    _log job "build-oci" action "build-oci" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-oci" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
  # Save artifacts on HOST after job completes
_log_job "build-oci" event "→" "Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build-oci"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/oci-dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/oci-dist"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/oci-dist/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/oci-dist/dist/"
else
  _log_workflow artifact "oci-dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/oci-dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: oci-dist → dist/ (${ARTIFACT_SIZE})"


}


job_compare() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  _log_workflow executor "local" workspace "$WORKSPACE_DIR_LOCAL" event "→" "Workspace created"
fi

  
  # Restore artifacts on HOST before executing job
_log_job "compare" artifacts "local-dist oci-dist" event "→" "Restoring artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/compare"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/local-dist" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/local-dist"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "local-dist" event "✗" "Artifact not found"
  return 1
fi

_log_job "compare" artifact "local-dist" event "✓" "Restored"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/compare"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/oci-dist" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/oci-dist"/* "$JOB_DIR/" 2>/dev/null || true
else
  _log_workflow artifact "oci-dist" event "✗" "Artifact not found"
  return 1
fi

_log_job "compare" artifact "oci-dist" event "✓" "Restored"


  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/compare"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

_log_job "compare" executor "local" workdir "$JOB_DIR" event "▶" "Job starting"


# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === compare-builds ===

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
  echo "⊘ Skipping compare-builds (condition: $ACTION_CONDITION)"
else
  _log job "compare" action "compare-builds" event "→" "Starting"
  
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
    /nix/store/w3npx31vvcrmwzs3l1dsa1j56hakxfay-compare-builds/bin/compare-builds
    _action_exit_code=$?
  else
    # Structured/JSON format - wrap each line
    /nix/store/w3npx31vvcrmwzs3l1dsa1j56hakxfay-compare-builds/bin/compare-builds 2>&1 | _log_line "compare" "compare-builds"
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
    _log job "compare" action "compare-builds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✗" "Failed"
    # Don't exit immediately - let conditions handle flow
  else
    _log job "compare" action "compare-builds" duration "${_action_duration_s}s" exit_code $_action_exit_code event "✓" "Completed"
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "compare" event "✗" "Job failed due to action failures"
  exit 1
fi

  
  
}


# Main execution
main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  
  # Execute level by level
  _log_workflow level 0 jobs "build-local, build-oci" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build-local|success()|" \
    "build-oci|success()|" || {
    _log_workflow level 0 event "✗" "Level failed"
    exit 1
  }


_log_workflow level 1 jobs "compare" event "→" "Starting level"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "compare|success()|" || {
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
