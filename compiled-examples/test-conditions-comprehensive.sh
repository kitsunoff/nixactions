#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-conditions-comprehensive-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-conditions-comprehensive"
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

job_test-always-condition() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-always-condition"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-always-condition" "first-fails" "/nix/store/4vb2lzd1p0wv58jaygpjp0d0bcvym8ld-first-fails/bin/first-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-always-condition" "always-runs" "/nix/store/iqpzpndwfqrz9cf6hc3id0578niy3kzb-always-runs/bin/always-runs" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-always-condition" "also-always-runs" "/nix/store/3vcw78f9lw3p2v3isv4s80rq736plivc-also-always-runs/bin/also-always-runs" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-always-condition" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-bash-env-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-bash-env-conditions"
if [ -z "${DEPLOY_ENV+x}" ]; then
  export DEPLOY_ENV=production
fi
if [ -z "${ENABLE_FEATURE+x}" ]; then
  export ENABLE_FEATURE=true
fi
if [ -z "${VERSION+x}" ]; then
  export VERSION=1.2.3
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-bash-env-conditions" "check-production" "/nix/store/dkmv3jw3bbq0v0123lm67b239r65ricq-check-production/bin/check-production" '[ "$DEPLOY_ENV" = "production" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-bash-env-conditions" "skip-staging" "/nix/store/glgiix1cpy6yj949xl1vrf50lzg7scyy-skip-staging/bin/skip-staging" '[ "$DEPLOY_ENV" = "staging" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-bash-env-conditions" "check-feature-enabled" "/nix/store/xaw8p42gjyc133am886ihck43by8cdh3-check-feature-enabled/bin/check-feature-enabled" '[ "$ENABLE_FEATURE" = "true" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-bash-env-conditions" "skip-feature-disabled" "/nix/store/g1abzm1gmfl13jn7qa1nbdy6rjbv5aa0-skip-feature-disabled/bin/skip-feature-disabled" '[ "$ENABLE_FEATURE" = "false" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-bash-env-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-command-substitution-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-command-substitution-conditions"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-command-substitution-conditions" "check-directory-not-empty" "/nix/store/4xvpp5dvq58gv9g3wz0ncp31brr1wgvi-check-directory-not-empty/bin/check-directory-not-empty" '[ "$(ls -A . | wc -l)" -gt 0 ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-command-substitution-conditions" "check-hostname" "/nix/store/34495n8v314jb7sh219nkn2igb3ci7k8-check-hostname/bin/check-hostname" '[ -n "$(hostname)" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-command-substitution-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-complex-bash-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-complex-bash-conditions"
if [ -z "${COUNT+x}" ]; then
  export COUNT=5
fi
if [ -z "${NAME+x}" ]; then
  export NAME=test
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-complex-bash-conditions" "numeric-comparison-gt" "/nix/store/44hw45q0449wa7dbhsl6a4xl3vhc0vs0-numeric-comparison-gt/bin/numeric-comparison-gt" '[ "$COUNT" -gt 3 ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-complex-bash-conditions" "numeric-comparison-lt" "/nix/store/i9k2lw018555j9gb9q52cli4g94m07w5-numeric-comparison-lt/bin/numeric-comparison-lt" '[ "$COUNT" -lt 3 ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-complex-bash-conditions" "string-pattern-match" "/nix/store/kpc68alpz780n1h3q9jsmkmrskc97b5r-string-pattern-match/bin/string-pattern-match" '[[ "$NAME" == *test* ]]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-complex-bash-conditions" "file-exists-check" "/nix/store/43k30vq1j9q6n9ysh9xvdjmz7dw3v9ri-file-exists-check/bin/file-exists-check" '[ -f "$JOB_ENV" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-complex-bash-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-condition-evaluation-order() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-condition-evaluation-order"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-condition-evaluation-order" "action-1-succeeds" "/nix/store/33swys31vmrlwak9f7l36b58kim0hgk4-action-1-succeeds/bin/action-1-succeeds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-condition-evaluation-order" "action-2-fails" "/nix/store/sf94bncrk6b6arcp7d30p3i60c0765q5-action-2-fails/bin/action-2-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-condition-evaluation-order" "action-3-skipped-on-success" "/nix/store/lzcibhdib02faa7klslvbwh30a3agbyy-action-3-skipped-on-success/bin/action-3-skipped-on-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-condition-evaluation-order" "action-4-runs-on-failure" "/nix/store/5432jl65b830d46287lalk2y2hl814lk-action-4-runs-on-failure/bin/action-4-runs-on-failure" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-condition-evaluation-order" "action-5-always" "/nix/store/7yg4wnn9w7mgvswlzzqnll8zgzqjc1r7-action-5-always/bin/action-5-always" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-condition-evaluation-order" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-empty-variable-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-empty-variable-conditions"
if [ -z "${EMPTY_VAR+x}" ]; then
  export EMPTY_VAR=''
fi
if [ -z "${SET_VAR+x}" ]; then
  export SET_VAR=value
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-empty-variable-conditions" "check-var-set" "/nix/store/hqcb99xviphjg2nhw1nah3hwpirhjxfi-check-var-set/bin/check-var-set" '[ -n "$SET_VAR" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-empty-variable-conditions" "check-var-empty" "/nix/store/xdysqpvscjfjiiam66b0g3g9i53pah9b-check-var-empty/bin/check-var-empty" '[ -z "$EMPTY_VAR" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-empty-variable-conditions" "check-var-not-empty-skip" "/nix/store/hdnvnlyn83agkmlx52fdcbswzvmdly5x-check-var-not-empty-skip/bin/check-var-not-empty-skip" '[ -n "$EMPTY_VAR" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-empty-variable-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-failure-condition() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-failure-condition"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-failure-condition" "first-fails" "/nix/store/4vb2lzd1p0wv58jaygpjp0d0bcvym8ld-first-fails/bin/first-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-failure-condition" "skip-on-failure" "/nix/store/wdycryikn3j9yc3bkkxsjj61y7ildg5n-skip-on-failure/bin/skip-on-failure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-failure-condition" "run-on-failure" "/nix/store/yjgknv2x45wl8fvw2js7b0s9cm9chk38-run-on-failure/bin/run-on-failure" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-failure-condition" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-logical-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-logical-conditions"
if [ -z "${DEBUG+x}" ]; then
  export DEBUG=false
fi
if [ -z "${ENV+x}" ]; then
  export ENV=production
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-logical-conditions" "and-condition-true" "/nix/store/ij3hsgyh4wvhp1gmm2dr8qxfk4cwxzn0-and-condition-true/bin/and-condition-true" '[ "$ENV" = "production" ] && [ "$DEBUG" = "false" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-logical-conditions" "and-condition-false" "/nix/store/87vmwbckamyaacjrlpqcf329pqcc61r7-and-condition-false/bin/and-condition-false" '[ "$ENV" = "production" ] && [ "$DEBUG" = "true" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-logical-conditions" "or-condition-true" "/nix/store/98254w3dnxq1wllilvj3lv5x76rxg1qg-or-condition-true/bin/or-condition-true" '[ "$ENV" = "production" ] || [ "$DEBUG" = "true" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-logical-conditions" "or-condition-all-false" "/nix/store/ngr7lyv1annl9an8jj7j0m8g3gcalk8h-or-condition-all-false/bin/or-condition-all-false" '[ "$ENV" = "staging" ] || [ "$ENV" = "development" ]' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-logical-conditions" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-mixed-condition-sequence() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-mixed-condition-sequence"
if [ -z "${STEP+x}" ]; then
  export STEP=build
fi
ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-mixed-condition-sequence" "step-1-build" "/nix/store/rbkx2428fmj4j6jyll9nwdg9mdagawkp-step-1-build/bin/step-1-build" '[ "$STEP" = "build" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-mixed-condition-sequence" "step-2-test" "/nix/store/30ws2dn98zlxw5q1jy92xyn8hyrpx0vl-step-2-test/bin/step-2-test" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-mixed-condition-sequence" "step-3-deploy-skipped" "/nix/store/5gc3jd84vh4fxs0vjlgx5qvvrh7bxsly-step-3-deploy-skipped/bin/step-3-deploy-skipped" '[ "$STEP" = "deploy" ]' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-mixed-condition-sequence" "step-4-cleanup" "/nix/store/mk651b0xslciqmfj84zxs674z3cnafsz-step-4-cleanup/bin/step-4-cleanup" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-mixed-condition-sequence" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-success-condition() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-success-condition"

ACTION_FAILED=false
# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-success-condition" "first-succeeds" "/nix/store/z0a193qk9vahwkpjh7dkwdw22w5xcd46-first-succeeds/bin/first-succeeds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

# Set action-level environment variables

# Set retry environment variables

# Set timeout environment variables

run_action "test-success-condition" "second-runs-on-success" "/nix/store/s3w2vzmp9007am0k16815pdw4rbwippb-second-runs-on-success/bin/second-runs-on-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-success-condition" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 10 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "test-success-condition" event "→" "Starting level"
run_parallel "test-success-condition|success()|" || {
  _log_workflow level 0 event "✗" "Level failed"
  exit 1
}

_log_workflow level 1 jobs "test-failure-condition" event "→" "Starting level"
run_parallel "test-failure-condition|success()|1" || {
  _log_workflow level 1 event "✗" "Level failed"
  exit 1
}

_log_workflow level 2 jobs "test-always-condition" event "→" "Starting level"
run_parallel "test-always-condition|success()|1" || {
  _log_workflow level 2 event "✗" "Level failed"
  exit 1
}

_log_workflow level 3 jobs "test-bash-env-conditions" event "→" "Starting level"
run_parallel "test-bash-env-conditions|success()|" || {
  _log_workflow level 3 event "✗" "Level failed"
  exit 1
}

_log_workflow level 4 jobs "test-complex-bash-conditions" event "→" "Starting level"
run_parallel "test-complex-bash-conditions|success()|" || {
  _log_workflow level 4 event "✗" "Level failed"
  exit 1
}

_log_workflow level 5 jobs "test-logical-conditions" event "→" "Starting level"
run_parallel "test-logical-conditions|success()|" || {
  _log_workflow level 5 event "✗" "Level failed"
  exit 1
}

_log_workflow level 6 jobs "test-command-substitution-conditions" event "→" "Starting level"
run_parallel "test-command-substitution-conditions|success()|" || {
  _log_workflow level 6 event "✗" "Level failed"
  exit 1
}

_log_workflow level 7 jobs "test-mixed-condition-sequence" event "→" "Starting level"
run_parallel "test-mixed-condition-sequence|success()|1" || {
  _log_workflow level 7 event "✗" "Level failed"
  exit 1
}

_log_workflow level 8 jobs "test-empty-variable-conditions" event "→" "Starting level"
run_parallel "test-empty-variable-conditions|success()|" || {
  _log_workflow level 8 event "✗" "Level failed"
  exit 1
}

_log_workflow level 9 jobs "test-condition-evaluation-order" event "→" "Starting level"
run_parallel "test-condition-evaluation-order|success()|1" || {
  _log_workflow level 9 event "✗" "Level failed"
  exit 1
}

  workflow_summary || exit 1
}

main "$@"
