#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-action-conditions-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-action-conditions"
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

job_test-always() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-always"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-always" "action1-fails" "/nix/store/9pwf11z54rrygzdr81flip0in8l5rslx-action1-fails/bin/action1-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-always" "action2-always-runs" "/nix/store/kswyhnj5aa1qwr7mci10raq6mai9rnas-action2-always-runs/bin/action2-always-runs" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-always" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-bash-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-bash-conditions"
if [ -z "${DEPLOY_ENABLED+x}" ]; then
  export DEPLOY_ENABLED=true
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-bash-conditions" "setup" "/nix/store/qfig2640bcias71h6f41pg1kskabimx8-setup/bin/setup" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-bash-conditions" "deploy-to-production" "/nix/store/a75hqjb2j3mb4d68qm32bd9cslhq9sl8-deploy-to-production/bin/deploy-to-production" '[ "$ENVIRONMENT" = "production" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-bash-conditions" "deploy-to-staging" "/nix/store/0v9x2vdmcgg2darmxbwwj2m7z6zy116m-deploy-to-staging/bin/deploy-to-staging" '[ "$ENVIRONMENT" = "staging" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-bash-conditions" "notify-if-deploy-enabled" "/nix/store/r5qz3m358937aka9gvcal26hhr5jqbjs-notify-if-deploy-enabled/bin/notify-if-deploy-enabled" '[ "$DEPLOY_ENABLED" = "true" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-bash-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-complex() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-complex"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-complex" "build" "/nix/store/ppnfb91dshhi4mjw0xn2k4vykcfcq87h-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-complex" "test" "/nix/store/pakvdzj083nm1pm3ym1vb9ssyrwjsm6c-test/bin/test" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-complex" "deploy-on-success" "/nix/store/v2ng2fypb8lf8k9p8405mkipc2ji2r0j-deploy-on-success/bin/deploy-on-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-complex" "notify-on-failure" "/nix/store/alkr5yb1pxaxbabh2s0a7ryc2d0m9ayr-notify-on-failure/bin/notify-on-failure" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-complex" "cleanup" "/nix/store/vdvbyy0im2mh4hii01qhypipfy7mxiyf-cleanup/bin/cleanup" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-complex" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-failure() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-failure"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-failure" "action1-fails" "/nix/store/9pwf11z54rrygzdr81flip0in8l5rslx-action1-fails/bin/action1-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-failure" "action2-success-should-skip" "/nix/store/f40srhqc9msjywjdvybzgv6i5f457clw-action2-success-should-skip/bin/action2-success-should-skip" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-failure" "action3-failure-should-run" "/nix/store/b2bb5fawsfaq87cnfs6sbaxi388a6ryx-action3-failure-should-run/bin/action3-failure-should-run" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-success() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-success"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "test-success" "action1-succeeds" "/nix/store/iakkb5z35vgkzm0z7ma3xakh52ncc2cm-action1-succeeds/bin/action1-succeeds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "test-success" "action2-with-success-condition" "/nix/store/7k4kpll4c3q2zyxl995500fvackmb9ik-action2-with-success-condition/bin/action2-with-success-condition" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-success" event "→" "Starting level"
run_parallel "test-success|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-failure" event "→" "Starting level"
run_parallel "test-failure|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-always" event "→" "Starting level"
run_parallel "test-always|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "test-bash-conditions" event "→" "Starting level"
run_parallel "test-bash-conditions|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "test-complex" event "→" "Starting level"
run_parallel "test-complex|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
