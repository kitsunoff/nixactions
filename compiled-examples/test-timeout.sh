#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-timeout-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-timeout"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/c6a8pgh4xzjl6zc1hglg5l823xfvbdr1-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/gnfqpy8dkjijil7y2k7jgx52v7nbc189-nixactions-runtime/bin/nixactions-runtime

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


# ============================================
# Job Functions
# ============================================

job_test-fast-action() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-fast-action"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=5s
run_action "test-fast-action" "fast-action" "/nix/store/difyzmccpdyqrzsh0gcq3kphr7wwy5ln-fast-action/bin/fast-action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-fast-action" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-job-timeout() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-job-timeout"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=5s
run_action "test-job-timeout" "quick-task" "/nix/store/kpb74p876nm8390hrlxw8qi1n7i3m4af-quick-task/bin/quick-task" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-job-timeout" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-no-timeout() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-no-timeout"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=30s
run_action "test-no-timeout" "no-timeout-action" "/nix/store/sajs99l0qx4ywd3d2ssnpb96lxvad3gn-no-timeout-action/bin/no-timeout-action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-no-timeout" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-timeout-action() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-timeout-action"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=2s
run_action "test-timeout-action" "slow-action" "/nix/store/rlj75vk7rd139n9zhgsfdj82nkgvqvkz-slow-action/bin/slow-action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=30s
run_action "test-timeout-action" "verify-timeout" "/nix/store/1ppgwswz480pv20hk906dvzdwp5x1jwm-verify-timeout/bin/verify-timeout" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-timeout-action" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-timeout-formats() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-timeout-formats"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=3s
run_action "test-timeout-formats" "test-seconds" "/nix/store/sm9s1x9gq2n2blig68a86dj6ybi9ihs5-test-seconds/bin/test-seconds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=1m
run_action "test-timeout-formats" "test-minutes" "/nix/store/jf5vspnbdr6j98nr1ak12qb657za6y6c-test-minutes/bin/test-minutes" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables
export NIXACTIONS_TIMEOUT=1h
run_action "test-timeout-formats" "test-hours" "/nix/store/33qlc3nim9g58k90qn8b89scqkwzcgzq-test-hours/bin/test-hours" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-timeout-formats" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-fast-action" event "→" "Starting level"
run_parallel "test-fast-action|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-timeout-action" event "→" "Starting level"
run_parallel "test-timeout-action|success()|1" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-job-timeout" event "→" "Starting level"
run_parallel "test-job-timeout|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "test-no-timeout" event "→" "Starting level"
run_parallel "test-no-timeout|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "test-timeout-formats" event "→" "Starting level"
run_parallel "test-timeout-formats|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
