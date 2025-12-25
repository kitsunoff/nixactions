#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="test-action-conditions-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="test-action-conditions"
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

job_test-always() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-always"

ACTION_FAILED=false

run_action "test-always" "action1-fails" "/nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-always" "action2-always-runs" "/nix/store/7ncw0p6ggmh42595dnhbmqf5kw93jldr-action2-always-runs/bin/action2-always-runs" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "test-always" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_test-bash-conditions() {
      source /nix/store/gjwg64hal8wgjdz7mmhgdyq4c7qbqpfr-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "test-bash-conditions"
export DEPLOY_ENABLED=true
export ENVIRONMENT=production
ACTION_FAILED=false

run_action "test-bash-conditions" "setup" "/nix/store/fk8cb0frdfr2nngqzhyfk27lv4d9jgkr-setup/bin/setup" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-bash-conditions" "deploy-to-production" "/nix/store/6h03g3fvi300rcqgk58105a0q4kpi31n-deploy-to-production/bin/deploy-to-production" '[ "$ENVIRONMENT" = "production" ]' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-bash-conditions" "deploy-to-staging" "/nix/store/1fdj6cam90kbb3vjq9s9vl04gxjk7nqa-deploy-to-staging/bin/deploy-to-staging" '[ "$ENVIRONMENT" = "staging" ]' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-bash-conditions" "notify-if-deploy-enabled" "/nix/store/qgp5lsl1kj8mdgsm61icpyfarzx81ys4-notify-if-deploy-enabled/bin/notify-if-deploy-enabled" '[ "$DEPLOY_ENABLED" = "true" ]' 'date +%s%N 2>/dev/null || echo "0"'

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

run_action "test-complex" "build" "/nix/store/vd259nzm2cq5fk0wlmp0lp8mskr03ylb-build/bin/build" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-complex" "test" "/nix/store/rsiv1296dm34mzx2bbndr89v0acsfmws-test/bin/test" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-complex" "deploy-on-success" "/nix/store/g0ay3wg0dy8vad0rz0vkjamvy8ck80zy-deploy-on-success/bin/deploy-on-success" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-complex" "notify-on-failure" "/nix/store/pr2qy8r8i2bpk6gjxab80rrc7jgb5pvk-notify-on-failure/bin/notify-on-failure" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-complex" "cleanup" "/nix/store/yyaw5fhdqhxwa7d2cxpwrg3c9ifvhnml-cleanup/bin/cleanup" 'always()' 'date +%s%N 2>/dev/null || echo "0"'

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

run_action "test-failure" "action1-fails" "/nix/store/y19zr5ryc6a555xa59bp8fj624qsksiw-action1-fails/bin/action1-fails" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-failure" "action2-success-should-skip" "/nix/store/q4ckdpggvgp79c4nrjycmv6zcnvvww9c-action2-success-should-skip/bin/action2-success-should-skip" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-failure" "action3-failure-should-run" "/nix/store/hx5f67yrvvf46vibrm45birfsggd1ikw-action3-failure-should-run/bin/action3-failure-should-run" 'failure()' 'date +%s%N 2>/dev/null || echo "0"'

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

run_action "test-success" "action1-succeeds" "/nix/store/i6imb4psjdmx2y3knpxwkp75l9v899vz-action1-succeeds/bin/action1-succeeds" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "test-success" "action2-with-success-condition" "/nix/store/hvx9vkmgf588vrrc8pq1qmrgvn89jcic-action2-with-success-condition/bin/action2-with-success-condition" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
