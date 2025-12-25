#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="artifacts-oci-build-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="artifacts-oci-build"
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

job_build() {
  # Mode: BUILD - build custom image with actions
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  # Load custom image
  echo "→ Loading custom OCI image with actions (this may take a while)..."
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker load < /nix/store/90zsrgv4a8k1n0b8kpslzd7gjmdslzsm-nixactions-alpine.tar.gz
  
  # Create and start container from custom image
  CONTAINER_ID_OCI_alpine_build=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    nixactions-alpine:latest)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_alpine_build"
  
  export CONTAINER_ID_OCI_alpine_build
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p /workspace
  
  _log_workflow executor "oci-alpine-build" container "$CONTAINER_ID_OCI_alpine_build" workspace "/workspace" event "→" "Workspace created"
  echo "  Image includes: bash, coreutils, and all action derivations"
fi

  
  if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow executor "oci-alpine-build" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_alpine_build" \
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
_log_job "build" executor "oci-alpine-build" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build" "build" "/nix/store/rs7map7s1lxr87cz6shw80lbzipq4l9l-build/bin/build" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
'

  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" test -e "$JOB_DIR/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
else
  _log_workflow artifact "dist" path "dist/" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: dist → dist/ (${ARTIFACT_SIZE})"

if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" test -e "$JOB_DIR/myapp"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/myapp" \
    "$NIXACTIONS_ARTIFACTS_DIR/myapp/myapp"
else
  _log_workflow artifact "myapp" path "myapp" event "✗" "Path not found"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/myapp" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: myapp → myapp (${ARTIFACT_SIZE})"


}

job_test() {
  # Mode: BUILD - build custom image with actions
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  # Load custom image
  echo "→ Loading custom OCI image with actions (this may take a while)..."
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker load < /nix/store/np6imxh1qsw3vpki0wl6vzb14pjzyjji-nixactions-alpine.tar.gz
  
  # Create and start container from custom image
  CONTAINER_ID_OCI_alpine_build=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    nixactions-alpine:latest)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_alpine_build"
  
  export CONTAINER_ID_OCI_alpine_build
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p /workspace
  
  _log_workflow executor "oci-alpine-build" container "$CONTAINER_ID_OCI_alpine_build" workspace "/workspace" event "→" "Workspace created"
  echo "  Image includes: bash, coreutils, and all action derivations"
fi

  # Restore artifacts
_log_job "test" artifacts "dist myapp" event "→" "Restoring artifacts"
if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/dist" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Determine target directory
  if [ "." = "." ] || [ "." = "./" ]; then
    # Restore to root of job directory (default behavior)
    /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$JOB_DIR"
    
    for item in "$NIXACTIONS_ARTIFACTS_DIR/dist"/*; do
      if [ -e "$item" ]; then
        /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/"
      fi
    done
  else
    # Restore to custom path
    TARGET_DIR="$JOB_DIR/."
    /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$TARGET_DIR"
    
    for item in "$NIXACTIONS_ARTIFACTS_DIR/dist"/*; do
      if [ -e "$item" ]; then
        /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$TARGET_DIR/"
      fi
    done
  fi
else
  _log_workflow artifact "dist" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "dist" path "." event "✓" "Restored"

if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow event "✗" "Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/myapp" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Determine target directory
  if [ "." = "." ] || [ "." = "./" ]; then
    # Restore to root of job directory (default behavior)
    /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$JOB_DIR"
    
    for item in "$NIXACTIONS_ARTIFACTS_DIR/myapp"/*; do
      if [ -e "$item" ]; then
        /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$JOB_DIR/"
      fi
    done
  else
    # Restore to custom path
    TARGET_DIR="$JOB_DIR/."
    /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_alpine_build" mkdir -p "$TARGET_DIR"
    
    for item in "$NIXACTIONS_ARTIFACTS_DIR/myapp"/*; do
      if [ -e "$item" ]; then
        /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_alpine_build:$TARGET_DIR/"
      fi
    done
  fi
else
  _log_workflow artifact "myapp" event "✗" "Artifact not found"
  return 1
fi

_log_job "test" artifact "myapp" path "." event "✓" "Restored"


  if [ -z "${CONTAINER_ID_OCI_alpine_build:-}" ]; then
  _log_workflow executor "oci-alpine-build" event "✗" "Workspace not initialized"
  exit 1
fi
/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
  -e WORKFLOW_NAME \
  -e NIXACTIONS_LOG_FORMAT \
  "$CONTAINER_ID_OCI_alpine_build" \
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
_log_job "test" executor "oci-alpine-build" workdir "$JOB_DIR" event "▶" "Job starting"

# Set job-level environment variables

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "test" "/nix/store/kqnml247dqq3967m97c1fyxvk9qpszhw-test/bin/test" '\''success()'\'' '\''date +%s%N 2>/dev/null || date +%s'\''

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
