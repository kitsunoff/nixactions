#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="artifacts-paths-$(date +%s)-$$"
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
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

echo "╔════════════════════════════════════════╗"
echo "║ JOB: build"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Execute the job script
# Setup PATH with all job dependencies


# Setup job-level environment variables


# Execute actions (all in the same job directory)
# === build ===

echo "→ Building with nested structure"

# Create nested directories
mkdir -p target/release
mkdir -p build/dist

# Create files
echo "#!/bin/bash" > target/release/myapp
echo "echo 'Release binary'" >> target/release/myapp
chmod +x target/release/myapp

echo "artifact 1" > build/dist/file1.txt
echo "artifact 2" > build/dist/file2.txt

echo "✓ Build complete"
find . -type f





  
  # Save artifacts on HOST after job completes
echo ""
echo "→ Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
if [ -e "$JOB_DIR/build/dist/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "build/dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/build/dist/" "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts/build/dist/"
else
  echo "  ✗ Path not found: build/dist/"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-artifacts → build/dist/ (${ARTIFACT_SIZE})"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
if [ -e "$JOB_DIR/target/release/myapp" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/release-binary"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/release-binary"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "target/release/myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/release-binary/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/target/release/myapp" "$NIXACTIONS_ARTIFACTS_DIR/release-binary/target/release/myapp"
else
  echo "  ✗ Path not found: target/release/myapp"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/release-binary" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: release-binary → target/release/myapp (${ARTIFACT_SIZE})"


  
  # Cleanup workspace after this job
  if [ -n "${WORKSPACE_DIR_LOCAL:-}" ]; then
  if [ "${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
    echo ""
    echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
    rm -rf "$WORKSPACE_DIR_LOCAL"
  else
    echo ""
    echo "→ Local workspace preserved: $WORKSPACE_DIR_LOCAL"
  fi
fi

}


job_test() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Restore artifacts on HOST before executing job
echo "→ Restoring artifacts: release-binary build-artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/release-binary" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/release-binary"/* "$JOB_DIR/" 2>/dev/null || true
else
  echo "  ✗ Artifact not found: release-binary"
  return 1
fi

echo "  ✓ Restored: release-binary"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"/* "$JOB_DIR/" 2>/dev/null || true
else
  echo "  ✗ Artifact not found: build-artifacts"
  return 1
fi

echo "  ✓ Restored: build-artifacts"

echo ""

  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Execute the job script
# Setup PATH with all job dependencies


# Setup job-level environment variables


# Execute actions (all in the same job directory)
# === test ===

echo "→ Testing restored paths"

echo ""
echo "Directory structure:"
find . -type f -o -type d | sort

echo ""
echo "→ Checking target/release/myapp"
if [ -f "target/release/myapp" ]; then
  echo "✓ target/release/myapp found"
  ./target/release/myapp
else
  echo "✗ target/release/myapp NOT found"
  exit 1
fi

echo ""
echo "→ Checking build/dist/"
if [ -d "build/dist" ]; then
  echo "✓ build/dist/ found"
  ls -la build/dist/
  cat build/dist/file1.txt
  cat build/dist/file2.txt
else
  echo "✗ build/dist/ NOT found"
  exit 1
fi

echo ""
echo "✓ All paths restored correctly!"





  
  
  
  # Cleanup workspace after this job
  if [ -n "${WORKSPACE_DIR_LOCAL:-}" ]; then
  if [ "${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
    echo ""
    echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
    rm -rf "$WORKSPACE_DIR_LOCAL"
  else
    echo ""
    echo "→ Local workspace preserved: $WORKSPACE_DIR_LOCAL"
  fi
fi

}


# Main execution
main() {
  echo "════════════════════════════════════════"
  echo " Workflow: artifacts-paths"
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
