#!/usr/bin/env bash
set -euo pipefail

# NixActions workflow - executors own workspace (v2)

# Generate workflow ID
WORKFLOW_ID="test-action-conditions-$(date +%s)-$$"
export WORKFLOW_ID

# Setup artifacts directory on control node
NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

# Job status tracking
declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false

# Trap cancellation
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

# Check if condition is met
check_condition() {
  local condition=$1
  
  case "$condition" in
    success\(\))
      if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
        return 1  # Has failures
      fi
      ;;
    failure\(\))
      if [ ${#FAILED_JOBS[@]} -eq 0 ]; then
        return 1  # No failures
      fi
      ;;
    always\(\))
      return 0  # Always run
      ;;
    cancelled\(\))
      if [ "$WORKFLOW_CANCELLED" = "false" ]; then
        return 1
      fi
      ;;
    *)
      echo "Unknown condition: $condition"
      return 1
      ;;
  esac
  
  return 0
}

# Run single job with condition check
run_job() {
  local job_name=$1
  local condition=${2:-success()}
  local continue_on_error=${3:-false}
  
  # Check condition
  if ! check_condition "$condition"; then
    echo "⊘ Skipping $job_name (condition not met: $condition)"
    JOB_STATUS[$job_name]="skipped"
    return 0
  fi
  
  # Execute job in subshell (isolation by design)
  if ( job_$job_name ); then
    echo "✓ Job $job_name succeeded"
    JOB_STATUS[$job_name]="success"
    return 0
  else
    local exit_code=$?
    echo "✗ Job $job_name failed (exit code: $exit_code)"
    FAILED_JOBS+=("$job_name")
    JOB_STATUS[$job_name]="failure"
    
    if [ "$continue_on_error" = "true" ]; then
      echo "→ Continuing despite failure (continueOnError: true)"
      return 0
    else
      return $exit_code
    fi
  fi
}

# Run jobs in parallel
run_parallel() {
  local -a job_specs=("$@")
  local -a pids=()
  local failed=false
  
  # Start all jobs
  for spec in "${job_specs[@]}"; do
    IFS='|' read -r job_name condition continue_on_error <<< "$spec"
    
    # Run in background
    (
      run_job "$job_name" "$condition" "$continue_on_error"
    ) &
    pids+=($!)
  done
  
  # Wait for all jobs
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=true
    fi
  done
  
  if [ "$failed" = "true" ]; then
    # Check if we should stop
    for spec in "${job_specs[@]}"; do
      IFS='|' read -r job_name condition continue_on_error <<< "$spec"
      if [ "${JOB_STATUS[$job_name]:-unknown}" = "failure" ] && [ "$continue_on_error" != "true" ]; then
        echo "⊘ Stopping workflow due to job failure: $job_name"
        return 1
      fi
    done
  fi
  
  return 0
}

# Job functions
job_test-always() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-always"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test-always"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-fails ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action1-fails (condition: $ACTION_CONDITION)"
else
  echo "→ action1-fails"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action1-fails failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === action2-always-runs ===

# Check action condition
_should_run=true
ACTION_CONDITION="always()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action2-always-runs (condition: $ACTION_CONDITION)"
else
  echo "→ action2-always-runs"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/7ncw0p6ggmh42595dnhbmqf5kw93jldr-action2-always-runs/bin/action2-always-runs
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action2-always-runs failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  echo ""
  echo "✗ Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-bash-conditions() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-bash-conditions"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test-bash-conditions"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment
export DEPLOY_ENABLED=true
export ENVIRONMENT=production

# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === setup ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping setup (condition: $ACTION_CONDITION)"
else
  echo "→ setup"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/fk8cb0frdfr2nngqzhyfk27lv4d9jgkr-setup/bin/setup
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action setup failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === deploy-to-production ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$ENVIRONMENT" = "production" ]"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping deploy-to-production (condition: $ACTION_CONDITION)"
else
  echo "→ deploy-to-production"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/6h03g3fvi300rcqgk58105a0q4kpi31n-deploy-to-production/bin/deploy-to-production
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action deploy-to-production failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === deploy-to-staging ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$ENVIRONMENT" = "staging" ]"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping deploy-to-staging (condition: $ACTION_CONDITION)"
else
  echo "→ deploy-to-staging"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/1fdj6cam90kbb3vjq9s9vl04gxjk7nqa-deploy-to-staging/bin/deploy-to-staging
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action deploy-to-staging failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === notify-if-deploy-enabled ===

