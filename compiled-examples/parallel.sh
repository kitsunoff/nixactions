#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="parallel-workflow-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="parallel-workflow"
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

job_analyze() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "analyze"

ACTION_FAILED=false

run_action "analyze" "analyze-structure" "/nix/store/a2ak0h8wdfp4iibrl11yv8vlpvpm4jz3-analyze-structure/bin/analyze-structure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "analyze" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_check-nix() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "check-nix"

ACTION_FAILED=false

run_action "check-nix" "check-nix-formatting" "/nix/store/fm5n0rl31ks38gq1nwd9qa7ld7wkigfy-check-nix-formatting/bin/check-nix-formatting" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "check-nix" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint-shell() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint-shell"

ACTION_FAILED=false

run_action "lint-shell" "lint-shell-scripts" "/nix/store/3wzdxlhrmm0d13zzjp070az4sjg4qcrx-lint-shell-scripts/bin/lint-shell-scripts" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint-shell" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_report() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "report"

ACTION_FAILED=false

run_action "report" "final-report" "/nix/store/wrmfjnx36rfbs259zn9z4hi9z2500m3k-final-report/bin/final-report" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "report" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "analyze, check-nix, lint-shell" event "→" "Starting level"
run_parallel "analyze|success()|" "check-nix|success()|" "lint-shell|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "report" event "→" "Starting level"
run_parallel "report|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
