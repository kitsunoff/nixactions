#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="complete-ci-pipeline-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="complete-ci-pipeline"
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
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi

# ============================================
# Job Functions
# ============================================

job_build() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build" "build-artifacts" "/nix/store/ybby4j1b81w2wx6qmqnjjiadk14krs0g-build-artifacts/bin/build-artifacts" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_cleanup() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "cleanup"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "cleanup" "cleanup-resources" "/nix/store/a9s6z3zl5lzxq5gnnk0xv5d9khs52ij3-cleanup-resources/bin/cleanup-resources" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "cleanup" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_deploy() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "deploy"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "deploy" "deploy-to-staging" "/nix/store/q3c2if34i64195hsf0fp77l8h33517h4-deploy-to-staging/bin/deploy-to-staging" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${LINT_MODE+x}" ]; then
  export LINT_MODE=strict
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "lint" "lint-nix" "/nix/store/qqzxnlqjx9l6m31b84rw64pzn9n6yb00-lint-nix/bin/lint-nix" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-failure() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-failure"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-failure" "notify-failure" "/nix/store/wxyd978q21dcmcvmgdcirnz0990s679z-notify-failure/bin/notify-failure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-success"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-success" "notify-success" "/nix/store/4290w2sg62rbmzxri46d3q83j9ks7rfx-notify-success/bin/notify-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_security() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "security"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "security" "security-scan" "/nix/store/6y8lg92p3iyxfy2cx2ybw8bqby1lgd6j-security-scan/bin/security-scan" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "security" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "run-tests" "/nix/store/x3117pp6wcwmrg6f454q909vggdnrd5a-run-tests/bin/run-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "validate"
if [ -z "${BUILD_ENV+x}" ]; then
  export BUILD_ENV=ci
fi
if [ -z "${PROJECT_NAME+x}" ]; then
  export PROJECT_NAME=nixactions
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "validate" "validate-structure" "/nix/store/474814gg4h23px8rlwr5kv537dfwmj16-validate-structure/bin/validate-structure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "validate" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "lint, security, validate" event "→" "Starting level"
run_parallel "lint|success()|" "security|success()|1" "validate|success()|" || {
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

_log_workflow level 3 jobs "deploy, notify-failure, notify-success" event "→" "Starting level"
run_parallel "deploy|success()|" "notify-failure|failure()|" "notify-success|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "cleanup" event "→" "Starting level"
run_parallel "cleanup|always()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
