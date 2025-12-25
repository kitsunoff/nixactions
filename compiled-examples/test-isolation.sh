#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-job-isolation-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-job-isolation"
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
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=shared-across-all-jobs
fi

# ============================================
# Job Functions
# ============================================

job_job1() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "job1"
if [ -z "${JOB1_VAR+x}" ]; then
  export JOB1_VAR=only-in-job1
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=shared-across-all-jobs
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "job1" "show-job1-env" "/nix/store/fwn37aw66z7298lj3q1svcwb8kqh4qyr-show-job1-env/bin/show-job1-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "job1" "try-to-leak" "/nix/store/walpcavxidfgjrq86hwzqzqabd7ajg87-try-to-leak/bin/try-to-leak" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "job1" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_job2() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "job2"
if [ -z "${JOB2_VAR+x}" ]; then
  export JOB2_VAR=only-in-job2
fi
if [ -z "${WORKFLOW_VAR+x}" ]; then
  export WORKFLOW_VAR=shared-across-all-jobs
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "job2" "show-job2-env" "/nix/store/cqhb6aa3nqd4f5hn8ck83xl94zbrk2cv-show-job2-env/bin/show-job2-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "job2" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "job1" event "→" "Starting level"
run_parallel "job1|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "job2" event "→" "Starting level"
run_parallel "job2|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
