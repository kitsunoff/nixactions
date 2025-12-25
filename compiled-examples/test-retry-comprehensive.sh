#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-retry-comprehensive-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-retry-comprehensive"
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

job_test-action-overrides-job() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-action-overrides-job"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=10
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-action-overrides-job" "overrides-job-retry" "/nix/store/xs1hs05j7wwlpxnq9i42fy8x15cr1949-overrides-job-retry/bin/overrides-job-retry" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-action-overrides-job" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-constant-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-constant-success"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=constant
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=2
export RETRY_MIN_TIME=2
# Set timeout environment variables

run_action "test-constant-success" "constant-backoff-success" "/nix/store/hndzy0p8rgaq212qad5nzgpi7w09ssan-constant-backoff-success/bin/constant-backoff-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-constant-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-exponential-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-exponential-success"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=60
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-exponential-success" "exponential-backoff-success" "/nix/store/ki08qf57fy91qlsn9vl7yl3l3szsg9gn-exponential-backoff-success/bin/exponential-backoff-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-exponential-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-job-level-retry() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-job-level-retry"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=constant
export RETRY_MAX_ATTEMPTS=2
export RETRY_MAX_TIME=1
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-job-level-retry" "inherits-job-retry" "/nix/store/6glgfq6gw73xysrvjliknxbwri99bcfw-inherits-job-retry/bin/inherits-job-retry" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-job-level-retry" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-linear-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-linear-success"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=linear
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=30
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-linear-success" "linear-backoff-success" "/nix/store/y24j9ckm4kgppkb4mb0aqmai28cgnj3w-linear-backoff-success/bin/linear-backoff-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-linear-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-max-delay-cap() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-max-delay-cap"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=5
export RETRY_MAX_TIME=5
export RETRY_MIN_TIME=10
# Set timeout environment variables

run_action "test-max-delay-cap" "max-delay-capped" "/nix/store/1wc0vs2r3xy7gxgm6pi3h0v36w72dn5b-max-delay-capped/bin/max-delay-capped" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-max-delay-cap" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-no-retry-single-attempt() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-no-retry-single-attempt"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-no-retry-single-attempt" "single-attempt-success" "/nix/store/d0n22rj31gp5a2irm3y8d0rjslawacqs-single-attempt-success/bin/single-attempt-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-no-retry-single-attempt" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-retry-disabled() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-retry-disabled"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-retry-disabled" "no-retry-action" "/nix/store/gw8hd3vps648vyz73c7gxxln8c4fv06y-no-retry-action/bin/no-retry-action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-retry-disabled" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-retry-exhausted() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-retry-exhausted"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=10
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-retry-exhausted" "always-fails" "/nix/store/1ybfxcghzq0p0dncxg1ih6969kscmwja-always-fails/bin/always-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-retry-exhausted" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-timing-verification() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-timing-verification"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=60
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test-timing-verification" "verify-exponential-timing" "/nix/store/hy99gpbbs4px2am43hp8q1jy43rp6vch-verify-exponential-timing/bin/verify-exponential-timing" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-timing-verification" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 10 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-exponential-success" event "→" "Starting level"
run_parallel "test-exponential-success|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-linear-success" event "→" "Starting level"
run_parallel "test-linear-success|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-constant-success" event "→" "Starting level"
run_parallel "test-constant-success|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "test-retry-exhausted" event "→" "Starting level"
run_parallel "test-retry-exhausted|success()|1" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "test-no-retry-single-attempt" event "→" "Starting level"
run_parallel "test-no-retry-single-attempt|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

_log_workflow level 5 jobs "test-retry-disabled" event "→" "Starting level"
run_parallel "test-retry-disabled|success()|" || {
  _log_workflow level 5 event "✗" "Level failed"
  exit 1
}

_log_workflow level 6 jobs "test-max-delay-cap" event "→" "Starting level"
run_parallel "test-max-delay-cap|success()|" || {
  _log_workflow level 6 event "✗" "Level failed"
  exit 1
}

_log_workflow level 7 jobs "test-job-level-retry" event "→" "Starting level"
run_parallel "test-job-level-retry|success()|" || {
  _log_workflow level 7 event "✗" "Level failed"
  exit 1
}

_log_workflow level 8 jobs "test-action-overrides-job" event "→" "Starting level"
run_parallel "test-action-overrides-job|success()|" || {
  _log_workflow level 8 event "✗" "Level failed"
  exit 1
}

_log_workflow level 9 jobs "test-timing-verification" event "→" "Starting level"
run_parallel "test-timing-verification|success()|" || {
  _log_workflow level 9 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