# Check action condition
_should_run=true
ACTION_CONDITION="[ "$DEPLOY_ENABLED" = "true" ]"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping notify-if-deploy-enabled (condition: $ACTION_CONDITION)"
else
  echo "→ notify-if-deploy-enabled"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/qgp5lsl1kj8mdgsm61icpyfarzx81ys4-notify-if-deploy-enabled/bin/notify-if-deploy-enabled
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action notify-if-deploy-enabled failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  echo ""
  echo "✗ Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-complex() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-complex"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test-complex"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === build ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping build (condition: $ACTION_CONDITION)"
else
  echo "→ build"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/vd259nzm2cq5fk0wlmp0lp8mskr03ylb-build/bin/build
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action build failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === test ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping test (condition: $ACTION_CONDITION)"
else
  echo "→ test"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/rsiv1296dm34mzx2bbndr89v0acsfmws-test/bin/test
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action test failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === deploy-on-success ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping deploy-on-success (condition: $ACTION_CONDITION)"
else
  echo "→ deploy-on-success"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/g0ay3wg0dy8vad0rz0vkjamvy8ck80zy-deploy-on-success/bin/deploy-on-success
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action deploy-on-success failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === notify-on-failure ===

# Check action condition
_should_run=true
ACTION_CONDITION="failure()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping notify-on-failure (condition: $ACTION_CONDITION)"
else
  echo "→ notify-on-failure"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/pr2qy8r8i2bpk6gjxab80rrc7jgb5pvk-notify-on-failure/bin/notify-on-failure
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action notify-on-failure failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === cleanup ===

# Check action condition
_should_run=true
ACTION_CONDITION="always()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping cleanup (condition: $ACTION_CONDITION)"
else
  echo "→ cleanup"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/yyaw5fhdqhxwa7d2cxpwrg3c9ifvhnml-cleanup/bin/cleanup
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action cleanup failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  echo ""
  echo "✗ Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-failure() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-failure"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test-failure"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-fails ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action1-fails (condition: $ACTION_CONDITION)"
else
  echo "→ action1-fails"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action1-fails failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === action2-success-should-skip ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action2-success-should-skip (condition: $ACTION_CONDITION)"
else
  echo "→ action2-success-should-skip"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/q4ckdpggvgp79c4nrjycmv6zcnvvww9c-action2-success-should-skip/bin/action2-success-should-skip
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action2-success-should-skip failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === action3-failure-should-run ===

# Check action condition
_should_run=true
ACTION_CONDITION="failure()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action3-failure-should-run (condition: $ACTION_CONDITION)"
else
  echo "→ action3-failure-should-run"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/hx5f67yrvvf46vibrm45birfsggd1ikw-action3-failure-should-run/bin/action3-failure-should-run
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action3-failure-should-run failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  echo ""
  echo "✗ Job failed due to action failures"
  exit 1
fi

  
  
}


