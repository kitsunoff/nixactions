#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="nix-shell-example-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="nix-shell-example"
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

job_api-test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "api-test"

ACTION_FAILED=false

run_action "api-test" "nix-shell" "/nix/store/k0jna9l5y7ifdkjqi5phrydxv2kza47v-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "api-test" "Fetch and parse GitHub API" "/nix/store/scizx11650j270ls7lv38gqk1s27xr2r-Fetch-and-parse-GitHub-API/bin/'Fetch and parse GitHub API'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "api-test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_file-processing() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "file-processing"

ACTION_FAILED=false

run_action "file-processing" "nix-shell" "/nix/store/1sl7jy5qpsi29z65zkmjgqixz4p5ay2m-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "file-processing" "Process files" "/nix/store/3mhzriwqwpyjndb2gdkdi2h7vszj9np5-Process-files/bin/'Process files'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "file-processing" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_multi-tool() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "multi-tool"

ACTION_FAILED=false

run_action "multi-tool" "nix-shell" "/nix/store/a8ljl1nvp9mfag7hj2wg6707dszmgp0g-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "multi-tool" "Use git and tree" "/nix/store/57j7sg6v9i93zgx9h4q03bj20lib2ngj-Use-git-and-tree/bin/'Use git and tree'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "multi-tool" "nix-shell" "/nix/store/mlbpb2x3f1zyd0jkal98a0aiy7wz7a7i-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "multi-tool" "System tools available" "/nix/store/iv8ly79hbb20rhis93fs6qzf6f8412z5-System-tools-available/bin/'System tools available'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "multi-tool" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "api-test, file-processing" event "→" "Starting level"
run_parallel "api-test|success()|" "file-processing|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "multi-tool" event "→" "Starting level"
run_parallel "multi-tool|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
