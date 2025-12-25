#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="example-retry-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="example-retry"
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

job_test-constant() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-constant"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=constant
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=3
export RETRY_MIN_TIME=3
# Set timeout environment variables

run_action "test-constant" "constant-backoff" "/nix/store/ym9q7pf7576zaz0lb7g43l0x0lsy16cb-constant-backoff/bin/constant-backoff" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-constant" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-exponential() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-exponential"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=60
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-exponential" "fail-twice-then-succeed" "/nix/store/307q3sdp3wgw03kp0xd59jyfmc4ch122-fail-twice-then-succeed/bin/fail-twice-then-succeed" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-exponential" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-linear() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-linear"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=linear
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=10
export RETRY_MIN_TIME=2
# Set timeout environment variables

run_action "test-linear" "fail-once-with-linear-backoff" "/nix/store/pha8jmrc9wgxdvapizmn89l7da1ngdv6-fail-once-with-linear-backoff/bin/fail-once-with-linear-backoff" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-linear" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-max-attempts-one() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-max-attempts-one"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-max-attempts-one" "single-attempt" "/nix/store/x37s7zmklin84nvcpfb2gykf7fxa4qxi-single-attempt/bin/single-attempt" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-max-attempts-one" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-no-retry() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-no-retry"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=2
export RETRY_MAX_TIME=30
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-no-retry" "no-retry-success" "/nix/store/3326xbx301xida810w0dyifh5rnl8js1-no-retry-success/bin/no-retry-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-no-retry" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-exponential" event "→" "Starting level"
run_parallel "test-exponential|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-linear" event "→" "Starting level"
run_parallel "test-linear|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-constant" event "→" "Starting level"
run_parallel "test-constant|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "test-no-retry" event "→" "Starting level"
run_parallel "test-no-retry|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "test-max-attempts-one" event "→" "Starting level"
run_parallel "test-max-attempts-one|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
