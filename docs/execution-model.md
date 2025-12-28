# Execution Model

NixActions uses a level-based parallel execution model, similar to GitHub Actions.

---

## Level-Based Parallel Execution

### Algorithm

```
1. Calculate dependency depth for each job:
   depth(job) = 0 if needs == []
              = 1 + max(depth(dep) for dep in needs) otherwise

2. Group jobs by depth (level):
   level_0 = jobs with depth 0
   level_1 = jobs with depth 1
   ...

3. Setup executors (called ONCE per unique executor):
   for each unique executor:
     setupWorkspace { derivations = [all actions for this executor] }

4. Execute level by level:
   for each level:
     - Start all jobs in level in parallel
     - Wait for all to complete
     - Check conditions (success/failure/always)
     - Proceed to next level

5. Stop on failure:
   - If job fails and continueOnError = false -> stop workflow
   - If job fails and continueOnError = true -> continue
   - Jobs with condition: always() always run
   - Jobs with condition: failure() only run if failures occurred
```

---

## Visual Example

```nix
jobs = {
  lint     = { ... };                           # Level 0
  security = { ... };                           # Level 0
  test     = { needs = ["lint"]; ... };         # Level 1
  build    = { needs = ["lint" "test"]; ... };  # Level 2
  deploy   = { needs = ["build"]; ... };        # Level 3
  notify   = { needs = ["build"]; condition = "always()"; ... };  # Level 3
};
```

```
Level 0:  lint ----+
                   |
          security-+---> (parallel)
                   |
Level 1:  test <---+
             |
Level 2:  build <--+
             |
Level 3:  deploy --+
          notify --+---> (parallel)
```

---

## Execution Timeline

```
Time --->

Level 0:  [lint========]  [security====]
                      |
Level 1:              +---[test============]
                                          |
Level 2:                                  +---[build==========]
                                                              |
Level 3:                                                      +---[deploy====]
                                                              +---[notify====]
```

---

## Job Status Tracking

```nix
# Runtime state
declare -A JOB_STATUS      # "success" | "failure" | "skipped"
FAILED_JOBS=()             # List of failed job names
WORKFLOW_CANCELLED=false   # Set to true on SIGINT/SIGTERM
```

### Status Flow

```
Job Start:
  - Check condition
  - If condition fails -> JOB_STATUS[job]="skipped"
  - Otherwise -> execute

Job End:
  - If exit code 0 -> JOB_STATUS[job]="success"
  - If exit code != 0:
    - If continueOnError -> JOB_STATUS[job]="failure", continue
    - Otherwise -> JOB_STATUS[job]="failure", stop workflow
```

---

## Condition Evaluation

### Built-in Conditions

```bash
check_condition() {
  local condition=$1
  
  case "$condition" in
    always\(\))
      return 0  # Always run
      ;;
    failure\(\))
      if [ ${#FAILED_JOBS[@]} -eq 0 ]; then
        return 1  # No failures, skip
      fi
      ;;
    success\(\))
      if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
        return 1  # Has failures, skip
      fi
      ;;
    cancelled\(\))
      if [ "$WORKFLOW_CANCELLED" = "false" ]; then
        return 1
      fi
      ;;
    *)
      # Bash expression - evaluate
      if eval "$condition"; then
        return 0
      else
        return 1
      fi
      ;;
  esac
}
```

### Example Scenarios

```nix
# Scenario 1: Normal success
jobs = {
  test = { ... };      # Succeeds
  deploy = { 
    needs = ["test"];
    condition = "success()";  # Runs (default)
  };
};

# Scenario 2: Failure handling
jobs = {
  test = { ... };      # Fails
  deploy = { 
    needs = ["test"];
    condition = "success()";  # Skipped
  };
  rollback = {
    needs = ["test"];
    condition = "failure()";  # Runs
  };
  notify = {
    needs = ["test"];
    condition = "always()";   # Runs
  };
};

# Scenario 3: Branch condition
jobs = {
  test = { ... };
  deploy = {
    needs = ["test"];
    condition = ''[ "$BRANCH" = "main" ]'';  # Only on main
  };
};
```

---

## Generated Code Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# === WORKFLOW SETUP ===
WORKFLOW_ID="workflow-$(date +%s)-$$"
NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export WORKFLOW_ID NIXACTIONS_ARTIFACTS_DIR

# === STATUS TRACKING ===
declare -A JOB_STATUS
FAILED_JOBS=()

# === EXECUTOR SETUP (one per unique executor) ===
EXECUTOR_local_INITIALIZED=false
setup_executor_local() {
  if [ "$EXECUTOR_local_INITIALIZED" = "false" ]; then
    # setupWorkspace code
    EXECUTOR_local_INITIALIZED=true
  fi
}

# === JOB FUNCTIONS ===
job_lint() {
  setup_executor_local
  # setupJob, executeJob, cleanupJob
}

job_test() {
  setup_executor_local
  # setupJob, executeJob, cleanupJob
}

# === MAIN EXECUTION ===
main() {
  # Level 0: parallel
  job_lint &
  PID_lint=$!
  
  job_security &
  PID_security=$!
  
  wait $PID_lint || FAILED_JOBS+=("lint")
  wait $PID_security || true  # continueOnError
  
  # Level 1: depends on level 0
  if check_condition "success()"; then
    job_test
  fi
  
  # ...
}

# === CLEANUP ===
cleanup() {
  # cleanupWorkspace for all executors
}
trap cleanup EXIT

main "$@"
```

---

## Parallel Execution Details

### Background Jobs

```bash
# Start jobs in parallel using background processes
job_lint &
PID_lint=$!

job_security &
PID_security=$!

# Wait for all and collect exit codes
wait $PID_lint
STATUS_lint=$?

wait $PID_security
STATUS_security=$?
```

### Process Management

- Each job runs in a subshell
- Parent process waits for all jobs in level
- Exit codes captured for condition evaluation
- Cleanup happens via `trap EXIT`

---

## Error Handling

### Default Behavior

```nix
# Job fails -> workflow stops
jobs = {
  test = { ... };   # Fails
  build = { needs = ["test"]; ... };  # Never runs
};
```

### Continue on Error

```nix
# Job fails -> workflow continues
jobs = {
  security = {
    continueOnError = true;
    ...
  };  # Fails but workflow continues
  build = { ... };  # Still runs
};
```

### Always Run

```nix
# Job runs regardless of previous failures
jobs = {
  test = { ... };   # Fails
  cleanup = {
    needs = ["test"];
    condition = "always()";
    ...
  };  # Still runs
};
```

---

## See Also

- [Conditions](./conditions.md) - Detailed condition system
- [Core Contracts](./core-contracts.md) - Job and Workflow contracts
- [Architecture](./architecture.md) - System overview
