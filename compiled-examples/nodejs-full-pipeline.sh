#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="nodejs-ci-cd-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="nodejs-ci-cd"
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
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi

# ============================================
# Job Functions
# ============================================

job_build() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "build" artifacts "coverage" event "→" "Restoring artifacts"
restore_local_artifact "coverage" "coverage/" "build"

_log_job "build" artifact "coverage" path "coverage/" event "✓" "Restored"


      setup_local_job "build"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build" "install-deps" "/nix/store/b7p589g11cl0lm462i9w12bg62p7j2fm-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build" "build" "/nix/store/1lzkms1zgvxrgv0kz81xlv9kgkzhw5yi-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "build" event "→" "Saving artifacts"
save_local_artifact "dist" "dist/" "build"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/dist" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: dist → dist/ (${ARTIFACT_SIZE})"


}

job_deploy-production() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "deploy-production" artifacts "dist" event "→" "Restoring artifacts"
restore_local_artifact "dist" "dist/" "deploy-production"

_log_job "deploy-production" artifact "dist" path "dist/" event "✓" "Restored"


      setup_local_job "deploy-production"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "deploy-production" "deploy-production" "/nix/store/d482fpy653sh7mg6i8gn2kdkjgiq4w4p-deploy-production/bin/deploy-production" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy-production" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_deploy-staging() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  # Restore artifacts
_log_job "deploy-staging" artifacts "dist" event "→" "Restoring artifacts"
restore_local_artifact "dist" "dist/" "deploy-staging"

_log_job "deploy-staging" artifact "dist" path "dist/" event "✓" "Restored"


      setup_local_job "deploy-staging"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "deploy-staging" "deploy-staging" "/nix/store/y95mlspbvwr3vvk089gr1xj5n7b3340l-deploy-staging/bin/deploy-staging" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy-staging" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "lint" "install-deps" "/nix/store/b7p589g11cl0lm462i9w12bg62p7j2fm-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "lint" "install-deps" "/nix/store/b7p589g11cl0lm462i9w12bg62p7j2fm-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-failure() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-failure"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-failure" "notify" "/nix/store/sjxj2zcjkigwwljlzmmjjka62iw17xwk-notify/bin/notify" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-success"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-success" "notify" "/nix/store/yaigzkf5008kpcywk1wkhvr01par0mhd-notify/bin/notify" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "install-deps" "/nix/store/b7p589g11cl0lm462i9w12bg62p7j2fm-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables
export RETRY_BACKOFF=exponential
export RETRY_MAX_ATTEMPTS=3
export RETRY_MAX_TIME=10
export RETRY_MIN_TIME=1
# Set timeout environment variables

run_action "test" "unit-tests" "/nix/store/15gla5nvmnzh7a8mvlhhlpn6m0v02z3d-unit-tests/bin/unit-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  # Save artifacts
_log_job "test" event "→" "Saving artifacts"
save_local_artifact "coverage" "coverage/" "test"

ARTIFACT_SIZE=$(du -sh "$NIXACTIONS_ARTIFACTS_DIR/coverage" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Saved: coverage → coverage/ (${ARTIFACT_SIZE})"


}

job_typecheck() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "typecheck"
if [ -z "${BRANCH+x}" ]; then
  export BRANCH=develop
fi
if [ -z "${CI+x}" ]; then
  export CI=true
fi
if [ -z "${NODE_ENV+x}" ]; then
  export NODE_ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "typecheck" "install-deps" "/nix/store/b7p589g11cl0lm462i9w12bg62p7j2fm-install-deps/bin/install-deps" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "typecheck" "typescript" "/nix/store/142rs20y2dpya57f56mdix3mcz32sw5p-typescript/bin/typescript" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "typecheck" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "lint, typecheck" event "→" "Starting level"
run_parallel "lint|success()|" "typecheck|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test" event "→" "Starting level"
run_parallel "test|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "build" event "→" "Starting level"
run_parallel "build|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "deploy-production, deploy-staging" event "→" "Starting level"
run_parallel "deploy-production|success()|" "deploy-staging|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "notify-failure, notify-success" event "→" "Starting level"
run_parallel "notify-failure|success()|" "notify-success|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