job_test-success() {
  # Setup workspace for this job
  # Lazy init - only create if not exists
if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
  WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
  mkdir -p "$WORKSPACE_DIR_LOCAL"
  export WORKSPACE_DIR_LOCAL
  echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
fi

  
  
  
  # Execute job via executor
  # Create isolated directory for this job
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test-success"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

# Create job-specific env file INSIDE workspace
JOB_ENV="$JOB_DIR/.job-env"
touch "$JOB_ENV"
export JOB_ENV

echo "╔════════════════════════════════════════╗"
echo "║ JOB: test-success"
echo "║ EXECUTOR: local"
echo "║ WORKDIR: $JOB_DIR"
echo "╚════════════════════════════════════════╝"

# Set job-level environment


# Track action failures
ACTION_FAILED=false

# Execute action derivations as separate processes
# === action1-succeeds ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action1-succeeds (condition: $ACTION_CONDITION)"
else
  echo "→ action1-succeeds"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/i6imb4psjdmx2y3knpxwkp75l9v899vz-action1-succeeds/bin/action1-succeeds
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action1-succeeds failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# === action2-with-success-condition ===

# Check action condition
_should_run=true
ACTION_CONDITION="success()"
case "$ACTION_CONDITION" in
  'always()')
    # Always run
    ;;
  'success()')
    # Run only if no previous action failed
    if [ "$ACTION_FAILED" = "true" ]; then
      _should_run=false
    fi
    ;;
  'failure()')
    # Run only if a previous action failed
    if [ "$ACTION_FAILED" = "false" ]; then
      _should_run=false
    fi
    ;;
  'cancelled()')
    # Would need workflow-level cancellation support
    _should_run=false
    ;;
  *)
    # Bash script condition - evaluate it
    if ! ($ACTION_CONDITION); then
      _should_run=false
    fi
    ;;
esac

if [ "$_should_run" = "false" ]; then
  echo "⊘ Skipping action2-with-success-condition (condition: $ACTION_CONDITION)"
else
  echo "→ action2-with-success-condition"
  
  # Source JOB_ENV and export all variables before running action
  set -a
  [ -f "$JOB_ENV" ] && source "$JOB_ENV" || true
  set +a
  
  # Execute action as separate process
  /nix/store/hvx9vkmgf588vrrc8pq1qmrgvn89jcic-action2-with-success-condition/bin/action2-with-success-condition
  _action_exit_code=$?
  
  # Track failure for subsequent actions
  if [ $_action_exit_code -ne 0 ]; then
    ACTION_FAILED=true
    echo "✗ Action action2-with-success-condition failed (exit code: $_action_exit_code)"
    # Don't exit immediately - let conditions handle flow
  fi
fi


# Fail job if any action failed
if [ "$ACTION_FAILED" = "true" ]; then
  echo ""
  echo "✗ Job failed due to action failures"
  exit 1
fi

  
  
}


# Main execution
main() {
  echo "════════════════════════════════════════"
  echo " Workflow: test-action-conditions"
  echo " Execution: GitHub Actions style (parallel)"
  echo " Levels: 5"
  echo "════════════════════════════════════════"
  echo ""
  
  # Execute level by level
  echo "→ Level 0: test-success"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-success|success()|" || {
    echo "⊘ Level 0 failed"
    exit 1
  }

echo ""


echo "→ Level 1: test-failure"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-failure|success()|" || {
    echo "⊘ Level 1 failed"
    exit 1
  }

echo ""


echo "→ Level 2: test-always"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-always|success()|" || {
    echo "⊘ Level 2 failed"
    exit 1
  }

echo ""


echo "→ Level 3: test-bash-conditions"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-bash-conditions|success()|" || {
    echo "⊘ Level 3 failed"
    exit 1
  }

echo ""


echo "→ Level 4: test-complex"

# Build job specs (name|condition|continueOnError)
run_parallel \
   "test-complex|success()|" || {
    echo "⊘ Level 4 failed"
    exit 1
  }

echo ""

  
  # Final report
  echo "════════════════════════════════════════"
  if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
    echo "✗ Workflow failed"
    echo ""
    echo "Failed jobs:"
    printf '  - %s\n' "${FAILED_JOBS[@]}"
    echo ""
    echo "Job statuses:"
    for job in test-always test-bash-conditions test-complex test-failure test-success; do
      echo "  $job: ${JOB_STATUS[$job]:-unknown}"
    done
    exit 1
  else
    echo "✓ Workflow completed successfully"
    echo ""
    echo "All jobs succeeded:"
    for job in test-always test-bash-conditions test-complex test-failure test-success; do
      if [ "${JOB_STATUS[$job]:-unknown}" = "success" ]; then
        echo "  ✓ $job"
      elif [ "${JOB_STATUS[$job]:-unknown}" = "skipped" ]; then
        echo "  ⊘ $job (skipped)"
      fi
    done
  fi
  echo "════════════════════════════════════════"
}

main "$@"
