#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="multi-executor-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="multi-executor-demo"
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

job_build-local() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-local"

ACTION_FAILED=false

run_action "build-local" "build-local" "/nix/store/3mfz8nj0a23gz1ljyd8krb71hq3i9c95-build-local/bin/build-local" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-local" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build-local" event "→" "Saving artifacts"
save_local_artifact "local-dist" "dist/" "build-local"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/local-dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: local-dist → dist/ (${ARTIFACT_SIZE})"


}

job_build-oci() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "nixos/nix" "nixos_nix_mount"

  
  if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow executor "oci-nixos_nix-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
   \
  "$CONTAINER_ID_OCI_nixos_nix_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/build-oci"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "build-oci" executor "oci-nixos_nix-mount" workdir "$JOB_DIR" event "▶" "Job starting"

ACTION_FAILED=false

run_action "build-oci" "build-oci" "/nix/store/2a693hkj5784ha08fjdf2fxdhw38qy5d-build-oci/bin/build-oci" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-oci" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  # Save artifacts
_log_job "build-oci" event "→" "Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build-oci"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/oci-dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/oci-dist"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/oci-dist/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/oci-dist/dist/"
else
  _log_workflow artifact "oci-dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/oci-dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: oci-dist → dist/ (${ARTIFACT_SIZE})"


}

job_compare() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "compare" artifacts "local-dist oci-dist" event "→" "Restoring artifacts"
restore_local_artifact "local-dist" "." "compare"

_log_job "compare" artifact "local-dist" path "." event "✓" "Restored"

restore_local_artifact "oci-dist" "." "compare"

_log_job "compare" artifact "oci-dist" path "." event "✓" "Restored"


      setup_local_job "compare"

ACTION_FAILED=false

run_action "compare" "compare-builds" "/nix/store/w3npx31vvcrmwzs3l1dsa1j56hakxfay-compare-builds/bin/compare-builds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "compare" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "build-local, build-oci" event "→" "Starting level"
run_parallel "build-local|success()|" "build-oci|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "compare" event "→" "Starting level"
run_parallel "compare|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
