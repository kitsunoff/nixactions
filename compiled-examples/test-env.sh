#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-env-propagation-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-env-propagation"
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


# ============================================
# Job Functions
# ============================================

job_summary() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "summary"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "summary" "summary" "/nix/store/pkyfdj391xmqyd1ds16nx05xyvhshafb-summary/bin/summary" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "summary" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-export-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-export-vars"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-export-vars" "without-export" "/nix/store/5agd51bavgvjw2x7g1ff2m263gkx2rg6-without-export/bin/without-export" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-export-vars" "with-export" "/nix/store/jzrr3y787h2hkq83n89csdac5xd3l244-with-export/bin/with-export" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-export-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-local-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-local-vars"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-local-vars" "set-local-var" "/nix/store/qm6v6f2742xadnyyl1zz1whnzw38ckyh-set-local-var/bin/set-local-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-local-vars" "try-use-local" "/nix/store/6gbs4yhpm1f8c0f8rav54jvj0g5rzap5-try-use-local/bin/try-use-local" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-local-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-regular-vars() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-regular-vars"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-regular-vars" "set-regular-var" "/nix/store/y39wb8yl32lqx3swv09x8zd5k51dsf9l-set-regular-var/bin/set-regular-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-regular-vars" "use-regular-var" "/nix/store/snxrhrgyjd94gab5lqzcachi970b7yv1-use-regular-var/bin/use-regular-var" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-regular-vars" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 4 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-regular-vars" event "→" "Starting level"
run_parallel "test-regular-vars|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-local-vars" event "→" "Starting level"
run_parallel "test-local-vars|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-export-vars" event "→" "Starting level"
run_parallel "test-export-vars|success()|" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "summary" event "→" "Starting level"
run_parallel "summary|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
