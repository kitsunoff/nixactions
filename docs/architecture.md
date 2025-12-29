# Architecture

## Layered Design

```
+------------------------------------------+
| Level 5: User Abstractions               |
|   Custom helpers, presets, wrappers      |
+------------------------------------------+
                   |
+------------------------------------------+
| Level 4: Workflow (DAG of jobs)          |
|   mkWorkflow { name, jobs }              |
|   Parallel execution by default          |
+------------------------------------------+
                   |
+------------------------------------------+
| Level 3: Job (actions + executor)        |
|   { executor, actions, needs }           |
+------------------------------------------+
                   |
+------------------------------------------+
| Level 2: Executor (where to execute)     |
|   mkExecutor { setupWorkspace }          |
|   Receives derivations for provision     |
+------------------------------------------+
                   |
+------------------------------------------+
| Level 1: Action = DERIVATION             |
|   mkAction { bash, deps } -> /nix/store  |
|   Compiled at build-time                 |
+------------------------------------------+
                   |
+------------------------------------------+
| Level 0: Nix Store (/nix/store)          |
|   All actions are derivations            |
+------------------------------------------+
```

---

## Compilation Flow

```
Nix Evaluation                 Build                    Runtime
==============                 =====                    =======

flake.nix                      
    |                          
    v                          
nixactions.mkWorkflow            
    |                          
    +-- jobs.test              
    |      |                   
    |      +-- actions         
    |           |              
    |           v              
    |      mkAction            nix build
    |           |              =========
    |           +------------> /nix/store/xxx-test
    |                               |
    +-- jobs.build                  |
           |                        |
           +-- actions              |
                |                   |
                v                   |
           mkAction                 |
                |                   |
                +----------------> /nix/store/yyy-build
                                        |
                                        v
                               /nix/store/zzz-ci-workflow
                                        |
                                        v
                                   nix run .#ci
                                   ============
                                   
                                   -> Setup workspace
                                   -> Execute job_test
                                   ->   /nix/store/xxx-test
                                   -> Execute job_build
                                   ->   /nix/store/yyy-build
                                   -> Cleanup
```

---

## Component Overview

### mkWorkflow

Compiles a workflow configuration into an executable bash script.

**Input:**
```nix
{
  name = "ci";
  jobs = { ... };
  env = { ... };
}
```

**Output:**
- Derivation containing bash script
- All action derivations as dependencies
- DAG-based execution order

### mkExecutor

Defines where and how jobs execute.

**5-Hook Model:**
1. `setupWorkspace` - Called once per unique executor
2. `cleanupWorkspace` - Called at workflow end
3. `setupJob` - Called before each job
4. `executeJob` - Runs action derivations
5. `cleanupJob` - Called after each job

### mkAction

Converts action configuration to a derivation.

**Input:**
```nix
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
}
```

**Output:**
```
/nix/store/xxx-test/
  bin/
    test  # Executable script
```

---

## Directory Structure

```
nixactions/
+-- flake.nix                 # Entry point
+-- lib/
|   +-- default.nix           # API exports
|   +-- mk-workflow.nix       # Workflow compiler
|   +-- mk-executor.nix       # Executor contract
|   +-- mk-matrix-jobs.nix    # Matrix generation
|   +-- retry.nix             # Retry logic
|   +-- timeout.nix           # Timeout handling
|   +-- logging.nix           # Structured logging
|   +-- runtime-helpers.nix   # Runtime bash functions
|   +-- make-configurable.nix # Configuration helper
|   +-- executors/
|   |   +-- default.nix
|   |   +-- local.nix         # Local executor
|   |   +-- local-helpers.nix
|   |   +-- oci.nix           # OCI/Docker executor
|   |   +-- action-runner.nix # Action execution engine
|   +-- actions/
|   |   +-- default.nix
|   |   +-- checkout.nix
|   |   +-- nix-shell.nix
|   |   +-- npm.nix
|   |   +-- setup.nix
|   +-- env-providers/
|   |   +-- default.nix
|   |   +-- file.nix
|   |   +-- sops.nix
|   |   +-- static.nix
|   |   +-- required.nix
|   +-- jobs/
|       +-- default.nix
|       +-- buildah-build-push.nix
+-- examples/
|   +-- 01-basic/
|   +-- 02-features/
|   +-- 03-real-world/
+-- docs/
+-- scripts/
```

---

## Runtime Structure

```
/tmp/nixactions/$WORKFLOW_ID/
+-- $EXECUTOR_NAME/
|   +-- jobs/
|       +-- job1/             # Job directory
|       |   +-- (repo copy)
|       |   +-- $JOB_ENV      # Job environment file
|       +-- job2/
|       +-- ...

$HOME/.cache/nixactions/$WORKFLOW_ID/
+-- artifacts/
    +-- artifact1/
    +-- artifact2/
```

---

## Data Flow

### Environment Variables

```
Workflow start:
  1. CLI env (highest priority)
  2. CLI --env-file
  3. Workflow envFrom providers
  4. Workflow env
  
For each job:
  5. Job envFrom providers
  6. Job env
  
For each action:
  7. Action env (lowest priority)
```

### Artifacts

```
Job A (producer):
  1. Execute actions
  2. saveArtifact() -> $NIXACTIONS_ARTIFACTS_DIR/name/

Job B (consumer):
  1. restoreArtifact() <- $NIXACTIONS_ARTIFACTS_DIR/name/
  2. Execute actions
```

---

## Executor Lifecycle

```
Workflow Start
==============
for each unique executor (by name):
  setupWorkspace({ actionDerivations = ALL actions using this executor })

Job Execution
=============
for each job:
  setupJob({ jobName, actionDerivations })
  restoreArtifacts()
  executeJob({ jobName, actionDerivations, env })
  saveArtifacts()
  cleanupJob({ jobName })

Workflow End (trap EXIT)
========================
for each unique executor:
  cleanupWorkspace({ actionDerivations })
```

---

## See Also

- [Core Contracts](./core-contracts.md) - Detailed type signatures
- [Executors](./executors.md) - Executor implementations
- [Execution Model](./execution-model.md) - DAG-based scheduling
