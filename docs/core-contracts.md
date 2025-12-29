# Core Contracts

NixActions is built on four core contracts: Step, Executor, Job, and Workflow.

---

## Contract 1: Step = Derivation

**Definition:** A Step is a Nix derivation (bash script + dependencies in /nix/store).

> **Note:** "Step" is the execution primitive. "Action" refers to reusable components from `lib/actions/` or SDK-defined actions.

### Type Signature

```nix
Step :: Derivation {
  type = "derivation";
  outputPath = "/nix/store/xxx-action-name";
  
  # Metadata (via passthru)
  passthru = {
    name     :: String;
    deps     :: [Derivation];
    env      :: AttrSet String;
    workdir  :: Path | Null;
    condition :: Condition | Null;
  };
}
```

### Constructor

```nix
mkStep :: {
  name      :: String,
  bash      :: String,
  deps      :: [Derivation] = [],
  env       :: AttrSet String = {},
  workdir   :: Path | Null = null,
  condition :: Condition | Null = null,
  retry     :: RetryConfig | Null = null,
  timeout   :: Int | Null = null,
} -> Derivation
```

### Key Design Points

- Step is ALWAYS a derivation in `/nix/store`
- User can pass attrset (converted to derivation via `mkStep`)
- User can pass derivation directly (already a step)
- Build-time validation (if step doesn't build -> workflow doesn't build)
- Caching (steps built once, reused across jobs)

### Examples

```nix
# User writes attrset (converted to derivation):
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
  condition = "always()";
}

# With bash condition:
{
  name = "deploy";
  bash = "kubectl apply -f k8s/";
  deps = [ pkgs.kubectl ];
  condition = ''[ "$BRANCH" = "main" ]'';
}

# Compiled to derivation:
# /nix/store/xxx-test
#   bin/
#     test  # Executable script with condition check

# Direct derivation usage:
let
  testStep = pkgs.writeScriptBin "test" ''
    npm test
  '';
in {
  steps = [ testStep ];
}
```

---

## Contract 2: Executor (5-Hook Model)

**Definition:** Abstraction of "where to execute" with workspace-level and job-level lifecycle hooks

### Type Signature

```nix
Executor :: {
  name     :: String,  # Unique identifier (can be customized)
  copyRepo :: Bool,    # Whether to copy repository to job directory (default: true)
  
  # === WORKSPACE LEVEL (for entire workflow) ===
  
  setupWorkspace :: {
    actionDerivations :: [Derivation]  # ALL steps from ALL jobs sharing this executor
  } -> Bash,
  
  cleanupWorkspace :: {
    actionDerivations :: [Derivation]
  } -> Bash,
  
  # === JOB LEVEL (for each job) ===
  
  setupJob :: {
    jobName           :: String,
    actionDerivations :: [Derivation],  # Steps for THIS job only
  } -> Bash,
  
  executeJob :: {
    jobName           :: String,
    actionDerivations :: [Derivation],
    env               :: AttrSet,
  } -> Bash,
  
  cleanupJob :: {
    jobName :: String,
  } -> Bash,
  
  # === ARTIFACTS ===
  
  saveArtifact :: {
    name    :: String,
    path    :: String,
    jobName :: String,
  } -> Bash,
  
  restoreArtifact :: {
    name    :: String,
    path    :: String,  # Target path (relative to job dir)
    jobName :: String,
  } -> Bash,
}
```

### Key Design Points

- **Workspace-level hooks** (`setupWorkspace`, `cleanupWorkspace`)
  - Called **ONCE** per unique executor (by name)
  - Receive **ALL** actionDerivations from **ALL** jobs sharing this executor

- **Job-level hooks** (`setupJob`, `executeJob`, `cleanupJob`)
  - Called **per job**
  - Each job gets isolated resources (directory, container, pod)

- **Executor uniqueness by name**
  - Executors deduplicated by `name` field
  - Custom names allow multiple workspaces with same configuration

### Execution Flow

