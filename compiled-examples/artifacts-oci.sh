#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="artifacts-simple-oci-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="artifacts-simple-oci"
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
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/zykjlvbsxgafrj0j52rsiwg67piyh9hj-nixactions-oci-executor/bin/nixactions-oci-executor
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
JOB_DIR="/workspace/jobs/build"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "build" executor "oci-nixos_nix-mount" workdir "$JOB_DIR" event "▶" "Job starting"

ACTION_FAILED=false

run_action "build" "build" "/nix/store/vg6djpdrsax8wz5jssvjva7bgx551vn7-build/bin/build" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
else
  _log_workflow artifact "dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: dist → dist/ (${ARTIFACT_SIZE})"

if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/myapp"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/myapp" \
    "$NIXACTIONS_ARTIFACTS_DIR/myapp/myapp"
else
  _log_workflow artifact "myapp" path "myapp" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/myapp" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: myapp → myapp (${ARTIFACT_SIZE})"


}

job_test() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/zykjlvbsxgafrj0j52rsiwg67piyh9hj-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "nixos/nix" "nixos_nix_mount"

  # Restore artifacts
_log_job "test" artifacts "dist myapp" event "→" "Restoring artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/dist" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/dist"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/"
    fi
  done
else
  _log_workflow artifact "dist" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "dist" event "✓" "Restored"

if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/myapp" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/myapp"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/"
    fi
  done
else
  _log_workflow artifact "myapp" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "myapp" event "✓" "Restored"


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
JOB_DIR="/workspace/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test" executor "oci-nixos_nix-mount" workdir "$JOB_DIR" event "▶" "Job starting"

ACTION_FAILED=false

run_action "test" "test" "/nix/store/pfbs6ccripni4pmq8ll9x1c34am6zxpv-test/bin/test" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
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
