#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="docker-ci-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="docker-ci"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/c6a8pgh4xzjl6zc1hglg5l823xfvbdr1-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/gnfqpy8dkjijil7y2k7jgx52v7nbc189-nixactions-runtime/bin/nixactions-runtime

NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

# ============================================
# Environment Provider Execution
# ============================================

# Helper: Execute provider and apply exports
run_provider() {
  local provider=$1
  local provider_name=$(basename "$provider")
  
  _log_workflow provider "$provider_name" event "→" "Loading environment"
  
  # Execute provider, capture output
  local output
  if ! output=$("$provider" 2>&1); then
    local exit_code=$?
    _log_workflow provider "$provider_name" event "✗" "Provider failed (exit $exit_code)"
    echo "$output" >&2
    exit $exit_code
  fi
  
  # Apply exports - providers always override previous values
  # Runtime environment (already in shell) has highest priority
  local vars_set=0
  local vars_from_runtime=0
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      local key="${BASH_REMATCH[1]}"
      
      # Check if variable was set from runtime (before provider execution started)
      # We detect this by checking if it's in our RUNTIME_ENV_KEYS list
      if [[ " ${RUNTIME_ENV_KEYS} " =~ " ${key} " ]]; then
        # Runtime env has highest priority - skip
        vars_from_runtime=$((vars_from_runtime + 1))
      else
        # Apply provider value (may override previous provider)
        eval "$line"
        vars_set=$((vars_set + 1))
      fi
    fi
  done <<< "$output"
  
  if [ $vars_set -gt 0 ]; then
    _log_workflow provider "$provider_name" vars_set "$vars_set" event "✓" "Variables loaded"
  fi
  if [ $vars_from_runtime -gt 0 ]; then
    _log_workflow provider "$provider_name" vars_from_runtime "$vars_from_runtime" event "⊘" "Variables skipped (runtime override)"
  fi
}

# Execute envFrom providers in order


# Apply workflow-level env (hardcoded, lowest priority)
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=hello-docker
fi

# ============================================
# Job Functions
# ============================================

job_build-docker-image() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-docker-image"
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=hello-docker
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-docker-image" "create-dockerfile" "/nix/store/vpdrfz1125zhx2bp103p01v4vsnzjj5g-create-dockerfile/bin/create-dockerfile" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-docker-image" "build-image" "/nix/store/jcdv8qajm0mq9sfyfx4r2i8ksvkqmb29-build-image/bin/build-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-docker-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=hello-docker
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "summary" "summary" "/nix/store/c3lrm0js31g2ja2abrkhdndvfjqpsvgx-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-node() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:20-slim" "node_20_slim_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_20_slim_mount:-}" ]; then
  _log_workflow executor "oci-node_20_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
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

# Set job-level environment variables
export PROJECT_NAME=hello-docker
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node" "check-node" "/nix/store/injx2x5n7hcp0m9nmiha22xydgb6ddrb-check-node/bin/check-node" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node" "run-javascript" "/nix/store/wzycza1y7ydyzzrg8qv34pay66wwgdk7-run-javascript/bin/run-javascript" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-python() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "python:3.11-slim" "python_3.11_slim_mount"

  
  if [ -z "${CONTAINER_ID_OCI_python_3.11_slim_mount:-}" ]; then
  _log_workflow executor "oci-python_3.11_slim-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
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

# Set job-level environment variables
export PROJECT_NAME=hello-docker
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-python" "check-environment" "/nix/store/na37vwqz3qpmpm19h8jjcxi84nj3sfh1-check-environment/bin/check-environment" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-python" "run-python-code" "/nix/store/4zv7m1isirlh56jj3n2plkrm7cfdzzs2-run-python-code/bin/run-python-code" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-python" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-ubuntu() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "ubuntu:22.04" "ubuntu_22.04_mount"

  
  if [ -z "${CONTAINER_ID_OCI_ubuntu_22.04_mount:-}" ]; then
  _log_workflow executor "oci-ubuntu_22.04-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
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

# Set job-level environment variables
export PROJECT_NAME=hello-docker
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-ubuntu" "system-info" "/nix/store/r4ch5z092b97ylhjcyjxq425i1vbxddl-system-info/bin/system-info" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-ubuntu" "install-and-run" "/nix/store/dkkd5q3npzj1vwqs6b89iamh5flv952h-install-and-run/bin/install-and-run" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

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
