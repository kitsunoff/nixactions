#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="python-ci-simple-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="python-ci-simple"
export NIXACTIONS_LOG_FORMAT=${NIXACTIONS_LOG_FORMAT:-structured}

source /nix/store/p95kzip1952gbhfggns20djl5fwgs5sk-nixactions-logging/bin/nixactions-logging
source /nix/store/2r76x2y7xbsx2fhfhkxrxszpckydci7y-nixactions-retry/bin/nixactions-retry
source /nix/store/1mgqdp33xiddrm2va94abw7l8wdvzz0q-nixactions-runtime/bin/nixactions-runtime

NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR

declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false
trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM

job_build() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build"

ACTION_FAILED=false

run_action "build" "action" "/nix/store/1p4ddvv6dpmddgb687maxcx88j474rgi-action/bin/action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build" "build-image" "/nix/store/7lgpch8cfclqhn5bbcwfxnxi0g30jw54-build-image/bin/build-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"

ACTION_FAILED=false

run_action "lint" "action" "/nix/store/1p4ddvv6dpmddgb687maxcx88j474rgi-action/bin/action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "lint" "lint" "/nix/store/nmqgnazmwfqm50qaqk1mbqbrjbh16m0c-lint/bin/lint" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"

ACTION_FAILED=false

run_action "test" "action" "/nix/store/1p4ddvv6dpmddgb687maxcx88j474rgi-action/bin/action" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "install-and-test" "/nix/store/85mrvakycyarwr07f0rl8v7f8ivrsb25-install-and-test/bin/install-and-test" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}


main() {
  _log_workflow levels 3 event "▶" "Workflow starting"
  _log_workflow level 0 jobs "lint" event "→" "Starting level"
run_parallel "lint|success()|" || {
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

  workflow_summary || exit 1
}

main "$@"
