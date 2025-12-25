#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="complete-ci-pipeline-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="complete-ci-pipeline"
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
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "build" "build-artifacts" "/nix/store/dkcfh9nlqpxnzva83r7fc3lx8qgahghi-build-artifacts/bin/build-artifacts" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_cleanup() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "cleanup"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "cleanup" "cleanup-resources" "/nix/store/9cj3j1gdibpni33kxrns6y4mzrh3vkqm-cleanup-resources/bin/cleanup-resources" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "cleanup" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_deploy() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "deploy"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "deploy" "deploy-to-staging" "/nix/store/w9q1fl3h0mi04qjdkif4amavyc1ks5gm-deploy-to-staging/bin/deploy-to-staging" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"
export BUILD_ENV=ci
export LINT_MODE=strict
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "lint" "lint-nix" "/nix/store/fads7z81s56jcszarmqiaaqf83z0f0vx-lint-nix/bin/lint-nix" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-failure() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-failure"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "notify-failure" "notify-failure" "/nix/store/m2j8m38qk6hff8am5iz8mdvr0sh2zfyc-notify-failure/bin/notify-failure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-success() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-success"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "notify-success" "notify-success" "/nix/store/ikkn44a2l6nsw0cq3hrmx3gyzxr5rw0r-notify-success/bin/notify-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_security() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "security"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "security" "security-scan" "/nix/store/243fwxgfk7h9g05d5gv07qrsqy83mi8r-security-scan/bin/security-scan" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "security" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "test" "run-tests" "/nix/store/32mn4m5rm4zvvxnw8cfyizbr81cjmxv0-run-tests/bin/run-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "validate"
export BUILD_ENV=ci
export PROJECT_NAME=nixactions
ACTION_FAILED=false

run_action "validate" "validate-structure" "/nix/store/24ky0w20c7450cwxvnhir88zhcq8f2dp-validate-structure/bin/validate-structure" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
