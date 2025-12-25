#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="structured-logging-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="structured-logging-demo"
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

job_test() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"

ACTION_FAILED=false

run_action "test" "checkout" "/nix/store/2krqy1vnpzq5hg9fbxyrpkfhgb9znvrn-checkout/bin/checkout" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "install-deps" "/nix/store/m9sknx1wm251l49srkpjgi35wg5myij4-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "run-tests" "/nix/store/021zbpvims9hahjn0lfsxz9s13q1n2rj-run-tests/bin/run-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 1 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test" event "→" "Starting level"
run_parallel "test|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
