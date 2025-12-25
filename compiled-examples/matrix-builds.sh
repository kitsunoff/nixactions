#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="matrix-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="matrix-demo"
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


# ============================================
# Job Functions
# ============================================

job_build-arch-amd64-distro-alpine() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-arch-amd64-distro-alpine"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-arch-amd64-distro-alpine" "build-amd64-alpine" "/nix/store/2jgsp5clyd48x8a2zn9g8v6kmvldy9dg-build-amd64-alpine/bin/build-amd64-alpine" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-amd64-distro-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build-arch-amd64-distro-alpine" event "→" "Saving artifacts"
save_local_artifact "build-amd64-alpine" "build-amd64-alpine/" "build-arch-amd64-distro-alpine"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-alpine" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-amd64-alpine → build-amd64-alpine/ (${ARTIFACT_SIZE})"


}

job_build-arch-amd64-distro-debian() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-arch-amd64-distro-debian"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-arch-amd64-distro-debian" "build-amd64-debian" "/nix/store/xlghvqkarksv1irl28s80s5lzarl7p0n-build-amd64-debian/bin/build-amd64-debian" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-amd64-distro-debian" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build-arch-amd64-distro-debian" event "→" "Saving artifacts"
save_local_artifact "build-amd64-debian" "build-amd64-debian/" "build-arch-amd64-distro-debian"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-amd64-debian" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-amd64-debian → build-amd64-debian/ (${ARTIFACT_SIZE})"


}

job_build-arch-arm64-distro-alpine() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-arch-arm64-distro-alpine"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-arch-arm64-distro-alpine" "build-arm64-alpine" "/nix/store/3cym7l7flcccab6g86cg2k43v7z5y3da-build-arm64-alpine/bin/build-arm64-alpine" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-arm64-distro-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build-arch-arm64-distro-alpine" event "→" "Saving artifacts"
save_local_artifact "build-arm64-alpine" "build-arm64-alpine/" "build-arch-arm64-distro-alpine"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-alpine" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-arm64-alpine → build-arm64-alpine/ (${ARTIFACT_SIZE})"


}

job_build-arch-arm64-distro-debian() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-arch-arm64-distro-debian"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-arch-arm64-distro-debian" "build-arm64-debian" "/nix/store/cvcc0c2ck9d0cvl3infz9j7agjz3m5yl-build-arm64-debian/bin/build-arm64-debian" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-arch-arm64-distro-debian" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build-arch-arm64-distro-debian" event "→" "Saving artifacts"
save_local_artifact "build-arm64-debian" "build-arm64-debian/" "build-arch-arm64-distro-debian"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-arm64-debian" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-arm64-debian → build-arm64-debian/ (${ARTIFACT_SIZE})"


}

job_deploy() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "deploy" artifacts "build-amd64-debian build-amd64-alpine build-arm64-debian build-arm64-alpine" event "→" "Restoring artifacts"
restore_local_artifact "build-amd64-debian" "." "deploy"

_log_job "deploy" artifact "build-amd64-debian" path "." event "✓" "Restored"

restore_local_artifact "build-amd64-alpine" "." "deploy"

_log_job "deploy" artifact "build-amd64-alpine" path "." event "✓" "Restored"

restore_local_artifact "build-arm64-debian" "." "deploy"

_log_job "deploy" artifact "build-arm64-debian" path "." event "✓" "Restored"

restore_local_artifact "build-arm64-alpine" "." "deploy"

