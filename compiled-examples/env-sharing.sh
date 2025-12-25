#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="env-sharing-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="env-sharing-demo"
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

job_build() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build"

ACTION_FAILED=false

run_action "build" "generate-version" "/nix/store/vbygxvra2ivhrnw3pklcvagarvaavsvf-generate-version/bin/generate-version" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build" "build-app" "/nix/store/9204zsym02mx6qcid6pmrw3an037j12h-build-app/bin/build-app" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build" "verify-build" "/nix/store/bqkkiblgyd3giajal0sr8xkbgbx6z7h2-verify-build/bin/verify-build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "build-info" "dist/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-info" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-info → dist/ (${ARTIFACT_SIZE})"


}

job_calculate() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "calculate" artifacts "build-info" event "→" "Restoring artifacts"
restore_local_artifact "build-info" "." "calculate"

_log_job "calculate" artifact "build-info" path "." event "✓" "Restored"


      setup_local_job "calculate"

ACTION_FAILED=false

run_action "calculate" "multi-step-calculation" "/nix/store/gm7kib0nz7vlw2zdjkrffbw4r695rgjs-multi-step-calculation/bin/multi-step-calculation" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "calculate" "use-calculations" "/nix/store/59d7gvas6synqwm7v0nrhd6lg6lh51iz-use-calculations/bin/use-calculations" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "calculate" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"

ACTION_FAILED=false

run_action "summary" "summary" "/nix/store/gd686fl8iipxm7jsbj1zh46jvxihywng-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-advanced() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-advanced" artifacts "build-info" event "→" "Restoring artifacts"
restore_local_artifact "build-info" "." "test-advanced"

_log_job "test-advanced" artifact "build-info" path "." event "✓" "Restored"


      setup_local_job "test-advanced"

ACTION_FAILED=false

run_action "test-advanced" "parse-build-info" "/nix/store/3lr6kic0yxf03c57zimzdz88qx101bsp-parse-build-info/bin/parse-build-info" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-advanced" "use-parsed-version" "/nix/store/9k9kakvp0g16zpxv6i8c0kil97gzd1w6-use-parsed-version/bin/use-parsed-version" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-advanced" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 3 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "build" event "→" "Starting level"
run_parallel "build|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "calculate, test-advanced" event "→" "Starting level"
run_parallel "calculate|success()|" "test-advanced|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "summary" event "→" "Starting level"
run_parallel "summary|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
