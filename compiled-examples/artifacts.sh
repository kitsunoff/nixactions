#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="artifacts-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="artifacts-demo"
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

run_action "build" "build" "/nix/store/gl905c346bxjxkq3p6cibhsppyyffg1i-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "backend" "dist/backend/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/backend" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: backend → dist/backend/ (${ARTIFACT_SIZE})"

save_local_artifact "binary" "myapp" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/binary" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: binary → myapp (${ARTIFACT_SIZE})"

save_local_artifact "frontend" "dist/frontend/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/frontend" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: frontend → dist/frontend/ (${ARTIFACT_SIZE})"

save_local_artifact "release" "target/release/app" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/release" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: release → target/release/app (${ARTIFACT_SIZE})"


}

job_test-custom() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-custom" artifacts "frontend backend" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "public/" "test-custom"

_log_job "test-custom" artifact "frontend" path "public/" event "✓" "Restored"

restore_local_artifact "backend" "server/" "test-custom"

_log_job "test-custom" artifact "backend" path "server/" event "✓" "Restored"


      setup_local_job "test-custom"

ACTION_FAILED=false

run_action "test-custom" "test-custom" "/nix/store/2da4mxb4lq6zsz0lln5rcj3mhyl7fv8n-test-custom/bin/test-custom" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-custom" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-default() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-default" artifacts "frontend backend" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "." "test-default"

_log_job "test-default" artifact "frontend" path "." event "✓" "Restored"

restore_local_artifact "backend" "." "test-default"

_log_job "test-default" artifact "backend" path "." event "✓" "Restored"


      setup_local_job "test-default"

ACTION_FAILED=false

run_action "test-default" "test-default" "/nix/store/zx98yqj0b2yjjc3fm2jnrxg9lxa01b9c-test-default/bin/test-default" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-default" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-mixed() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-mixed" artifacts "binary release" event "→" "Restoring artifacts"
restore_local_artifact "binary" "." "test-mixed"

_log_job "test-mixed" artifact "binary" path "." event "✓" "Restored"

restore_local_artifact "release" "bin/" "test-mixed"

_log_job "test-mixed" artifact "release" path "bin/" event "✓" "Restored"


      setup_local_job "test-mixed"

ACTION_FAILED=false

run_action "test-mixed" "test-mixed" "/nix/store/z1f09kanjxjsqz5gz0hww2y41bb8pagl-test-mixed/bin/test-mixed" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-mixed" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "validate" artifacts "frontend backend binary release" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "." "validate"

_log_job "validate" artifact "frontend" path "." event "✓" "Restored"

restore_local_artifact "backend" "." "validate"

_log_job "validate" artifact "backend" path "." event "✓" "Restored"

restore_local_artifact "binary" "." "validate"

_log_job "validate" artifact "binary" path "." event "✓" "Restored"

restore_local_artifact "release" "." "validate"

_log_job "validate" artifact "release" path "." event "✓" "Restored"


      setup_local_job "validate"

ACTION_FAILED=false

run_action "validate" "validate" "/nix/store/x50gagnpayd7d487ncwq3m268lv1dp4q-validate/bin/validate" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "validate" event "✗" "Job failed due to action failures"
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

_log_workflow level 1 jobs "test-custom, test-default, test-mixed" event "→" "Starting level"
run_parallel "test-custom|success()|" "test-default|success()|" "test-mixed|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "validate" event "→" "Starting level"
run_parallel "validate|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
