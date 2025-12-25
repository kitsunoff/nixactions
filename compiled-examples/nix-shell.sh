#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="nix-shell-example-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="nix-shell-example"
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

job_api-test() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "api-test"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "api-test" "nix-shell" "/nix/store/sin4b8zxbgrzhajjg1rrkd1jzhrzh8g1-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "api-test" "Fetch and parse GitHub API" "/nix/store/1mmdg71sd6rxya3i533zv33fyy3yg7gy-Fetch-and-parse-GitHub-API/bin/'Fetch and parse GitHub API'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "api-test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_file-processing() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "file-processing"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "file-processing" "nix-shell" "/nix/store/4gxsszd224dnic3mqjj1n5fy7fmsvxil-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "file-processing" "Process files" "/nix/store/4nj9krizqxrppaw49iznz73xrrlvs5rw-Process-files/bin/'Process files'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "file-processing" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_multi-tool() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "multi-tool"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "multi-tool" "nix-shell" "/nix/store/nxapn0a8qmf5m0hji94wlhpawaiqnyk9-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "multi-tool" "Use git and tree" "/nix/store/pibvrl5n6zirgc78hpwswfmy3zwy6iy8-Use-git-and-tree/bin/'Use git and tree'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "multi-tool" "nix-shell" "/nix/store/lw82g92hlm6xvni2ra948xnawyp9v4rn-nix-shell/bin/nix-shell" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "multi-tool" "System tools available" "/nix/store/qqcl8wg1v24p3gjq1q0kcwv8vjd9w1b3-System-tools-available/bin/'System tools available'" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "multi-tool" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 2 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "api-test, file-processing" event "→" "Starting level"
run_parallel "api-test|success()|" "file-processing|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "multi-tool" event "→" "Starting level"
run_parallel "multi-tool|success()|" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
