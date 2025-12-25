#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="docker-ci-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="docker-ci"
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

job_build-docker-image() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-docker-image"
export PROJECT_NAME=hello-docker
ACTION_FAILED=false

run_action "build-docker-image" "create-dockerfile" "/nix/store/rlsm5c8717kdpqdjgkhjsxjzmp1c3mhn-create-dockerfile/bin/create-dockerfile" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build-docker-image" "build-image" "/nix/store/kdmykpzj7rb7vhj9qjny1cj94wymk717-build-image/bin/build-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-docker-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_summary() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"
export PROJECT_NAME=hello-docker
ACTION_FAILED=false

run_action "summary" "summary" "/nix/store/i6rjxpjfpykj70f6h7y0nil31nv4bfgl-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-node() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/zykjlvbsxgafrj0j52rsiwg67piyh9hj-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:20-slim" "node_20_slim_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_20_slim_mount:-}" ]; then
  _log_workflow executor "oci-node_20_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_node_20_slim_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node" executor "oci-node_20_slim-mount" workdir "$JOB_DIR" event "▶" "Job starting"
export PROJECT_NAME=hello-docker
ACTION_FAILED=false

run_action "test-node" "check-node" "/nix/store/ms95p0j4z3xa9gx8sccr1p60fdljvpa4-check-node/bin/check-node" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''


run_action "test-node" "run-javascript" "/nix/store/g8d8b6cy6hwmamjlxxqdf5b7gimqlrsq-run-javascript/bin/run-javascript" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-python() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/zykjlvbsxgafrj0j52rsiwg67piyh9hj-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "python:3.11-slim" "python_3.11_slim_mount"

  
  if [ -z "${CONTAINER_ID_OCI_python_3.11_slim_mount:-}" ]; then
  _log_workflow executor "oci-python_3.11_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_python_3.11_slim_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-python"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-python" executor "oci-python_3.11_slim-mount" workdir "$JOB_DIR" event "▶" "Job starting"
export PROJECT_NAME=hello-docker
ACTION_FAILED=false

run_action "test-python" "check-environment" "/nix/store/3fx56082dn4ri2svs6vllqlyx6x4f3by-check-environment/bin/check-environment" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''


run_action "test-python" "run-python-code" "/nix/store/2ygvnsmdcq2c31slma1f00rdmbjynd2r-run-python-code/bin/run-python-code" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-python" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-ubuntu() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/zykjlvbsxgafrj0j52rsiwg67piyh9hj-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "ubuntu:22.04" "ubuntu_22.04_mount"

  
  if [ -z "${CONTAINER_ID_OCI_ubuntu_22.04_mount:-}" ]; then
  _log_workflow executor "oci-ubuntu_22.04-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  -e PROJECT_NAME \
  "$CONTAINER_ID_OCI_ubuntu_22.04_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-ubuntu" executor "oci-ubuntu_22.04-mount" workdir "$JOB_DIR" event "▶" "Job starting"
export PROJECT_NAME=hello-docker
ACTION_FAILED=false

run_action "test-ubuntu" "system-info" "/nix/store/bz7dxkc21p4fl4xr9ykidaclib7j34ng-system-info/bin/system-info" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''


run_action "test-ubuntu" "install-and-run" "/nix/store/hd5kifgqaqcc0681ixcwy07p1gqsklx4-install-and-run/bin/install-and-run" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}


main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-node, test-python" event "→" "Starting level"
run_parallel "test-node|success()|" "test-python|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-ubuntu" event "→" "Starting level"
run_parallel "test-ubuntu|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "build-docker-image" event "→" "Starting level"
run_parallel "build-docker-image|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "summary" event "→" "Starting level"
run_parallel "summary|always()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