_log_job "deploy" artifact "build-arm64-alpine" path "." event "✓" "Restored"


      setup_local_job "deploy"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "deploy" "deploy-all-builds" "/nix/store/9qqxcncgzyslwl60pl75j15bs7b3wiba-deploy-all-builds/bin/deploy-all-builds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "summary" "workflow-summary" "/nix/store/5dkqq35g3wbavyc1im3c5gs8irvr6wx1-workflow-summary/bin/workflow-summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-node-18-os-alpine() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:18-alpine" "node_18_alpine_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_18_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_18_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_18_alpine_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-18-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-18-os-alpine" executor "oci-node_18_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-18-os-alpine" "test-node-18-on-alpine" "/nix/store/1y76dwqd7p2izcwaiaw8lzb8hpknf297-test-node-18-on-alpine/bin/test-node-18-on-alpine" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-18-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-node-18-os-ubuntu() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:18-ubuntu" "node_18_ubuntu_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_18_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_18_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_18_ubuntu_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-18-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-18-os-ubuntu" executor "oci-node_18_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-18-os-ubuntu" "test-node-18-on-ubuntu" "/nix/store/jcwns5c2wlibcajs2cdb0sys0yjkqmg1-test-node-18-on-ubuntu/bin/test-node-18-on-ubuntu" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-18-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-node-20-os-alpine() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:20-alpine" "node_20_alpine_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_20_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_20_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_20_alpine_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-20-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-20-os-alpine" executor "oci-node_20_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-20-os-alpine" "test-node-20-on-alpine" "/nix/store/061g36ccgy8l4fiwwn75pcya300ljcmm-test-node-20-on-alpine/bin/test-node-20-on-alpine" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-20-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-node-20-os-ubuntu() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:20-ubuntu" "node_20_ubuntu_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_20_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_20_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_20_ubuntu_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-20-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-20-os-ubuntu" executor "oci-node_20_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-20-os-ubuntu" "test-node-20-on-ubuntu" "/nix/store/hnfzsrly68lz2afr4i5lfb4nmsqbvixz-test-node-20-on-ubuntu/bin/test-node-20-on-ubuntu" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-20-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-node-22-os-alpine() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:22-alpine" "node_22_alpine_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_22_alpine_mount:-}" ]; then
  _log_workflow executor "oci-node_22_alpine-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_22_alpine_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-22-os-alpine"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-22-os-alpine" executor "oci-node_22_alpine-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-22-os-alpine" "test-node-22-on-alpine" "/nix/store/jq4gc2ghwpp0s1zvyyggcb4xyqjhnjb4-test-node-22-on-alpine/bin/test-node-22-on-alpine" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-22-os-alpine" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}

job_test-node-22-os-ubuntu() {
  # Mode: MOUNT - mount /nix/store from host
source /nix/store/wl2bxzccsz9d2bmnjmknqzmqgy01liar-nixactions-oci-executor/bin/nixactions-oci-executor
export DOCKER=/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker
setup_oci_workspace "node:22-ubuntu" "node_22_ubuntu_mount"

  
  if [ -z "${CONTAINER_ID_OCI_node_22_ubuntu_mount:-}" ]; then
  _log_workflow executor "oci-node_22_ubuntu-mount" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_node_22_ubuntu_mount" \
  bash -c 'set -uo pipefail
source /nix/store/*-nixactions-logging/bin/nixactions-logging
source /nix/store/*-nixactions-retry/bin/nixactions-retry
source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
JOB_DIR="/workspace/jobs/test-node-22-os-ubuntu"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV
_log_job "test-node-22-os-ubuntu" executor "oci-node_22_ubuntu-mount" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-node-22-os-ubuntu" "test-node-22-on-ubuntu" "/nix/store/hclmkgwxx7vjy7p17caq8w181zw4sg1y-test-node-22-on-ubuntu/bin/test-node-22-on-ubuntu" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-node-22-os-ubuntu" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  
}


main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-node-18-os-alpine, test-node-18-os-ubuntu, test-node-20-os-alpine, test-node-20-os-ubuntu, test-node-22-os-alpine, test-node-22-os-ubuntu" event "→" "Starting level"
run_parallel "test-node-18-os-alpine|success()|" "test-node-18-os-ubuntu|success()|" "test-node-20-os-alpine|success()|" "test-node-20-os-ubuntu|success()|" "test-node-22-os-alpine|success()|" "test-node-22-os-ubuntu|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "build-arch-amd64-distro-alpine, build-arch-amd64-distro-debian, build-arch-arm64-distro-alpine, build-arch-arm64-distro-debian" event "→" "Starting level"
run_parallel "build-arch-amd64-distro-alpine|success()|" "build-arch-amd64-distro-debian|success()|" "build-arch-arm64-distro-alpine|success()|" "build-arch-arm64-distro-debian|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "deploy" event "→" "Starting level"
run_parallel "deploy|success()|" || {
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
