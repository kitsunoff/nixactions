#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="python-ci-cd-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="python-ci-cd"
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
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi

# ============================================
# Job Functions
# ============================================

job_build-image() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-image"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-image" "checkout-code" "/nix/store/3az73jgfcx91phkijfwx4m747nxhyzqj-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-image" "prepare-build-context" "/nix/store/isjlli1aw9ga1hxya0ksy1rrhhhhrl3z-prepare-build-context/bin/prepare-build-context" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-image" "build-docker-image" "/nix/store/vpp3mkr0dlbbkj37w4dvfb5df7skj9kx-build-docker-image/bin/build-docker-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "build-image" "scan-image" "/nix/store/8kni9s106jmgmdjr8j6xbi261xn2g0sj-scan-image/bin/scan-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_cleanup() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "cleanup"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "cleanup" "cleanup-temp-files" "/nix/store/hywvj2q47gpa960wwf1872bmqw2xwimb-cleanup-temp-files/bin/cleanup-temp-files" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "cleanup" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "lint" "checkout-code" "/nix/store/jrpdjsk567rxilr5ana483ddpsjkimld-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "lint" "lint-python" "/nix/store/vzqjxq48g82kjx3cw4rf0nzp1mgsz2n5-lint-python/bin/lint-python" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-failure() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-failure"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-failure" "send-failure-notification" "/nix/store/w29r50vcm2cviv9j9b1ifrm2k1gmagrb-send-failure-notification/bin/send-failure-notification" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-success"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "notify-success" "send-success-notification" "/nix/store/p8232vcwlvn66mp7bnsvmc35r4g4bl7i-send-success-notification/bin/send-success-notification" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_push-image() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "push-image"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "push-image" "push-to-registry" "/nix/store/pcb4ndwmb7z897ff6nv0cknrs85xrxya-push-to-registry/bin/push-to-registry" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "push-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "checkout-code" "/nix/store/dcwkds6p6v2047pcjrsrwcjmr2aa1ssr-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "install-dependencies" "/nix/store/32ag4by3z6n1n8049xmzaxqb8hv6bdy8-install-dependencies/bin/install-dependencies" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "run-unit-tests" "/nix/store/gjf6mqjnz9i8cmpdl0xki19mzp5d7hx0-run-unit-tests/bin/run-unit-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test" "test-app-execution" "/nix/store/29v7gs4ksiw0bdjl0awhgdg8x63i9dgd-test-app-execution/bin/test-app-execution" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_type-check() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "type-check"
if [ -z "${DOCKER_REGISTRY+x}" ]; then
  export DOCKER_REGISTRY=registry.example.com
fi
if [ -z "${IMAGE_NAME+x}" ]; then
  export IMAGE_NAME=math-app
fi
if [ -z "${IMAGE_TAG+x}" ]; then
  export IMAGE_TAG=v1.0.0
fi
if [ -z "${PYTHON_VERSION+x}" ]; then
  export PYTHON_VERSION=3.11
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "type-check" "setup-code-for-typecheck" "/nix/store/yxyij6cif1v3d2n25qzgh3bm1xilqkrb-setup-code-for-typecheck/bin/setup-code-for-typecheck" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "type-check" "run-mypy" "/nix/store/043ylhyryga6g2hz7hmkrbpmm62pa0dh-run-mypy/bin/run-mypy" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "type-check" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "lint, type-check" event "→" "Starting level"
run_parallel "lint|success()|" "type-check|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test" event "→" "Starting level"
run_parallel "test|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "build-image" event "→" "Starting level"
run_parallel "build-image|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "notify-failure, notify-success, push-image" event "→" "Starting level"
run_parallel "notify-failure|failure()|" "notify-success|success()|" "push-image|success()|" || {
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
