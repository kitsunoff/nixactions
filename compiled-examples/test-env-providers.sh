#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-env-providers-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-env-providers"
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
# Capture runtime environment keys (highest priority)
RUNTIME_ENV_KEYS=$(compgen -e | tr '\n' ' ')

_log_workflow event "→" "Loading environment from providers"
run_provider "/nix/store/fhqm3a9y2cc5r7sp07qxsip7wsylix2z-env-provider-static/bin/$(ls /nix/store/fhqm3a9y2cc5r7sp07qxsip7wsylix2z-env-provider-static/bin | head -1)"

run_provider "/nix/store/jyj04kbx8yh8f82kvnpq59jqaprafabz-env-provider-file/bin/$(ls /nix/store/jyj04kbx8yh8f82kvnpq59jqaprafabz-env-provider-file/bin | head -1)"

run_provider "/nix/store/j2i5ln0nfd3yg7wapb6hsi6ighaq7nz9-env-provider-required/bin/$(ls /nix/store/j2i5ln0nfd3yg7wapb6hsi6ighaq7nz9-env-provider-required/bin | head -1)"

_log_workflow event "✓" "Environment loaded"


# Apply workflow-level env (hardcoded, lowest priority)
if [ -z "${SHARED_VAR+x}" ]; then
  export SHARED_VAR=workflow_priority
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=from_workflow
fi

# ============================================
# Job Functions
# ============================================

job_test-priority() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-priority"
if [ -z "${SHARED_VAR+x}" ]; then
  export SHARED_VAR=workflow_priority
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=from_workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-priority" "show-environment" "/nix/store/ivqcva0ajfi87p0xg8h62mi629swqqcn-show-environment/bin/show-environment" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-priority" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-required() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-required"
if [ -z "${SHARED_VAR+x}" ]; then
  export SHARED_VAR=workflow_priority
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=from_workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-required" "test-required-validation" "/nix/store/v01dxvljfl2j3y0ksab0k7rsd736zr88-test-required-validation/bin/test-required-validation" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-required" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-runtime-override() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-runtime-override"
if [ -z "${JOB_VAR+x}" ]; then
  export JOB_VAR=from_job
fi
if [ -z "${SHARED_VAR+x}" ]; then
  export SHARED_VAR=should_be_file_priority
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=from_workflow
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-runtime-override" "test-job-env" "/nix/store/i9nb1rqpj5fqnai43fzphh8pjlr5fp9f-test-job-env/bin/test-job-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-runtime-override" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 3 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-priority" event "→" "Starting level"
run_parallel "test-priority|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-required" event "→" "Starting level"
run_parallel "test-required|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-runtime-override" event "→" "Starting level"
run_parallel "test-runtime-override|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
