#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="artifacts-paths-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="artifacts-paths"
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

run_action "build" "build" "/nix/store/p50sas9887lp1h8qwbqd5nrf1qmqw2w5-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "build-artifacts" "build/dist/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-artifacts → build/dist/ (${ARTIFACT_SIZE})"

save_local_artifact "release-binary" "target/release/myapp" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/release-binary" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: release-binary → target/release/myapp (${ARTIFACT_SIZE})"


}

job_test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test" artifacts "release-binary build-artifacts" event "→" "Restoring artifacts"
restore_local_artifact "release-binary" "." "test"

_log_job "test" artifact "release-binary" path "." event "✓" "Restored"

restore_local_artifact "build-artifacts" "." "test"

_log_job "test" artifact "build-artifacts" path "." event "✓" "Restored"


      setup_local_job "test"

ACTION_FAILED=false

run_action "test" "test" "/nix/store/bfcvrbfgkdq982hfkzmrgikly5lyr1zf-test/bin/test" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "build" event "→" "Starting level"
run_parallel "build|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test" event "→" "Starting level"
run_parallel "test|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
