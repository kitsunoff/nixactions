#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="artifacts-simple-$(date +%s)-$$"
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

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: build"
echo "║ EXECUTOR: local"
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
/nix/store/6aj0lvfzqyp05m5ii498nf8nhivdng7v-build/bin/build


  
  # Save artifacts on HOST after job completes
echo ""
echo "→ Saving artifacts"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
if [ -e "$JOB_DIR/dist/" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/dist"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "dist/")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/dist/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/dist/" "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
else
  echo "  ✗ Path not found: dist/"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: dist → dist/ (${ARTIFACT_SIZE})"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
if [ -e "$JOB_DIR/myapp" ]; then
  rm -rf "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp"
  
  # Save preserving original path structure
  PARENT_DIR=$(dirname "myapp")
  if [ "$PARENT_DIR" != "." ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/myapp/$PARENT_DIR"
  fi
  
  cp -r "$JOB_DIR/myapp" "$NIXACTIONS_ARTIFACTS_DIR/myapp/myapp"
else
  echo "  ✗ Path not found: myapp"
  return 1
fi

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/myapp" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: myapp → myapp (${ARTIFACT_SIZE})"


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
echo "→ Restoring artifacts: dist myapp"
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/dist" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/dist"/* "$JOB_DIR/" 2>/dev/null || true
else
  echo "  ✗ Artifact not found: dist"
  return 1
fi

echo "  ✓ Restored: dist"

JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
if [ -e "$NIXACTIONS_ARTIFACTS_DIR/myapp" ]; then
  # Restore to job directory (will be created by executeJob)
  mkdir -p "$JOB_DIR"
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/myapp"/* "$JOB_DIR/" 2>/dev/null || true
else
  echo "  ✗ Artifact not found: myapp"
  return 1
fi

echo "  ✓ Restored: myapp"

echo ""

  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test"
echo "║ EXECUTOR: local"
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
/nix/store/dfsi7aq678iahd9kkdn3lqhn66l3fpa6-test/bin/test


  
  
}


# Main execution
main() {
  echo "════════════════════════════════════════"
  echo " Workflow: artifacts-simple"
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
