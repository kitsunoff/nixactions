#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-env-propagation-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-env-propagation"
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

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"

ACTION_FAILED=false

run_action "summary" "summary" "/nix/store/a296n1ffz7q6vfw8i8rpjkhcr9damci8-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-export-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-export-vars"

ACTION_FAILED=false

run_action "test-export-vars" "without-export" "/nix/store/q867yz66gihkra0i5g7428yskrf2z7yk-without-export/bin/without-export" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-export-vars" "with-export" "/nix/store/bjr17v5jvxiil7ynwljimzy0q1s80kjs-with-export/bin/with-export" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-export-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-local-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-local-vars"

ACTION_FAILED=false

run_action "test-local-vars" "set-local-var" "/nix/store/6gbmihjanx4lvyr2x381rlq52zy01fc3-set-local-var/bin/set-local-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-local-vars" "try-use-local" "/nix/store/5rkdpb1sdkq2zsy5gnag7fypklpi0y7k-try-use-local/bin/try-use-local" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-local-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-regular-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-regular-vars"

ACTION_FAILED=false

run_action "test-regular-vars" "set-regular-var" "/nix/store/c6wj4s3ps05m2sqx5n3j7p5v92r7h87s-set-regular-var/bin/set-regular-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-regular-vars" "use-regular-var" "/nix/store/vn7vpg4sqndyicbkkl7g3lg8r15ag59w-use-regular-var/bin/use-regular-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-regular-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-regular-vars" event "→" "Starting level"
run_parallel "test-regular-vars|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-local-vars" event "→" "Starting level"
run_parallel "test-local-vars|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-export-vars" event "→" "Starting level"
run_parallel "test-export-vars|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "summary" event "→" "Starting level"
run_parallel "summary|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
