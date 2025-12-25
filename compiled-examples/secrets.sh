#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="secrets-workflow-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="secrets-workflow"
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
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi

# ============================================
# Job Functions
# ============================================

job_deploy-with-secrets() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "deploy-with-secrets"
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${DEPLOY_TARGET+x}" ]; then
  export DEPLOY_TARGET=staging-cluster
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "deploy-with-secrets" "simulate-deployment" "/nix/store/28dj7grrqaha34ix9534d9kkrg69w42w-simulate-deployment/bin/simulate-deployment" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy-with-secrets" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_override-env() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "override-env"
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi
if [ -z "${LOG_LEVEL+x}" ]; then
  export LOG_LEVEL=info
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "override-env" "default-log-level" "/nix/store/71r1zigsvky6vddvj9k1fyj63pgha6iz-default-log-level/bin/default-log-level" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables
export LOG_LEVEL=debug
# Set retry environment variables

run_action "override-env" "override-log-level" "/nix/store/g0ffhn80vpq0b0rlsldqkfg3r3vs9vj4-override-log-level/bin/override-log-level" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "override-env" "back-to-default" "/nix/store/sh5fj2cv3j40lm3lmhxbkwzagx2qf1dz-back-to-default/bin/back-to-default" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "override-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_report() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "report"
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "report" "secrets-demo-report" "/nix/store/zbgfz2cqpd8q1s7h3hl91lfkdgp25fhk-secrets-demo-report/bin/secrets-demo-report" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "report" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_use-runtime-env() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "use-runtime-env"
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "use-runtime-env" "check-optional-secrets" "/nix/store/bihb30j9hshmisrcjg05zd1c0lvy7al5-check-optional-secrets/bin/check-optional-secrets" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "use-runtime-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate-env() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "validate-env"
if [ -z "${APP_NAME+x}" ]; then
  export APP_NAME=nixactions-demo
fi
if [ -z "${DATABASE_HOST+x}" ]; then
  export DATABASE_HOST=localhost
fi
if [ -z "${DATABASE_PORT+x}" ]; then
  export DATABASE_PORT=5432
fi
if [ -z "${ENVIRONMENT+x}" ]; then
  export ENVIRONMENT=staging
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

run_action "validate-env" "require-env" "/nix/store/mjm37dq9dc7y1g82lr42pjq8y676gmdd-require-env/bin/require-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

run_action "validate-env" "show-config" "/nix/store/9y4lixxlnx47bdyy3m4sg6w4bgn9pc4p-show-config/bin/show-config" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "validate-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 5 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "validate-env" event "→" "Starting level"
run_parallel "validate-env|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "use-runtime-env" event "→" "Starting level"
run_parallel "use-runtime-env|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "override-env" event "→" "Starting level"
run_parallel "override-env|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "deploy-with-secrets" event "→" "Starting level"
run_parallel "deploy-with-secrets|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "report" event "→" "Starting level"
run_parallel "report|always()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
