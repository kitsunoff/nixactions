#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_ID="secrets-workflow-$(date +%s)-$$"
export WORKFLOW_ID WORKFLOW_NAME="secrets-workflow"
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

job_deploy-with-secrets() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "deploy-with-secrets"
export APP_NAME=nixactions-demo
export DEPLOY_TARGET=staging-cluster
export ENVIRONMENT=staging
ACTION_FAILED=false

run_action "deploy-with-secrets" "simulate-deployment" "/nix/store/9gw2wziw4jw6qdddhgpl3kpqkhiyjpjc-simulate-deployment/bin/simulate-deployment" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "deploy-with-secrets" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_override-env() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "override-env"
export APP_NAME=nixactions-demo
export ENVIRONMENT=staging
export LOG_LEVEL=info
ACTION_FAILED=false

run_action "override-env" "default-log-level" "/nix/store/5s16rdyyqxa807ydixcr2dqnp7324nn0-default-log-level/bin/default-log-level" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "override-env" "override-log-level" "/nix/store/mcf3m48q9dwzjz15psksyyqkyqgnvxfc-override-log-level/bin/override-log-level" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "override-env" "back-to-default" "/nix/store/5zx4ig9vn1y648ywdyj426ymjm7yj98a-back-to-default/bin/back-to-default" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "override-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_report() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "report"
export APP_NAME=nixactions-demo
export ENVIRONMENT=staging
ACTION_FAILED=false

run_action "report" "secrets-demo-report" "/nix/store/mxqih5qyx4wj4kbnjj3s82616x8qksn2-secrets-demo-report/bin/secrets-demo-report" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "report" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_use-runtime-env() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "use-runtime-env"
export APP_NAME=nixactions-demo
export ENVIRONMENT=staging
ACTION_FAILED=false

run_action "use-runtime-env" "check-optional-secrets" "/nix/store/vn2vvf0ikql6q0my2jgk9sf6v2xa7cl3-check-optional-secrets/bin/check-optional-secrets" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

if [ "$ACTION_FAILED" = "true" ]; then
  _log_job "use-runtime-env" event "✗" "Job failed due to action failures"
  exit 1
fi
  
}

job_validate-env() {
      source /nix/store/f26psz5whxf06q1ba3yxvq874lpr2xal-nixactions-local-executor/bin/nixactions-local-executor
setup_local_workspace
  
      setup_local_job "validate-env"
export APP_NAME=nixactions-demo
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export ENVIRONMENT=staging
ACTION_FAILED=false

run_action "validate-env" "require-env" "/nix/store/raaj31x068pmkjxw4w306ccq97q0cwkg-require-env/bin/require-env" 'success()' 'date +%s%N 2>/dev/null || echo "0"'


run_action "validate-env" "show-config" "/nix/store/9gj6h1hx337bqn3pkinwrcciyirq68jj-show-config/bin/show-config" 'success()' 'date +%s%N 2>/dev/null || echo "0"'

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
