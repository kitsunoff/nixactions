#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="artifacts-demo-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="artifacts-demo"
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

run_action "build" "build" "/nix/store/himisiy3z1smgagy1dxaxadqj8yib4xk-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "backend" "dist/backend/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/backend" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: backend → dist/backend/ (${ARTIFACT_SIZE})"

save_local_artifact "binary" "myapp" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/binary" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: binary → myapp (${ARTIFACT_SIZE})"

save_local_artifact "frontend" "dist/frontend/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/frontend" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: frontend → dist/frontend/ (${ARTIFACT_SIZE})"

save_local_artifact "release" "target/release/app" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/release" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: release → target/release/app (${ARTIFACT_SIZE})"


}

job_test-custom() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-custom" artifacts "frontend backend" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "public/" "test-custom"

_log_job "test-custom" artifact "frontend" path "public/" event "✓" "Restored"

restore_local_artifact "backend" "server/" "test-custom"

_log_job "test-custom" artifact "backend" path "server/" event "✓" "Restored"


      setup_local_job "test-custom"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-custom" "test-custom" "/nix/store/dpjr6m9s6vmwcgfgxp54nb2hm0jl3ql2-test-custom/bin/test-custom" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-custom" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-default() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-default" artifacts "frontend backend" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "." "test-default"

_log_job "test-default" artifact "frontend" path "." event "✓" "Restored"

restore_local_artifact "backend" "." "test-default"

_log_job "test-default" artifact "backend" path "." event "✓" "Restored"


      setup_local_job "test-default"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-default" "test-default" "/nix/store/bc5608wfv379jr2hdsp9ja30fpknrqpw-test-default/bin/test-default" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-default" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-mixed() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "test-mixed" artifacts "binary release" event "→" "Restoring artifacts"
restore_local_artifact "binary" "." "test-mixed"

_log_job "test-mixed" artifact "binary" path "." event "✓" "Restored"

restore_local_artifact "release" "bin/" "test-mixed"

_log_job "test-mixed" artifact "release" path "bin/" event "✓" "Restored"


      setup_local_job "test-mixed"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-mixed" "test-mixed" "/nix/store/73jz4i4fs11k8611kjc9h2zdscsrcay0-test-mixed/bin/test-mixed" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-mixed" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "validate" artifacts "frontend backend binary release" event "→" "Restoring artifacts"
restore_local_artifact "frontend" "." "validate"

_log_job "validate" artifact "frontend" path "." event "✓" "Restored"

restore_local_artifact "backend" "." "validate"

_log_job "validate" artifact "backend" path "." event "✓" "Restored"

restore_local_artifact "binary" "." "validate"

_log_job "validate" artifact "binary" path "." event "✓" "Restored"

restore_local_artifact "release" "." "validate"

_log_job "validate" artifact "release" path "." event "✓" "Restored"


      setup_local_job "validate"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "validate" "validate" "/nix/store/xyzxjj214r1yafz1kvfs1is3hf8mm4kw-validate/bin/validate" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "validate" event "✗" "Job failed due to action failures"
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

_log_workflow level 1 jobs "test-custom, test-default, test-mixed" event "→" "Starting level"
run_parallel "test-custom|success()|" "test-default|success()|" "test-mixed|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "validate" event "→" "Starting level"
run_parallel "validate|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
