#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="artifacts-paths-oci-$(date +%s)-$$"
export WORKFLOW_ID

# Setup artifacts directory on control node
NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

# Job status tracking
declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false

# Trap cancellation
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

# Check if condition is met
check_condition() {
  local condition=$1
  
  case "$condition" in
    success\(\))
      if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
        return 1  # Has failures
      fi
      ;;
    failure\(\))
      if [ ${#FAILED_JOBS[@]} -eq 0 ]; then
        return 1  # No failures
      fi
      ;;
    always\(\))
      return 0  # Always run
      ;;
    cancelled\(\))
      if [ "$WORKFLOW_CANCELLED" = "false" ]; then
        return 1
      fi
      ;;
    *)
      echo "Unknown condition: $condition"
      return 1
      ;;
  esac
  
  return 0
}

# Run single job with condition check
run_job() {
  local job_name=$1
  local condition=${2:-success()}
  local continue_on_error=${3:-false}
  
  # Check condition
  if ! check_condition "$condition"; then
    echo "⊘ Skipping $job_name (condition not met: $condition)"
    JOB_STATUS[$job_name]="skipped"
    return 0
  fi
  
  # Execute job in subshell (isolation by design)
  if ( job_$job_name ); then
    echo "✓ Job $job_name succeeded"
    JOB_STATUS[$job_name]="success"
    return 0
  else
    local exit_code=$?
    echo "✗ Job $job_name failed (exit code: $exit_code)"
    FAILED_JOBS+=("$job_name")
    JOB_STATUS[$job_name]="failure"
    
    if [ "$continue_on_error" = "true" ]; then
      echo "→ Continuing despite failure (continueOnError: true)"
      return 0
    else
      return $exit_code
    fi
  fi
}

# Run jobs in parallel
run_parallel() {
  local -a job_specs=("$@")
  local -a pids=()
  local failed=false
  
  # Start all jobs
  for spec in "${job_specs[@]}"; do
    IFS='|' read -r job_name condition continue_on_error <<< "$spec"
    
    # Run in background
    (
      run_job "$job_name" "$condition" "$continue_on_error"
    ) &
    pids+=($!)
  done
  
  # Wait for all jobs
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=true
    fi
  done
  
  if [ "$failed" = "true" ]; then
    # Check if we should stop
    for spec in "${job_specs[@]}"; do
      IFS='|' read -r job_name condition continue_on_error <<< "$spec"
      if [ "${JOB_STATUS[$job_name]}" = "failure" ] && [ "$continue_on_error" != "true" ]; then
        echo "⊘ Stopping workflow due to job failure: $job_name"
        return 1
      fi
    done
  fi
  
  return 0
}

# Job functions
job_build() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_nixos_nix_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    nixos/nix \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_nixos_nix_mount"
  
  export CONTAINER_ID_OCI_nixos_nix_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p /workspace
  
  echo "→ OCI workspace (mount): container $CONTAINER_ID_OCI_nixos_nix_mount:/workspace"
fi

  
  
  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "Error: OCI workspace not initialized for nixos/nix (mode: mount)"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_nixos_nix_mount" \
  bash -c 'set -euo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/build"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: build"
echo "║ EXECUTOR: oci-nixos_nix-mount"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Execute action derivations as separate processes
# === build ===
echo "→ build"

