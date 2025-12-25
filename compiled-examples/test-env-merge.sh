#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-env-merge-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-env-merge"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/c6a8pgh4xzjl6zc1hglg5l823xfvbdr1-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/1mgqdp33xiddrm2va94abw7l8wdvzz0q-nixactions-runtime/bin/nixactions-runtime

NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

# ============================================
# Environment Provider Execution
# ============================================

# Helper: Execute provider and apply exports
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
  
  # Apply exports - providers always override previous values
  # Runtime environment (already in shell) has highest priority
  local vars_set=0
  local vars_from_runtime=0
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      local key="${BASH_REMATCH[1]}"
      
      # Check if variable was set from runtime (before provider execution started)
      # We detect this by checking if it's in our RUNTIME_ENV_KEYS list
      if [[ " ${RUNTIME_ENV_KEYS} " =~ " ${key} " ]]; then
        # Runtime env has highest priority - skip
        vars_from_runtime=$((vars_from_runtime + 1))
      else
        # Apply provider value (may override previous provider)
        eval "$line"
        vars_set=$((vars_set + 1))
      fi
    fi
  done <<< "$output"
  
  if [ $vars_set -gt 0 ]; then
    _log_workflow provider "$provider_name" vars_set "$vars_set" event "✓" "Variables loaded"
  fi
  if [ $vars_from_runtime -gt 0 ]; then
    _log_workflow provider "$provider_name" vars_from_runtime "$vars_from_runtime" event "⊘" "Variables skipped (runtime override)"
  fi
}

# Execute envFrom providers in order


# Apply workflow-level env (hardcoded, lowest priority)
if [ -z "${LEVEL+x}" ]; then
  export LEVEL=workflow
fi
if [ -z "${VAR_SHARED+x}" ]; then
  export VAR_SHARED=workflow-value
fi
if [ -z "${VAR_WORKFLOW+x}" ]; then
  export VAR_WORKFLOW=from-workflow
fi

# ============================================
# Job Functions
# ============================================

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"
if [ -z "${LEVEL+x}" ]; then
  export LEVEL=workflow
fi
if [ -z "${VAR_SHARED+x}" ]; then
  export VAR_SHARED=workflow-value
fi
if [ -z "${VAR_WORKFLOW+x}" ]; then
  export VAR_WORKFLOW=from-workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "summary" "summary" "/nix/store/lmpyzw4xafql760dji8flj9dxpgdkmv3-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-merge() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-merge"
if [ -z "${LEVEL+x}" ]; then
  export LEVEL=job
fi
if [ -z "${VAR_JOB+x}" ]; then
  export VAR_JOB=from-job
fi
if [ -z "${VAR_SHARED+x}" ]; then
  export VAR_SHARED=job-value
fi
if [ -z "${VAR_WORKFLOW+x}" ]; then
  export VAR_WORKFLOW=from-workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-merge" "test-inheritance" "/nix/store/5ihbi4dfmi0ygibx8g693780xs2rs4a7-test-inheritance/bin/test-inheritance" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables
export LEVEL=action
export VAR_ACTION=from-action
export VAR_SHARED=action-value
# Set retry environment variables

run_action "test-merge" "test-action-override" "/nix/store/7afwra09xdcrwg6gz0i4vpjcyw33mxli-test-action-override/bin/test-action-override" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-merge" "test-runtime-priority" "/nix/store/115ja5q1hl0lhzfc4g16imvzg4cmhl68-test-runtime-priority/bin/test-runtime-priority" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-merge" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_verify-workflow-env() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "verify-workflow-env"
if [ -z "${LEVEL+x}" ]; then
  export LEVEL=workflow
fi
if [ -z "${VAR_SHARED+x}" ]; then
  export VAR_SHARED=workflow-value
fi
if [ -z "${VAR_WORKFLOW+x}" ]; then
  export VAR_WORKFLOW=from-workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "verify-workflow-env" "verify-shared" "/nix/store/gfb9sx6dc81r3ps1yai589a9kv5imix8-verify-shared/bin/verify-shared" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "verify-workflow-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 3 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-merge" event "→" "Starting level"
run_parallel "test-merge|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "verify-workflow-env" event "→" "Starting level"
run_parallel "verify-workflow-env|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "summary" event "→" "Starting level"
run_parallel "summary|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