```bash
main() {
  # 1. Setup workspaces (ONCE per unique executor)
  local.setupWorkspace({ actionDerivations = [all local actions] })
  oci.setupWorkspace({ actionDerivations = [all oci actions] })
  
  # 2. Run jobs
  job_build() {
    oci.setupJob({ jobName = "build", actionDerivations = [...] })
    restore_artifacts
    oci.executeJob({ jobName = "build", actionDerivations, env })
    save_artifacts
    oci.cleanupJob({ jobName = "build" })
  }
}

# Workflow end (via trap)
cleanup_all() {
  oci.cleanupWorkspace({ actionDerivations = [...] })
  local.cleanupWorkspace({ actionDerivations = [...] })
}
```

---

## Contract 3: Job (GitHub Actions Style)

**Definition:** Composition of steps + executor + metadata

### Type Signature

```nix
Job :: {
  # Required
  executor :: Executor,
  steps    :: [Step],
  
  # Dependencies (GitHub Actions style)
  needs :: [String] = [],
  
  # Conditional execution
  condition :: Condition = "success()",
  
  # Error handling
  continueOnError :: Bool = false,
  
  # Environment (runtime values)
  env :: AttrSet String = {},
  envFrom :: [Derivation] = [],  # Environment provider derivations
  
  # Artifacts
  inputs  :: [String | { name :: String, path :: String }] = [],
  outputs :: AttrSet String = {},
  
  # Retry/timeout
  retry   :: RetryConfig | Null = null,
  timeout :: Int | Null = null,
}
```

### Execution Flow

```
0. Setup workflow environment (on HOST)
   - WORKFLOW_ID, NIXACTIONS_ARTIFACTS_DIR
   - Load environment variables (immutable for workflow)

For each job:

1. Setup workspace (lazy init)
   - executor.setupWorkspace (if not already done)

2. Restore artifacts (if inputs specified)
   - executor.restoreArtifact for each input

3. Execute job
   - executor.executeJob { jobName, actionDerivations, env }

4. Save artifacts (if outputs specified)
   - executor.saveArtifact for each output

At workflow end:

5. Cleanup workspace
   - executor.cleanupWorkspace
```

---

## Contract 4: Workflow (GitHub Actions Style)

**Definition:** DAG of jobs with parallel execution

### Type Signature

```nix
WorkflowConfig :: {
  name    :: String,
  jobs    :: AttrSet Job,
  env     :: AttrSet String = {},
  envFrom :: [Derivation] = {},
  retry   :: RetryConfig | Null = null,
  timeout :: Int | Null = null,
}
```

### Constructor

```nix
mkWorkflow :: {
  name :: String,
  jobs :: AttrSet Job,
  env  :: AttrSet String = {},
} -> Derivation  # Bash script with all actions pre-compiled
```

### Compilation Process

```
1. Convert all action attrsets to derivations
   actions = map mkAction job.actions

2. Collect ALL derivations per executor
   executorDerivations = groupBy executor [all actions]

3. Generate setup functions (one per executor)
   setup_executor_local() {
     setupWorkspace { derivations = [...]; }
   }

4. Generate job functions
   job_test() {
     executeJob {
       steps = [ /nix/store/xxx /nix/store/yyy ];
     }
   }

5. Generate main execution (DAG-based)
   Level 0: run jobs in parallel
   Level 1: run jobs in parallel
   ...
```

---

## Supporting Types

### Condition

```nix
Condition :: 
  | "always()"     # Always run
  | "failure()"    # Run if any previous job failed
  | "success()"    # Run if all previous jobs succeeded (default)
  | "cancelled()"  # Run if workflow was cancelled
  | BashScript     # Any bash that returns exit code 0 (run) or 1 (skip)
```

### RetryConfig

```nix
RetryConfig :: {
  max_attempts :: Int = 1,           # Total attempts (1 = no retry)
  backoff      :: "exponential" | "linear" | "constant" = "exponential",
  min_time     :: Int = 1,           # Minimum delay (seconds)
  max_time     :: Int = 60,          # Maximum delay (seconds)
}
```

---

## See Also

- [Actions](./actions.md) - Deep dive into actions
- [Executors](./executors.md) - Executor implementations
- [API Reference](./api-reference.md) - Full API documentation