# Source JOB_ENV and export all variables before running action
set -a
[ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
set +a

# Execute action as separate process
/nix/store/hdwpjkhis0y7cv1zfcrlzn7f64fza148-build/bin/build

'

  
  # Save artifacts on HOST after job completes
echo ""
echo "→ Saving artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "  ✗ Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/build/dist/"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "build/dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/build/dist/" \
    "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts/build/dist/"
else
  echo "  ✗ Path not found: build/dist/"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-artifacts → build/dist/ (${ARTIFACT_SIZE})"

if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "  ✗ Container not initialized"
  return 1
fi

JOB_DIR="/workspace/jobs/build"

# Check if path exists in container
if /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" test -e "$JOB_DIR/target/release/myapp"; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/release-binary"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/release-binary"
  
  # Preserve directory structure
  PARENT_DIR=$(dirname "target/release/myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/release-binary/$PARENT_DIR"
  fi
  
  # Copy from container to host
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp \
    "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/target/release/myapp" \
    "$NIXACTIONS_ARTIFACTS_DIR/release-binary/target/release/myapp"
else
  echo "  ✗ Path not found: target/release/myapp"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/release-binary" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: release-binary → target/release/myapp (${ARTIFACT_SIZE})"


}


job_test() {
  # Setup workspace for this job
  # Mode: MOUNT - mount /nix/store from host
# Lazy init - only create if not exists
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  # Create and start long-running container with /nix/store mounted
  CONTAINER_ID_OCI_nixos_nix_mount=$(/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker create \
    -v /nix/store:/nix/store:ro \
    nixos/nix \
    sleep infinity)
  
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker start "$CONTAINER_ID_OCI_nixos_nix_mount"
  
  export CONTAINER_ID_OCI_nixos_nix_mount
  
  # Create workspace directory in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p /workspace
  
  echo "→ OCI workspace (mount): container $CONTAINER_ID_OCI_nixos_nix_mount:/workspace"
fi

  
  # Restore artifacts on HOST before executing job
echo "→ Restoring artifacts: release-binary build-artifacts"
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "  ✗ Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/release-binary" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/release-binary"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/"
    fi
  done
else
  echo "  ✗ Artifact not found: release-binary"
  return 1
fi

echo "  ✓ Restored: release-binary"

if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "  ✗ Container not initialized"
  return 1
fi

if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts" ]; then
  JOB_DIR="/workspace/jobs/test"
  
  # Ensure job directory exists in container
  /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec "$CONTAINER_ID_OCI_nixos_nix_mount" mkdir -p "$JOB_DIR"
  
  # Copy each file/directory from artifact to container
  for item in "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"/*; do
    if [ -e "$item" ]; then
      /nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker cp "$item" "$CONTAINER_ID_OCI_nixos_nix_mount:$JOB_DIR/"
    fi
  done
else
  echo "  ✗ Artifact not found: build-artifacts"
  return 1
fi

echo "  ✓ Restored: build-artifacts"

echo ""

  
  # Execute job via executor
  # Ensure workspace is initialized
if [ -z "${CONTAINER_ID_OCI_nixos_nix_mount:-}" ]; then
  echo "Error: OCI workspace not initialized for nixos/nix (mode: mount)"
  exit 1
fi

/nix/store/38qw6ldsflj4jzvvfm2q7f4i7x1m79n7-docker-29.1.2/bin/docker exec \
   \
  "$CONTAINER_ID_OCI_nixos_nix_mount" \
  bash -c 'set -euo pipefail

# Create job directory
JOB_DIR="/workspace/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE container workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test"
echo "║ EXECUTOR: oci-nixos_nix-mount"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Execute action derivations as separate processes
# === test ===
echo "→ test"

# Source JOB_ENV and export all variables before running action
set -a
[ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
set +a

# Execute action as separate process
/nix/store/6sch2vjgq7k8s8qpwi1r8k6klld149qh-test/bin/test

'

  
  
}


# Main execution
main() {
  echo "════════════════════════════════════════"
  echo " Workflow: artifacts-paths-oci"
  echo " Execution: GitHub Actions style (parallel)"
  echo " Levels: 2"
  echo "════════════════════════════════════════"
  echo ""
  
  # Execute level by level
  echo "→ Level 0: build"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "build|success()|" || {
    echo "⊘ Level 0 failed"
    exit 1
  }

echo ""


echo "→ Level 1: test"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test|success()|" || {
    echo "⊘ Level 1 failed"
    exit 1
  }

echo ""

  
  # Final report
  echo "════════════════════════════════════════"
  if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
    echo "✗ Workflow failed"
    echo ""
    echo "Failed jobs:"
    printf '  - %s\n' "${FAILED_JOBS[@]}"
    echo ""
    echo "Job statuses:"
    for job in build test; do
      echo "  $job: ${JOB_STATUS[$job]:-unknown}"
    done
    exit 1
  else
    echo "✓ Workflow completed successfully"
    echo ""
    echo "All jobs succeeded:"
    for job in build test; do
      if [ "${JOB_STATUS[$job]:-unknown}" = "success" ]; then
        echo "  ✓ $job"
      elif [ "${JOB_STATUS[$job]:-unknown}" = "skipped" ]; then
        echo "  ⊘ $job (skipped)"
      fi
    done
  fi
  echo "════════════════════════════════════════"
}

main "$@"
