#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="python-ci-cd-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="python-ci-cd"
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

job_build-image() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "build-image"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "build-image" "checkout-code" "/nix/store/svw5qkwjaps8904ciii9d5h9dns354ig-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build-image" "prepare-build-context" "/nix/store/9h7ix2ilf3iqar6n151rsjxnh197hkgq-prepare-build-context/bin/prepare-build-context" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build-image" "build-docker-image" "/nix/store/7qvlkx4rlwlx1n6jgq30bz7i9i0dy6s4-build-docker-image/bin/build-docker-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "build-image" "scan-image" "/nix/store/k59qwjwgyqahazfkmyxxmlsyvj5g6spx-scan-image/bin/scan-image" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "build-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_cleanup() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "cleanup"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "cleanup" "cleanup-temp-files" "/nix/store/s6lf0sphzip0741vnl1sf8smqqsjms2c-cleanup-temp-files/bin/cleanup-temp-files" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "cleanup" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_lint() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "lint"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "lint" "checkout-code" "/nix/store/c0dhi8jydadpzc58yaffxl4ixgd0hqff-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "lint" "lint-python" "/nix/store/lvqbr3lk1gw5r2bqmxky1k1zc3i0kw92-lint-python/bin/lint-python" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "lint" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-failure() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-failure"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "notify-failure" "send-failure-notification" "/nix/store/f815w7sw8aja53a5kfjyqicqf8nxlx7v-send-failure-notification/bin/send-failure-notification" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-failure" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_notify-success() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "notify-success"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "notify-success" "send-success-notification" "/nix/store/6hi0c44ykwh1wydhvjcvp5mq4f620ib2-send-success-notification/bin/send-success-notification" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "notify-success" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_push-image() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "push-image"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "push-image" "push-to-registry" "/nix/store/rza33asqiczadan9h4d3anq9vjy811l4-push-to-registry/bin/push-to-registry" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "push-image" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "test" "checkout-code" "/nix/store/y509h1x395wk9saaxlhs3pa6sn3vp68r-checkout-code/bin/checkout-code" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "install-dependencies" "/nix/store/zxg75zf1ahbg19p12rs3rg8r9434pgvh-install-dependencies/bin/install-dependencies" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "run-unit-tests" "/nix/store/nx55vq678ipkzrv4inf8nziig1chzzmj-run-unit-tests/bin/run-unit-tests" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test" "test-app-execution" "/nix/store/r6byhsbmb280yjrm4x9b0cxsf1kdn31w-test-app-execution/bin/test-app-execution" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_type-check() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "type-check"
export DOCKER_REGISTRY=registry.example.com
export IMAGE_NAME=math-app
export IMAGE_TAG=v1.0.0
export PYTHON_VERSION=3.11
ACTION_FAILED=false

run_action "type-check" "setup-code-for-typecheck" "/nix/store/r5fk48am7gha455sjqi3515pmr4naxz0-setup-code-for-typecheck/bin/setup-code-for-typecheck" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "type-check" "run-mypy" "/nix/store/mlkn0qyj09f3kn5qag3mnwlk9w06bf0k-run-mypy/bin/run-mypy" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
