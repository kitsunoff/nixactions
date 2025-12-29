# Conditions System

Conditions control when jobs and actions run.

---

## Overview

**Two types of conditions:**

1. **Built-in workflow-aware**: `always()`, `failure()`, `success()`, `cancelled()`
   - Track workflow state (job failures, cancellation)
   - Work at both job and action level
    
2. **Bash scripts**: Any bash that returns exit code 0 (run) or 1 (skip)
   - Full bash power: `test`, `[`, file checks, git, grep, env vars
   - Examples: `[ "$BRANCH" = "main" ]`, `test -f .env`, `git diff --quiet`

---

## Condition Types

```nix
Condition :: 
  | "always()"     # Always run
  | "failure()"    # Run if any previous job failed
  | "success()"    # Run if all previous jobs succeeded (default)
  | "cancelled()"  # Run if workflow was cancelled
  | BashScript     # Any bash returning exit code 0 (run) or 1 (skip)
```

---

## Built-in Conditions

### success() (Default)

Run only if all dependencies succeeded.

```nix
jobs = {
  test = { ... };
  
  deploy = {
    needs = ["test"];
    condition = "success()";  # Default, can be omitted
    ...
  };
};
```

### failure()

Run only if any dependency failed.

```nix
jobs = {
  test = { ... };
  
  rollback = {
    needs = ["test"];
    condition = "failure()";
    steps = [{
      bash = "kubectl rollout undo deployment/app";
    }];
  };
};
```

### always()

Always run, regardless of previous job status.

```nix
jobs = {
  test = { ... };
  
  notify = {
    needs = ["test"];
    condition = "always()";
    steps = [{
      bash = ''
        curl -X POST $WEBHOOK \
          -d '{"status": "completed"}'
      '';
    }];
  };
  
  cleanup = {
    needs = ["test"];
    condition = "always()";
    steps = [{
      bash = "rm -rf /tmp/test-data";
    }];
  };
};
```

### cancelled()

Run only if workflow was cancelled (SIGINT/SIGTERM).

```nix
jobs = {
  long-task = { ... };
  
  handle-cancel = {
    needs = ["long-task"];
    condition = "cancelled()";
    steps = [{
      bash = "echo 'Workflow was cancelled'";
    }];
  };
};
```

---

## Bash Conditions

Any bash script that returns exit code 0 (run) or 1 (skip).

### Environment Variable Checks

```nix
# Branch check
{
  condition = ''[ "$BRANCH" = "main" ]'';
}

# Environment check
{
  condition = ''[ "$ENVIRONMENT" = "production" ]'';
}

# Variable exists
{
  condition = ''test -n "$DEPLOY_KEY"'';
}

# Multiple conditions
{
  condition = ''[ "$CI" = "true" ] && test -n "$API_KEY"'';
}
```

### File/Directory Checks

```nix
# File exists
{
  condition = ''[ -f .env ]'';
}

# Directory exists
{
  condition = ''[ -d dist/ ]'';
}

# File contains pattern
{
  condition = ''grep -q "version.*2.0" package.json'';
}
```

### Git Conditions

```nix
# No changes since last commit
{
  condition = ''git diff --quiet HEAD~1'';
}

# Changes in specific directory
{
  condition = ''! git diff --quiet main..HEAD -- src/'';
}

# Current branch check
{
  condition = ''[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]'';
}
```

### Command Success

```nix
# Run if check passes
{
  condition = ''npm run check'';
}

# Run if tests pass
{
  condition = ''npm test --dry-run'';
}
```

---

## Job-Level Conditions

```nix
jobs = {
  test = {
    executor = nixactions.executors.local;
    steps = [...];
  };
  
  # Only on success (default)
  deploy = {
    needs = ["test"];
    condition = "success()";
    ...
  };
  
  # Only on failure
  cleanup-on-failure = {
    needs = ["test"];
    condition = "failure()";
    steps = [{
      bash = "rm -rf /tmp/test-data";
    }];
  };
  
  # Always run
  notify = {
    needs = ["test"];
    condition = "always()";
    ...
  };
  
  # Branch check
  deploy-production = {
    needs = ["test"];
    condition = ''[ "$BRANCH" = "main" ]'';
    ...
  };
  
  # Multiple conditions
  deploy-staging = {
    needs = ["test"];
    condition = ''[ "$BRANCH" = "develop" ] && test -n "$STAGING_KEY"'';
    ...
  };
  
  # File-based condition
  publish-npm = {
    needs = ["build"];
    condition = ''grep -q "\"private\": false" package.json'';
    ...
  };
  
  # Git-based condition
  deploy-frontend = {
    needs = ["test"];
    condition = ''! git diff --quiet main..HEAD -- frontend/'';
    ...
  };
};
```

