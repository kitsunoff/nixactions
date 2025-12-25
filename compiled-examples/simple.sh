#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="simple-workflow-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="simple-workflow"
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

job_hello() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "hello"

ACTION_FAILED=false

run_action "hello" "checkout" "/nix/store/gr7399jp3asx13zaq86bcqf6nw2lkvzj-checkout/bin/checkout" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "hello" "greet" "/nix/store/1ary6kliahmm7iv8fla4abp89jq7vqkf-greet/bin/greet" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "hello" "system-info" "/nix/store/c804kwj18280ag1xal76z5hp5y1g2jix-system-info/bin/system-info" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "hello" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 1 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "hello" event "→" "Starting level"
run_parallel "hello|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
