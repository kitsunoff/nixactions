#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="env-sharing-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="env-sharing-demo"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/c6a8pgh4xzjl6zc1hglg5l823xfvbdr1-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/1mgqdp33xiddrm2va94abw7l8wdvzz0q-nixactions-runtime/bin/nixactions-runtime

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
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "build" "generate-version" "/nix/store/15pd9x4513h8yz79b6n7gd27r0bq03q0-generate-version/bin/generate-version" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "build" "build-app" "/nix/store/6rc61imrlc6jdlgb7wn4p4dbdq47dlrm-build-app/bin/build-app" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "build" "verify-build" "/nix/store/h8sjcdkh8f38r4m070gfsrpzsmv05yx3-verify-build/bin/verify-build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "build-info" "dist/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/build-info" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: build-info → dist/ (${ARTIFACT_SIZE})"


}

job_calculate() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "calculate" artifacts "build-info" event "→" "Restoring artifacts"
restore_local_artifact "build-info" "." "calculate"

_log_job "calculate" artifact "build-info" path "." event "✓" "Restored"


      setup_local_job "calculate"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "calculate" "multi-step-calculation" "/nix/store/i96xrfp07fkjlhr0ir3yz31s8y8m1iff-multi-step-calculation/bin/multi-step-calculation" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "calculate" "use-calculations" "/nix/store/99kpksdaqqf7252srib1pjnay9cjcwvz-use-calculations/bin/use-calculations" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "calculate" event "✗" "Job failed due to action failures"
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

run_action "summary" "summary" "/nix/store/nc3zk8nfwyh4sgdr5714c8n46kvra9k3-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-advanced() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-advanced" artifacts "build-info" event "→" "Restoring artifacts"
restore_local_artifact "build-info" "." "test-advanced"

_log_job "test-advanced" artifact "build-info" path "." event "✓" "Restored"


      setup_local_job "test-advanced"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-advanced" "parse-build-info" "/nix/store/bp8gcmbhyvh7pg16m42f94m2xpbi21vq-parse-build-info/bin/parse-build-info" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-advanced" "use-parsed-version" "/nix/store/idfgnvnb6flyz1pprp1n6arbc9492hcr-use-parsed-version/bin/use-parsed-version" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-advanced" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 3 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "build" event "→" "Starting level"
run_parallel "build|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "calculate, test-advanced" event "→" "Starting level"
run_parallel "calculate|success()|" "test-advanced|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "summary" event "→" "Starting level"
run_parallel "summary|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
