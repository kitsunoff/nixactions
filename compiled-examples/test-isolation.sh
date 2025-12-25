#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-job-isolation-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-job-isolation"
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

job_job1() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "job1"
export JOB1_VAR=only-in-job1
export WORKFLOW_VAR=shared-across-all-jobs
ACTION_FAILED=false

run_action "job1" "show-job1-env" "/nix/store/hg9kqrqqsaacjjzc2hyalaaxjbdi7lsd-show-job1-env/bin/show-job1-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "job1" "try-to-leak" "/nix/store/d3fh0szypnggjaga302204qly0ygd3b6-try-to-leak/bin/try-to-leak" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "job1" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_job2() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "job2"
export JOB2_VAR=only-in-job2
export WORKFLOW_VAR=shared-across-all-jobs
ACTION_FAILED=false

run_action "job2" "show-job2-env" "/nix/store/h3gpk1zgrknd7yxpivyzj0nba0r0cb7f-show-job2-env/bin/show-job2-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