---

## Action-Level Conditions

GitHub Actions supports `if` on steps - NixActions supports `condition` on actions:

```nix
{
  steps = [
    {
      name = "test";
      bash = "npm test";
    }
    
    # Bash condition
    {
      name = "deploy";
      condition = ''[ "$BRANCH" = "main" ]'';
      bash = "deploy.sh";
    }
    
    # Built-in condition
    {
      name = "notify-slack";
      condition = "always()";
      bash = ''
        curl -X POST $SLACK_WEBHOOK \
          -d '{"text": "Tests completed"}'
      '';
    }
    
    # File existence check
    {
      name = "upload-coverage";
      condition = ''[ -f coverage/lcov.info ]'';
      bash = "codecov upload coverage/lcov.info";
    }
    
    # Environment check
    {
      name = "deploy-production";
      condition = ''test -n "$PROD_TOKEN" && [ "$ENVIRONMENT" = "prod" ]'';
      bash = "deploy.sh production";
    }
    
    # Git diff check
    {
      name = "build-docker";
      condition = ''! git diff --quiet HEAD~1 -- Dockerfile'';
      bash = "docker build -t myapp .";
    }
  ];
}
```

### Compiled Action

```bash
# /nix/store/xxx-deploy/bin/deploy
#!/usr/bin/env bash
set -euo pipefail

# Check condition
if ! ( [ "$BRANCH" = "main" ] ); then
  echo "Skipping: deploy (condition not met)"
  exit 0
fi

# Execute
deploy.sh
```

---

## Condition Evaluation

### Job-Level

```bash
# Generated workflow tracks status
declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false

check_condition() {
  local condition=$1
  
  case "$condition" in
    always\(\))
      return 0
      ;;
    failure\(\))
      [ ${#FAILED_JOBS[@]} -gt 0 ]
      ;;
    success\(\))
      [ ${#FAILED_JOBS[@]} -eq 0 ]
      ;;
    cancelled\(\))
      [ "$WORKFLOW_CANCELLED" = "true" ]
      ;;
    *)
      eval "$condition"
      ;;
  esac
}

# Usage
if check_condition "${job_condition}"; then
  job_test
else
  echo "Skipping job_test (condition not met)"
fi
```

### Action-Level

```bash
# Embedded in action derivation
# /nix/store/xxx-deploy/bin/deploy
if ! ( ${condition} ); then
  echo "Skipping: deploy"
  exit 0
fi

# Execute action
deploy.sh
```

---

## Examples

### Cleanup on Failure

```nix
jobs = {
  test = {
    executor = nixactions.executors.local;
    steps = [{ bash = "npm test"; }];
  };
  
  cleanup = {
    needs = ["test"];
    condition = "failure()";
    steps = [{
      bash = "rm -rf /tmp/test-data";
    }];
  };
};
```

### Deploy Only on Main

```nix
jobs = {
  build = {
    executor = nixactions.executors.local;
    steps = [{ bash = "npm run build"; }];
  };
  
  deploy = {
    needs = ["build"];
    condition = ''[ "$GITHUB_REF" = "refs/heads/main" ]'';
    steps = [{
      bash = "kubectl apply -f k8s/";
    }];
  };
};
```

### Conditional Actions Within Job

```nix
jobs = {
  ci = {
    executor = nixactions.executors.local;
    steps = [
      # Always runs
      {
        name = "test";
        bash = "npm test";
      }
      
      # Only on main branch
      {
        name = "publish";
        condition = ''[ "$BRANCH" = "main" ]'';
        bash = "npm publish";
      }
      
      # Always runs
      {
        name = "notify";
        condition = "always()";
        bash = "curl -X POST $WEBHOOK";
      }
    ];
  };
};
```

---

## See Also

- [Execution Model](./execution-model.md) - How conditions affect execution
- [Actions](./actions.md) - Action-level conditions
- [API Reference](./api-reference.md) - Full condition API
