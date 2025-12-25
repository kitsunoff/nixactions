#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="example-retry-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="example-retry"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/p95kzip1952gbhfggns20djl5fwgs5sk-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/1mgqdp33xiddrm2va94abw7l8wdvzz0q-nixactions-runtime/bin/nixactions-runtime

NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

job_test-constant() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-constant"

ACTION_FAILED=false
export RETRY_BACKOFF=constant
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=3
export RETRY_MIN_TIME=3
run_action "test-constant" "constant-backoff" "/nix/store/qjfppfxn6lbzji2qc3si9fb96i7krvh8-constant-backoff/bin/constant-backoff" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=60
export RETRY_MIN_TIME=1
run_action "test-exponential" "fail-twice-then-succeed" "/nix/store/8j3fsfdi49isfdrzgazpvmk9k2b50nxk-fail-twice-then-succeed/bin/fail-twice-then-succeed" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
export RETRY_BACKOFF=linear
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=10
export RETRY_MIN_TIME=2
run_action "test-linear" "fail-once-with-linear-backoff" "/nix/store/kyzl0zsfyxl5qq4jpr732glfl9wjxxra-fail-once-with-linear-backoff/bin/fail-once-with-linear-backoff" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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

run_action "test-max-attempts-one" "single-attempt" "/nix/store/r8qaf38fklypwl2c0yga3kcckm2h0n8g-single-attempt/bin/single-attempt" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=2
export RETRY_MAX_TIME=30
export RETRY_MIN_TIME=1
run_action "test-no-retry" "no-retry-success" "/nix/store/qdnl91i5rj7kb1hpwa00fbqlqrzsmjjk-no-retry-success/bin/no-retry-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
