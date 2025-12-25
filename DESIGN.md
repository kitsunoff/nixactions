# NixActions Design Document v4.0 - Actions as Derivations

## Executive Summary

**NixActions** - agentless CI/CD platform powered by Nix, following GitHub Actions execution model with build-time action compilation.

**Elevator pitch:** "Ansible for CI/CD with a type-safe DSL and deterministic environments"

**Core concept:** Compile workflows into self-contained executables that run anywhere without agents or central infrastructure. **Actions are Nix derivations**, provisioned at build-time.

**Execution model:** GitHub Actions style - parallel by default, explicit dependencies via `needs`.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Architecture](#architecture)
3. [Core Contracts](#core-contracts)
4. [Execution Model](#execution-model)
5. [Actions as Derivations](#actions-as-derivations)
6. [Conditions System](#conditions-system)
7. [Retry Mechanism](#retry-mechanism)
8. [Secrets Management](#secrets-management)
9. [Artifacts Management](#artifacts-management)
   - [Custom Restore Paths](#custom-restore-paths)
10. [API Reference](#api-reference)
11. [Implementation](#implementation)
12. [User Guide](#user-guide)
13. [Comparison](#comparison)
14. [Roadmap](#roadmap)

---

## Philosophy

### Core Principles

1. **Local-first**: CI should work locally first, remote is optional
2. **Agentless**: No persistent agents, no polling, no registration
3. **Deterministic**: Nix guarantees reproducibility
4. **Composable**: Everything is a function, everything composes
5. **Simple**: Minimal abstractions, maximum power
6. **Parallel**: Jobs without dependencies run in parallel (like GitHub Actions)
7. **Build-time compilation**: Actions are derivations, provisioned once

### Design Philosophy

```
GitHub Actions execution model:
  ✅ Parallel by default
  ✅ Explicit dependencies (needs)
  ✅ Conditional execution (condition)
  ✅ DAG-based ordering

+ Nix reproducibility:
  ✅ Deterministic builds
  ✅ Self-contained
  ✅ Type-safe
  ✅ Actions = Derivations

+ Agentless:
  ✅ No infrastructure
  ✅ Run anywhere
  ✅ SSH/containers/local

= NixActions
```

---

## Architecture

### Layered Design

```
┌─────────────────────────────────────────┐
│ Level 5: User Abstractions              │
│  └─ Custom helpers, presets, wrappers   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 4: Workflow (DAG of jobs)         │
│  └─ mkWorkflow { name, jobs }           │
│     Parallel execution by default       │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 3: Job (actions + executor)       │
│  └─ { executor, actions, needs }        │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 2: Executor (где выполнить)       │
│  └─ mkExecutor { setupWorkspace }       │
│     Receives derivations for provision  │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 1: Action = DERIVATION            │
│  └─ mkAction { bash, deps } → /nix/store│
│     Compiled at build-time              │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 0: Nix Store (/nix/store)         │
│  └─ All actions are derivations         │
└─────────────────────────────────────────┘
```

---

## Core Contracts

### Contract 1: Action = Derivation

**Definition:** Action is a Nix derivation (bash script + dependencies in /nix/store)

**Type Signature:**
```nix
Action :: Derivation {
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

**Constructor:**
```nix
mkAction :: {
  name      :: String,
  bash      :: String,
  deps      :: [Derivation] = [],
  env       :: AttrSet String = {},
  workdir   :: Path | Null = null,
  condition :: Condition | Null = null,
} -> Derivation
```

**Key design:**
- ✅ Action is ALWAYS a derivation in `/nix/store`
- ✅ User can pass attrset (converted to derivation via `mkAction`)
- ✅ User can pass derivation directly (already an action)
- ✅ Build-time validation (if action doesn't build → workflow doesn't build)
- ✅ Caching (actions built once, reused across jobs)

**Examples:**

```nix
# User writes attrset (converted to derivation):
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
  condition = "always()";  # Built-in condition
}

# With bash condition:
{
  name = "deploy";
  bash = "kubectl apply -f k8s/";
  deps = [ pkgs.kubectl ];
  condition = ''[ "$BRANCH" = "main" ]'';  # Bash script condition
}

# Compiled to derivation:
/nix/store/xxx-test
  └── bin/
      └── test  # Executable script with condition check

# Direct derivation usage:
let
  testAction = pkgs.writeScriptBin "test" ''
    npm test
  '';
in {
  actions = [ testAction ];
}
```

---

### Contract 2: Executor

**Definition:** Abstraction of "where to execute" + build-time provisioning

**Type Signature:**
```nix
Executor :: {
  name :: String,
  
  # Setup workspace for job (called in each job function)
  # Receives action derivations for this job
  # Initializes execution environment with lazy init (creates once, reuses)
  # Use for: creating containers, VMs, copying derivations, etc.
  # Expects: $WORKFLOW_ID to be set
  # Pattern: Check if already initialized, create if not
  #   if [ -z "${EXECUTOR_STATE_VAR:-}" ]; then
  #     # Create container/VM/connection
  #     # Optionally provision actionDerivations
  #     export EXECUTOR_STATE_VAR=...
  #   fi
  setupWorkspace :: {
    actionDerivations :: [Derivation]  # Actions for this job
  } -> Bash,
  
  # Cleanup workspace (called at workflow end)
  cleanupWorkspace :: Bash,
  
  # Execute job in isolated directory
  # Executor receives action derivations and composes them for execution
  # Expects: $WORKFLOW_ID to be set
  executeJob :: {
    jobName           :: String,
    actionDerivations :: [Derivation],  # Actions to execute
    env               :: AttrSet,        # Job-level environment
  } -> Bash,
  
  # Save artifact from job directory to HOST artifacts storage
  # Called AFTER executeJob completes (executed on HOST)
  # Expects: $NIXACTIONS_ARTIFACTS_DIR (exists ONLY on HOST)
  # Implementation: Transfer files from execution environment to host
  #   - local: cp from job dir to $NIXACTIONS_ARTIFACTS_DIR
  #   - OCI: docker cp from container to $NIXACTIONS_ARTIFACTS_DIR
  #   - SSH: scp from remote to $NIXACTIONS_ARTIFACTS_DIR
  saveArtifact :: {
    name    :: String,  # Artifact name
    path    :: String,  # Relative path in job directory
    jobName :: String,  # Job that created it
  } -> Bash,
  
  # Restore artifact from HOST storage to job directory
  # Called BEFORE executeJob starts (executed on HOST)
  # Expects: $NIXACTIONS_ARTIFACTS_DIR (exists ONLY on HOST)
  # Implementation: Transfer files from host to execution environment
  #   - local: cp from $NIXACTIONS_ARTIFACTS_DIR to job dir
  #   - OCI: docker cp from $NIXACTIONS_ARTIFACTS_DIR to container
  #   - SSH: scp from $NIXACTIONS_ARTIFACTS_DIR to remote
  restoreArtifact :: {
    name    :: String,  # Artifact name
    path    :: String,  # Target path (relative to job dir, default ".")
    jobName :: String,  # Job to restore into
  } -> Bash,
}
```

**Key design:**
- ✅ `setupWorkspace` called in each job function with **lazy init pattern**
  - Receives `actionDerivations` for that specific job
  - Creates environment on first call, subsequent calls skip creation
  - Multiple jobs using same executor → environment reused via lazy init
- ✅ `executeJob` receives `actionDerivations` and `env`
  - Composes actions into execution script
  - Sets up job directory and environment
  - Runs actions in execution context (docker exec, local, ssh, etc.)
- ✅ `saveArtifact`/`restoreArtifact` are SEPARATE functions
  - Called outside executeJob on HOST
  - Transfer files between execution environment and `$NIXACTIONS_ARTIFACTS_DIR`

**Responsibilities:**

1. **Workspace Initialization**
   - `setupWorkspace`: Initialize execution environment for job (lazy init)
   - Called in each job function, but creates environment only once
   - Use cases:
     - **Local**: Create /tmp workspace directory
     - **OCI**: Create and start Docker container with /nix/store mount
     - **VM**: Start VM instance
     - **SSH**: Establish SSH connection
   - Uses lazy init pattern: check if initialized, create if not
   - `cleanupWorkspace`: Remove workspace at workflow end

2. **Job Execution**
   - `executeJob`: Compose and execute actions in isolated directory
   - Receives action derivations and job environment
   - Creates job directory: `$WORKSPACE_DIR/jobs/${jobName}`
   - Sets up environment variables
   - Executes each action derivation
   - Executor handles execution context (e.g., `docker exec` for OCI, direct for local)

3. **Artifacts Management** (Local Storage)
   - `saveArtifact`: Save artifact from job directory to **HOST** artifacts storage
   - `restoreArtifact`: Restore artifact from **HOST** storage to job directory
   - Called by workflow orchestrator (NOT inside executeJob)
   - Always executed on HOST machine
   - Uses `$NIXACTIONS_ARTIFACTS_DIR` (exists ONLY on HOST)
   
   **Implementation varies by executor:**
   - **Local**: Direct file copy (workspace is on host)
     - Save: `cp $WORKSPACE_DIR/jobs/$JOB/$PATH $NIXACTIONS_ARTIFACTS_DIR/$NAME/`
     - Restore: `cp $NIXACTIONS_ARTIFACTS_DIR/$NAME/* $WORKSPACE_DIR/jobs/$JOB/`
   
   - **OCI**: Docker cp between container and host
     - Save: `docker cp $CONTAINER:$JOB_DIR/$PATH $NIXACTIONS_ARTIFACTS_DIR/$NAME/`
     - Restore: `docker cp $NIXACTIONS_ARTIFACTS_DIR/$NAME/* $CONTAINER:$JOB_DIR/`
   
   - **SSH** (future): SCP from remote to host artifacts dir
     - Save: `scp $REMOTE:$JOB_DIR/$PATH $NIXACTIONS_ARTIFACTS_DIR/$NAME/`
     - Restore: `scp $NIXACTIONS_ARTIFACTS_DIR/$NAME/* $REMOTE:$JOB_DIR/`

---

### Contract 3: Job (GitHub Actions Style)

**Definition:** Composition of actions + executor + metadata

**Type Signature:**
```nix
Job :: {
  # Required
  executor :: Executor,
  actions  :: [Action],  # Actions (attrsets → derivations)
  
  # Dependencies (GitHub Actions style)
  needs :: [String] = [],
  
  # Conditional execution
  condition :: Condition = "success()",
  
  # Error handling
  continueOnError :: Bool = false,
  
  # Environment
  env :: AttrSet String = {},
  
  # Artifacts
  inputs  :: [String | { name :: String, path :: String }] = [],  # Artifacts to restore (simple or with custom path)
  outputs :: AttrSet String = {},                                   # Artifacts to save
}
```

**Execution flow:**
```
0. Setup workflow environment (on control node/HOST)
   → WORKFLOW_ID="workflow-$(date +%s)-$$"
   → NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
   → mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
   → export WORKFLOW_ID NIXACTIONS_ARTIFACTS_DIR

For each job:

1. Setup workspace (lazy init in job function)
   → executor.setupWorkspace
   → Creates execution environment if not exists (container, VM, etc.)
   → Subsequent calls skip creation (lazy init pattern)

2. Restore artifacts (if inputs specified)
   → for each input: executor.restoreArtifact { name; path; jobName; }
   → Executed on HOST, copies from $NIXACTIONS_ARTIFACTS_DIR to execution env
   → Custom paths allow restoring to subdirectories (e.g., "lib/", "config/")

3. Execute job
   → executor.executeJob { jobName; actionDerivations; env; }
   → Composes and executes all actions in job directory

4. Save artifacts (if outputs specified)
   → for each output: executor.saveArtifact { name; path; jobName; }
   → Executed on HOST, copies from execution env to $NIXACTIONS_ARTIFACTS_DIR

At workflow end:

5. Cleanup workspace
   → executor.cleanupWorkspace
   → Removes containers, VMs, temp directories, etc.
```

**Key points:**
- `$NIXACTIONS_ARTIFACTS_DIR` exists ONLY on HOST (control node)
- Artifacts are saved/restored OUTSIDE of executeJob (executed on HOST)
- `saveArtifact`/`restoreArtifact` transfer files between execution env and HOST
- executeJob receives a PRE-COMPOSED script (not individual actions)
- Cleanup happens once at workflow end (not after each job)

---

### Contract 4: Workflow (GitHub Actions Style)

**Definition:** DAG of jobs with parallel execution

**Type Signature:**
```nix
WorkflowConfig :: {
  name :: String,
  jobs :: AttrSet Job,
  env  :: AttrSet String = {},
}
```

**Constructor:**
```nix
mkWorkflow :: {
  name :: String,
  jobs :: AttrSet Job,
  env  :: AttrSet String = {},
} -> Derivation  # Bash script with all actions pre-compiled
```

**Compilation process:**

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
       actions = [ /nix/store/xxx /nix/store/yyy ];
     }
   }

5. Generate main execution (DAG-based)
   Level 0: run jobs in parallel
   Level 1: run jobs in parallel
   ...
```

---

## Execution Model

### Level-Based Parallel Execution

**Algorithm:**

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
     - Check conditions (condition: success/failure/always)
     - Proceed to next level

5. Stop on failure:
   - If job fails and continueOnError = false → stop workflow
   - If job fails and continueOnError = true → continue
   - Jobs with condition: always() always run
   - Jobs with condition: failure() only run if failures occurred
```

---

## Actions as Derivations

### Why Actions = Derivations?

**Problem with v3.0 (string concatenation):**
```nix
# Old approach:
actionsScript = concatMapStrings (action: action.bash) job.actions;

# ❌ No build-time validation
# ❌ No caching
# ❌ Runtime string manipulation
# ❌ Executor can't provision dependencies
```

**Solution: Actions as Derivations**
```nix
# New approach:
actionDerivations = map mkAction job.actions;
# → [ /nix/store/xxx-action1 /nix/store/yyy-action2 ]

# ✅ Build-time validation
# ✅ Caching (Nix store)
# ✅ Build-time compilation
# ✅ Executor provisions once
```

---

### mkAction Implementation

```nix
# lib/mk-action.nix
{ pkgs, lib }:

{ name
, bash
, deps ? []
, env ? {}
, workdir ? null
, condition ? null
}:

pkgs.writeScriptBin name ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail
  
  # Step-level condition
  ${lib.optionalString (condition != null) ''
    if ! ( ${conditionToBash condition} ); then
      echo "⊘ Skipping: ${name} (condition not met)"
      exit 0
    fi
  ''}
  
  # Working directory
  ${lib.optionalString (workdir != null) "cd ${workdir}"}
  
  # Environment variables
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: 
      "export ${k}=${lib.escapeShellArg (toString v)}"
    ) env
  )}
  
  # Dependencies in PATH
  export PATH=${lib.makeBinPath deps}:$PATH
  
  # Execute action
  ${bash}
'' // {
  # Metadata for introspection
  passthru = {
    inherit name deps env workdir condition;
  };
}
```

---

### Build-time Provisioning

**Workflow compilation:**

```nix
# 1. Convert actions to derivations
jobs.test.actionDerivations = [
  /nix/store/aaa-checkout
  /nix/store/bbb-test
  /nix/store/ccc-upload
]

# 2. Generate job function
job_test() {
  # Setup workspace (lazy init)
  setupWorkspace
  
  # Execute job
  executeJob {
    jobName = "test";
    actionDerivations = [
      /nix/store/aaa-checkout
      /nix/store/bbb-test
      /nix/store/ccc-upload
    ];
    env = { CI = "true"; };
  }
}

job_deploy() {
  # Setup workspace (reuses same container/env)
  setupWorkspace
  
  # Execute job
  executeJob {
    jobName = "deploy";
    actionDerivations = [
      /nix/store/ddd-deploy
    ];
    env = { CI = "true"; };
  }
}
```

**Generated bash:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Setup workflow
WORKFLOW_ID="workflow-$(date +%s)-$$"
NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export WORKFLOW_ID NIXACTIONS_ARTIFACTS_DIR

# Job functions
job_test() {
  # Setup workspace (lazy init - creates container if not exists)
  # Receives actionDerivations for this job
  if [ -z "${CONTAINER_ID_OCI_NODE_20:-}" ]; then
    echo "→ Creating OCI container from image: node:20"
    
    CONTAINER_ID_OCI_NODE_20=$(docker create -v /nix/store:/nix/store:ro node:20 sleep infinity)
    docker start "$CONTAINER_ID_OCI_NODE_20"
    export CONTAINER_ID_OCI_NODE_20
    
    docker exec "$CONTAINER_ID_OCI_NODE_20" mkdir -p /workspace
    
    echo "→ OCI workspace: container $CONTAINER_ID_OCI_NODE_20:/workspace"
    # actionDerivations: /nix/store/aaa-checkout /nix/store/bbb-test /nix/store/ccc-upload
    # Available via /nix/store mount (no need to copy)
  fi
  
  # Execute job
  docker exec -e CI "$CONTAINER_ID_OCI_NODE_20" bash -c '
    set -euo pipefail
    
    JOB_DIR="/workspace/jobs/test"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    echo "╔════════════════════════════════════════╗"
    echo "║ JOB: test"
    echo "║ EXECUTOR: oci-node:20"
    echo "║ WORKDIR: $JOB_DIR"
    echo "╚════════════════════════════════════════╝"
    
    # Set job-level environment
    export CI="true"
    
    # Execute action derivations (available in /nix/store)
    echo "→ checkout"
    /nix/store/aaa-checkout/bin/checkout
    
    echo "→ test"
    /nix/store/bbb-test/bin/test
    
    echo "→ upload"
    /nix/store/ccc-upload/bin/upload
  '
}

job_deploy() {
  # Setup workspace (reuses same container - already initialized)
  # Receives actionDerivations for this job
  if [ -z "${CONTAINER_ID_OCI_NODE_20:-}" ]; then
    echo "→ Creating OCI container from image: node:20"
    
    CONTAINER_ID_OCI_NODE_20=$(docker create -v /nix/store:/nix/store:ro node:20 sleep infinity)
    docker start "$CONTAINER_ID_OCI_NODE_20"
    export CONTAINER_ID_OCI_NODE_20
    
    docker exec "$CONTAINER_ID_OCI_NODE_20" mkdir -p /workspace
    
    echo "→ OCI workspace: container $CONTAINER_ID_OCI_NODE_20:/workspace"
    # actionDerivations: /nix/store/ddd-deploy
    # Available via /nix/store mount
  fi
  
  # Execute job
  docker exec -e CI "$CONTAINER_ID_OCI_NODE_20" bash -c '
    set -euo pipefail
    
    JOB_DIR="/workspace/jobs/deploy"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    echo "╔════════════════════════════════════════╗"
    echo "║ JOB: deploy"
    echo "║ EXECUTOR: oci-node:20"
    echo "║ WORKDIR: $JOB_DIR"
    echo "╚════════════════════════════════════════╝"
    
    # Set job-level environment
    export CI="true"
    
    # Execute action derivations
    echo "→ deploy"
    /nix/store/ddd-deploy/bin/deploy
  '
}

# Main
job_test    # Creates container on first call
job_deploy  # Reuses same container (lazy init skips creation)

# Cleanup
if [ -n "${CONTAINER_ID_OCI_NODE_20:-}" ]; then
  docker stop "$CONTAINER_ID_OCI_NODE_20"
  docker rm "$CONTAINER_ID_OCI_NODE_20"
fi
```

---

### Benefits

1. **Build-time validation**
   ```bash
   $ nix build .#ci
   error: builder for '/nix/store/xxx-test.drv' failed
   # Action fails → workflow fails at build time
   ```

2. **Caching**
   ```bash
   # Action unchanged → reused from cache
   $ nix build .#ci
   # /nix/store/xxx-test already exists, skipping
   ```

3. **Provision once, use many times**
   ```bash
   # Old: provision on every job
   job_test1() { provision nodejs; npm test; }
   job_test2() { provision nodejs; npm test; }
   
   # New: provision once in setupWorkspace
   setup_executor() { 
     setupWorkspace { 
       actionDerivations = [ /nix/store/xxx-test /nix/store/yyy-lint ]; 
     }
     # Build image, start container, copy to remote, etc.
   }
   job_test1() { 
     executeJob { 
       actionDerivations = [ /nix/store/xxx-test ]; 
       env = { CI = "true"; };
     } 
   }
   job_test2() { 
     executeJob { 
       actionDerivations = [ /nix/store/xxx-test ]; 
       env = { CI = "true"; };
     } 
   }
   ```

4. **Composability**
   ```nix
   let
     commonTest = mkAction {
       name = "test";
       bash = "npm test";
       deps = [ pkgs.nodejs ];
     };
   in {
     jobs = {
       test-node-18.actions = [ commonTest ];
       test-node-20.actions = [ commonTest ];
       # Same derivation, reused!
     };
   }
   ```

---

## Conditions System

### Philosophy

**Conditions control when jobs and actions run.**

**Two types of conditions:**
1. **Built-in workflow-aware**: `always()`, `failure()`, `success()`, `cancelled()`
   - Track workflow state (job failures, cancellation)
   - Work at both job and action level
   
2. **Bash scripts**: Any bash that returns exit code 0 (run) or 1 (skip)
   - Full bash power: `test`, `[`, file checks, git, grep, env vars
   - Examples: `[ "$BRANCH" = "main" ]`, `test -f .env`, `git diff --quiet`

**v3.0 used `if`, but it's inconsistent:**
- GitHub Actions: `if: success()` and `if: ${{ github.ref == 'refs/heads/main' }}`
- Mixed semantics (function call vs expression)

**v4.0 uses `condition` with unified semantics:**
- ✅ Consistent API: `condition` for both jobs and actions
- ✅ Built-in conditions: `always()`, `failure()`, `success()`, `cancelled()`
- ✅ **Bash scripts**: any bash expression that returns exit code 0 (run) or 1 (skip)
- ✅ Full bash power: use `test`, `[`, file checks, git commands, env vars, etc.

---

### Condition Types

```nix
Condition :: 
  | "always()"                    # Always run
  | "failure()"                   # Run if any previous job failed
  | "success()"                   # Run if all previous jobs succeeded (default)
  | "cancelled()"                 # Run if workflow was cancelled
  | BashScript                    # Any bash that returns exit code 0 (run) or 1 (skip)
```

**Examples:**

```nix
# ============================================
# Built-in conditions (workflow-aware)
# ============================================

{
  condition = "always()";      # Always run (notifications, cleanup)
}

{
  condition = "failure()";     # Only on failure (cleanup, alerts)
}

{
  condition = "success()";     # Only on success (default, deploy)
}

{
  condition = "cancelled()";   # Only if workflow was cancelled
}

# ============================================
# Bash scripts (exit code 0 = run, 1 = skip)
# ============================================

# Environment variable checks
{
  condition = ''[ "$BRANCH" = "main" ]'';
}

{
  condition = ''[ "$ENVIRONMENT" = "production" ]'';
}

{
  condition = ''test -n "$DEPLOY_KEY"'';
}

# File/directory checks
{
  condition = ''[ -f .env ]'';
}

{
  condition = ''[ -d dist/ ]'';
}

{
  condition = ''test -e package.json'';
}

# Git conditions
{
  condition = ''git diff --quiet HEAD~1'';  # No changes since last commit
}

{
  condition = ''git diff --quiet main..HEAD -- src/'';  # No changes in src/
}

{
  condition = ''[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]'';
}

# Complex conditions (multiple checks)
{
  condition = ''[ "$CI" = "true" ] && [ -f package.json ]'';
}

{
  condition = ''test -n "$API_KEY" && [ "$BRANCH" = "main" ]'';
}

# Command success/failure
{
  condition = ''npm run check'';  # Run if check succeeds
}

{
  condition = ''grep -q "version.*2.0" package.json'';
}
```

---

### Job-level Conditions

```nix
jobs = {
  test = {
    executor = local;
    actions = [...];
  };
  
  # Always run (notifications)
  notify = {
    needs = ["test"];
    condition = "always()";
    actions = [{
      bash = ''
        curl -X POST $WEBHOOK \
          -d '{"status": "done"}'
      '';
    }];
  };
  
  # Only on failure (cleanup)
  cleanup-on-failure = {
    needs = ["test"];
    condition = "failure()";
    actions = [{
      bash = "rm -rf /tmp/test-data";
    }];
  };
  
  # Only on success (deploy)
  deploy = {
    needs = ["test"];
    condition = "success()";  # Default
    actions = [{
      bash = "kubectl apply -f k8s/";
    }];
  };
  
  # Custom bash condition - branch check
  deploy-production = {
    needs = ["test"];
    condition = ''[ "$BRANCH" = "main" ]'';
    actions = [{
      bash = "deploy.sh production";
    }];
  };
  
  # Multiple conditions combined
  deploy-staging = {
    needs = ["test"];
    condition = ''[ "$BRANCH" = "develop" ] && test -n "$STAGING_KEY"'';
    actions = [{
      bash = "deploy.sh staging";
    }];
  };
  
  # File-based condition
  publish-npm = {
    needs = ["build"];
    condition = ''grep -q "\"private\": false" package.json'';
    actions = [{
      bash = "npm publish";
    }];
  };
  
  # Git-based condition - only if changes in specific directory
  deploy-frontend = {
    needs = ["test"];
    condition = ''! git diff --quiet main..HEAD -- frontend/'';
    actions = [{
      bash = "cd frontend && npm run deploy";
    }];
  };
};
```

---

### Step-level Conditions (Actions)

**GitHub Actions supports `if` on steps!**

```yaml
# GitHub Actions
steps:
  - name: Deploy
    if: github.ref == 'refs/heads/main'
    run: deploy.sh
```

**NixActions equivalent:**

```nix
{
  actions = [
    {
      name = "test";
      bash = "npm test";
    }
    
    # Bash condition - branch check
    {
      name = "deploy";
      condition = ''[ "$BRANCH" = "main" ]'';
      bash = "deploy.sh";
    }
    
    # Built-in condition - always run
    {
      name = "notify-slack";
      condition = "always()";  # NOTE: step-level always() checks job status
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
    
    # Environment variable check
    {
      name = "deploy-production";
      condition = ''test -n "$PROD_TOKEN" && [ "$ENVIRONMENT" = "prod" ]'';
      bash = "deploy.sh production";
    }
    
    # Git diff check - only run if files changed
    {
      name = "build-docker";
      condition = ''! git diff --quiet HEAD~1 -- Dockerfile'';
      bash = "docker build -t myapp .";
    }
    
    # Command success - only run if check passes
    {
      name = "publish";
      condition = ''npm run check-version'';
      bash = "npm publish";
    }
  ];
}
```

**Compiled action:**

```bash
# /nix/store/xxx-deploy/bin/deploy
#!/usr/bin/env bash
set -euo pipefail

# Check condition
if ! ( [ "$BRANCH" = "main" ] ); then
  echo "⊘ Skipping: deploy (condition not met)"
  exit 0
fi

# Execute
deploy.sh
```

---

### Condition Evaluation

**Job-level conditions:**

```bash
# Workflow tracks status
declare -A JOB_STATUS
FAILED_JOBS=()
WORKFLOW_CANCELLED=false

# Check condition before running job
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

# Run job with condition
if check_condition "${job_condition}"; then
  job_test
else
  echo "⊘ Skipping job_test (condition not met)"
fi
```

**Step-level conditions:**

```bash
# Embedded in action derivation
# /nix/store/xxx-deploy/bin/deploy
if ! ( ${condition} ); then
  echo "⊘ Skipping: deploy"
  exit 0
fi

# Execute action
deploy.sh
```

---

### Condition Examples

#### Cleanup on failure

```nix
jobs = {
  test = {
    executor = local;
    actions = [{ bash = "npm test"; }];
  };
  
  cleanup = {
    needs = ["test"];
    condition = "failure()";
    actions = [{
      bash = "rm -rf /tmp/test-data";
    }];
  };
};
```

#### Deploy only on main branch

```nix
jobs = {
  build = {
    executor = local;
    actions = [{ bash = "npm run build"; }];
  };
  
  deploy = {
    needs = ["build"];
    condition = ''[ "$GITHUB_REF" = "refs/heads/main" ]'';
    actions = [{
      bash = "kubectl apply -f k8s/";
    }];
  };
};
```

#### Conditional actions within job

```nix
jobs = {
  ci = {
    executor = local;
    actions = [
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
      
      # Always runs (notification)
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

## Retry Mechanism

### Overview

Retry mechanism для автоматического повтора failed jobs и actions.

**Приоритет**: 🔥 Critical (Must-have для production)

**Key features:**
- Three-level configuration hierarchy: workflow → job → action
- Three backoff strategies: exponential (default), linear, constant
- Configurable min_time/max_time delays
- Actions = Derivations (compiled at build-time, retry logic injected at runtime)

---

### Retry Configuration Block

```nix
retry = {
  max_attempts = 3;           # int: Total attempts (1 = no retry, just run once)
  backoff = "exponential";    # "exponential" | "linear" | "constant"
  min_time = 1;               # int: Minimum delay between retries (seconds)
  max_time = 60;              # int: Maximum delay between retries (seconds)
}
```

### Configuration Levels (Priority: action > job > workflow)

```nix
platform.mkWorkflow {
  name = "ci";
  
  # Level 1: Workflow-level retry (applies to ALL jobs)
  retry = {
    max_attempts = 2;
    backoff = "exponential";
    min_time = 1;
    max_time = 30;
  };
  
  jobs = {
    test = {
      # Level 2: Job-level retry (applies to ALL actions in this job)
      # Overrides workflow-level retry
      retry = {
        max_attempts = 3;
        backoff = "linear";
        min_time = 2;
        max_time = 60;
      };
      
      actions = [
        {
          name = "flaky-network-call";
          bash = "npm install";
          
          # Level 3: Action-level retry (highest priority)
          # Overrides job-level retry
          retry = {
            max_attempts = 5;
            backoff = "exponential";
            min_time = 1;
            max_time = 120;
          };
        }
        
        {
          name = "unit-tests";
          bash = "npm test";
          # No action-level retry → inherits from job-level
        }
      ];
    };
    
    deploy = {
      # Disable retry for this job
      retry = null;
      
      actions = [{
        bash = "kubectl apply -f prod/";
        # No retry even if workflow-level retry is set
      }];
    };
  };
}
```

---

### Backoff Strategies

#### 1. Exponential Backoff (Default)

**Formula**: `delay = min(max_time, min_time * 2^(attempt-1))`

**Example** (min_time=1, max_time=60):
```
Attempt 1 → delay 1s   (1 * 2^0 = 1)
Attempt 2 → delay 2s   (1 * 2^1 = 2)
Attempt 3 → delay 4s   (1 * 2^2 = 4)
Attempt 4 → delay 8s   (1 * 2^3 = 8)
Attempt 5 → delay 16s  (1 * 2^4 = 16)
Attempt 6 → delay 32s  (1 * 2^5 = 32)
Attempt 7 → delay 60s  (1 * 2^6 = 64, capped at max_time)
```

**Use Case**: Network calls, API requests (prevents thundering herd)

#### 2. Linear Backoff

**Formula**: `delay = min(max_time, min_time * attempt)`

**Example** (min_time=2, max_time=60):
```
Attempt 1 → delay 2s   (2 * 1 = 2)
Attempt 2 → delay 4s   (2 * 2 = 4)
Attempt 3 → delay 6s   (2 * 3 = 6)
Attempt 4 → delay 8s   (2 * 4 = 8)
Attempt 5 → delay 10s  (2 * 5 = 10)
```

**Use Case**: Predictable retry intervals

#### 3. Constant Backoff

**Formula**: `delay = min_time`

**Example** (min_time=5):
```
Attempt 1 → delay 5s
Attempt 2 → delay 5s
Attempt 3 → delay 5s
Attempt 4 → delay 5s
```

**Use Case**: Simple polling, fixed retry intervals

---

### Implementation Details

#### Merge Strategy

```nix
# Priority: action > job > workflow
finalRetry = actionRetry or jobRetry or workflowRetry or null

# If retry.max_attempts == 1 → no retry (single attempt)
# If retry == null → no retry
```

#### Defaults

```nix
{
  max_attempts = 1;        # No retry by default
  backoff = "exponential"; # Exponential if retry enabled
  min_time = 1;            # 1 second minimum
  max_time = 60;           # 60 seconds maximum
}
```

#### Retry Wrapper Integration

Retry logic is implemented via bash functions injected into the compiled workflow:

```bash
# lib/retry.nix provides bash functions
retry_with_backoff() {
  local max_attempts=$1
  local backoff=$2
  local min_time=$3
  local max_time=$4
  shift 4
  
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      local delay=$(calculate_delay $attempt "$backoff" $min_time $max_time)
      sleep $delay
    fi
    
    attempt=$((attempt + 1))
  done
  
  return 1
}

# lib/executors/action-runner.nix wraps action execution
if [ -n "${retry_max_attempts:-}" ]; then
  retry_with_backoff \
    "$retry_max_attempts" \
    "${retry_backoff:-exponential}" \
    "${retry_min_time:-1}" \
    "${retry_max_time:-60}" \
    ${action}/bin/${action.passthru.name}
else
  ${action}/bin/${action.passthru.name}
fi
```

---

### Structured Logging

#### Retry Events

```bash
# Structured format (default)
[2025-12-24T12:00:00.123Z] [workflow:ci] [job:test] [action:npm-install] [attempt:1/3] Starting
[2025-12-24T12:00:05.456Z] [workflow:ci] [job:test] [action:npm-install] [attempt:1/3] Failed (exit: 1)
[2025-12-24T12:00:05.457Z] [workflow:ci] [job:test] [action:npm-install] [retry] Waiting 1s before attempt 2/3 (backoff: exponential)
[2025-12-24T12:00:06.457Z] [workflow:ci] [job:test] [action:npm-install] [attempt:2/3] Starting
[2025-12-24T12:00:08.789Z] [workflow:ci] [job:test] [action:npm-install] [attempt:2/3] Failed (exit: 1)
[2025-12-24T12:00:08.790Z] [workflow:ci] [job:test] [action:npm-install] [retry] Waiting 2s before attempt 3/3 (backoff: exponential)
[2025-12-24T12:00:10.790Z] [workflow:ci] [job:test] [action:npm-install] [attempt:3/3] Starting
[2025-12-24T12:00:12.123Z] [workflow:ci] [job:test] [action:npm-install] [attempt:3/3] Success (duration: 1.333s, total_attempts: 3)
```

#### JSON Format

```json
{"timestamp":"2025-12-24T12:00:00.123Z","workflow":"ci","job":"test","action":"npm-install","event":"start","attempt":1,"max_attempts":3}
{"timestamp":"2025-12-24T12:00:05.456Z","workflow":"ci","job":"test","action":"npm-install","event":"failed","attempt":1,"exit_code":1}
{"timestamp":"2025-12-24T12:00:05.457Z","workflow":"ci","job":"test","action":"npm-install","event":"retry","next_attempt":2,"delay_seconds":1,"backoff":"exponential"}
{"timestamp":"2025-12-24T12:00:12.123Z","workflow":"ci","job":"test","action":"npm-install","event":"success","attempt":3,"duration_ms":1333,"total_attempts":3}
```

---

### Example Usage

#### Basic Retry

```nix
{
  actions = [{
    name = "flaky-test";
    bash = "npm test";
    retry = {
      max_attempts = 3;
      backoff = "exponential";
      min_time = 1;
      max_time = 60;
    };
  }];
}
```

#### Workflow-wide Retry

```nix
platform.mkWorkflow {
  name = "ci";
  
  retry = {
    max_attempts = 2;
    backoff = "exponential";
    min_time = 1;
    max_time = 30;
  };
  
  jobs = {
    test.actions = [{ bash = "npm test"; }];
    lint.actions = [{ bash = "npm run lint"; }];
    # Both inherit workflow-level retry
  };
}
```

#### Selective Retry

```nix
{
  jobs = {
    test = {
      retry = {
        max_attempts = 3;
        backoff = "exponential";
        min_time = 1;
        max_time = 60;
      };
      
      actions = [
        { bash = "npm install"; }  # Retries enabled
        { bash = "npm test"; }     # Retries enabled
        {
          bash = "npm run deploy";
          retry = null;            # NO retry for deploy
        }
      ];
    };
  };
}
```

---

### Edge Cases

#### 1. max_attempts = 1

```nix
retry = {
  max_attempts = 1;  # Single attempt, no retries
  backoff = "exponential";
  min_time = 1;
  max_time = 60;
}

# Equivalent to: retry = null
```

#### 2. retry = null

```nix
retry = null;  # Explicitly disable retry
```

#### 3. Empty retry block

```nix
retry = {};  # Uses all defaults (max_attempts = 1 → no retry)
```

---

### Testing

Comprehensive test suite available in `examples/02-features/test-retry-comprehensive.nix`:

- Exponential backoff success
- Linear backoff success
- Constant backoff success
- Retry exhausted scenarios
- Max attempts = 1 (no retry)
- Retry = null (disabled)
- Workflow-level inheritance
- Job-level override
- Action-level override
- Timing verification

**Run tests:**
```bash
nix run .#test-retry-comprehensive
```

**Coverage:** 23/23 retry features (100%)

---

## Secrets Management

### Philosophy

**NixActions doesn't manage secrets directly.** Instead, it provides:
1. ✅ Universal access to environment variables
2. ✅ Standard actions for popular secrets managers (SOPS, Vault, 1Password)
3. ✅ Composability - use any secrets tool via bash
4. ✅ Runtime env vars override everything

**Key principle:** Secrets are loaded via actions, not built into Nix derivations.

---

### Environment Variables

All jobs and actions have access to environment variables with clear precedence.

#### Precedence Order (highest to lowest)

```
1. Runtime env:     API_KEY=xxx nix run .#ci
2. Action env:      { env.API_KEY = "..."; bash = "..."; }
3. Job env:         { env = { API_KEY = "..."; }; actions = [...]; }
4. Workflow env:    mkWorkflow { env = { API_KEY = "..."; }; }
5. System env:      $API_KEY from shell
```

---

### Built-in Secrets Actions

All secrets actions are derivations:

```nix
# SOPS action
platform.actions.sopsLoad {
  file = ./secrets.sops.yaml;
}
# → /nix/store/xxx-sops-load/bin/sops-load

# Vault action
platform.actions.vaultLoad {
  path = "secret/data/production";
}
# → /nix/store/yyy-vault-load/bin/vault-load

# Environment validation
platform.actions.requireEnv ["API_KEY" "DB_PASSWORD"]
# → /nix/store/zzz-require-env/bin/require-env
```

#### Example Usage

```nix
jobs = {
  deploy = {
    executor = platform.executors.ssh { host = "prod"; };
    
    actions = [
      # 1. Load secrets (derivation)
      (platform.actions.sopsLoad {
        file = ./secrets/production.sops.yaml;
      })
      
      # 2. Validate secrets (derivation)
      (platform.actions.requireEnv [
        "API_KEY"
        "DB_PASSWORD"
      ])
      
      # 3. Use secrets (derivation)
      (mkAction {
        name = "deploy";
        bash = ''
          kubectl create secret generic app-secrets \
            --from-literal=api-key="$API_KEY" \
            --from-literal=db-password="$DB_PASSWORD"
        '';
      })
    ];
  };
};
```

---

## Artifacts Management

### Philosophy

**Artifacts allow jobs to share files explicitly and safely.**

**Key principles:**
1. ✅ **Explicit transfer** - `inputs`/`outputs` API for reliable file sharing
2. ✅ **HOST-based storage** - `$NIXACTIONS_ARTIFACTS_DIR` exists ONLY on control node (HOST)
3. ✅ **Executor transfers files** - `saveArtifact`/`restoreArtifact` copy between execution env and HOST
4. ✅ **Survives cleanup** - artifacts stored outside workspace
5. ✅ **Custom restore paths** - control where artifacts are restored in job directory
6. ⚠️ **Job isolation by convention** - job directories persist but reading across jobs is UB

---

### Architecture

```
┌─────────────────────────────────────────────────┐
│ CONTROL NODE (HOST)                             │
│                                                 │
│  $NIXACTIONS_ARTIFACTS_DIR/                     │
│  ├── dist/                                      │
│  │   └── dist/bundle.js                        │
│  └── coverage/                                  │
│      └── coverage/report.html                  │
│                                                 │
│  ▲                                    │         │
│  │ saveArtifact (docker cp/scp)      │         │
│  │                                    │         │
│  │              restoreArtifact       ▼         │
│  │              (docker cp/scp)                 │
└──┼────────────────────────────────────┼─────────┘
   │                                    │
   │                                    │
┌──┴────────────────────────────────────┴─────────┐
│ EXECUTION ENVIRONMENT (Container/Remote/Local)  │
│                                                 │
│  /workspace/jobs/build/                         │
│  ├── dist/                  ← Created by job    │
│  │   └── bundle.js                             │
│  └── coverage/              ← Restored input    │
│      └── report.html                           │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

### Declarative API

```nix
jobs = {
  build = {
    executor = platform.executors.oci { image = "node:20"; };
    
    # Declare outputs
    outputs = {
      dist = "dist/";
      myapp = "myapp";
    };
    
    actions = [{
      bash = ''
        npm run build
        # dist/ created in /workspace/jobs/build/
      '';
    }];
    # Artifacts saved to HOST after actions complete!
  };
  
  test = {
    needs = ["build"];
    executor = platform.executors.oci { image = "node:20"; };
    
    # Declare inputs
    inputs = ["dist" "myapp"];
    
    actions = [{
      bash = ''
        # Artifacts restored from HOST before actions run!
        # Files now in /workspace/jobs/test/
        npm test
      '';
    }];
  };
};
```

**Generated code:**

```bash
# Setup artifacts dir on HOST
NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"

job_build() {
  # Execute actions in container
  docker exec $CONTAINER bash -c 'cd /workspace/jobs/build && npm run build'
  
  # Save outputs (executed on HOST)
  # docker cp from container to HOST artifacts dir
  docker cp "$CONTAINER:/workspace/jobs/build/dist" "$NIXACTIONS_ARTIFACTS_DIR/dist/"
  docker cp "$CONTAINER:/workspace/jobs/build/myapp" "$NIXACTIONS_ARTIFACTS_DIR/myapp/"
}

job_test() {
  # Restore inputs (executed on HOST)
  # docker cp from HOST artifacts dir to container
  docker cp "$NIXACTIONS_ARTIFACTS_DIR/dist" "$CONTAINER:/workspace/jobs/test/"
  docker cp "$NIXACTIONS_ARTIFACTS_DIR/myapp" "$CONTAINER:/workspace/jobs/test/"
  
  # Execute actions in container
  docker exec $CONTAINER bash -c 'cd /workspace/jobs/test && npm test'
}
```

---

### Custom Restore Paths

**Status:** ✅ IMPLEMENTED (Dec 25, 2025)

Artifacts can be restored to custom paths within the job directory, enabling better organization for monorepos and complex workflows.

#### API: Hybrid Approach

Support both simple strings (backward compatible) and attribute sets (with custom path):

```nix
inputs = [
  "dist"                              # Simple: restore to $JOB_DIR/
  { name = "libs"; path = "lib/"; }   # Custom: restore to $JOB_DIR/lib/
  { name = "config"; path = "../shared/"; }  # Relative paths allowed
]
```

#### Syntax

**Simple (string):**
```nix
inputs = [ "artifact-name" ]
# Equivalent to:
inputs = [ { name = "artifact-name"; path = "."; } ]
```

**Custom path (attribute set):**
```nix
inputs = [
  {
    name = "artifact-name";  # Required: artifact to restore
    path = "target/dir/";     # Required: where to restore (relative to $JOB_DIR)
  }
]
```

**Path semantics:**
- `.` or `./` - Root of job directory (default)
- `subdir/` - Subdirectory within job directory
- `../other/` - Relative to job directory (can go up)
- `/absolute/` - Absolute path (use with caution!)

#### Use Cases

**1. Multiple build outputs to different locations**
```nix
# Want:
# - frontend dist -> public/
# - backend dist -> server/
# - shared libs -> lib/

inputs = [
  { name = "frontend-dist"; path = "public/"; }
  { name = "backend-dist"; path = "server/"; }
  { name = "shared-libs"; path = "lib/"; }
]
```

**2. Monorepo with multiple services**
```nix
# Want:
# - api build -> services/api/
# - worker build -> services/worker/
# - common -> shared/

inputs = [
  { name = "api-dist"; path = "services/api/dist/"; }
  { name = "worker-dist"; path = "services/worker/dist/"; }
  { name = "common"; path = "shared/"; }
]
```

**3. Legacy systems with specific directory structure**
```nix
# Want:
# - application -> /opt/app/
# - config -> /etc/app/
# - data -> /var/app/

inputs = [
  { name = "app-binary"; path = "/opt/app/"; }
  { name = "app-config"; path = "/etc/app/"; }
  { name = "app-data"; path = "/var/app/"; }
]
```

#### Examples

**Default behavior (unchanged):**
```nix
jobs.deploy = {
  needs = [ "build" ];
  inputs = [ "dist" ];  # Restored to $JOB_DIR/
  actions = [
    (actions.runCommand "ls dist/")  # Works as before
  ];
}
```

**Custom subdirectories:**
```nix
jobs.package = {
  needs = [ "build-frontend" "build-backend" ];
  inputs = [
    { name = "frontend"; path = "public/"; }
    { name = "backend"; path = "server/"; }
  ];
  actions = [
    (actions.runCommand ''
      ls public/    # Frontend files
      ls server/    # Backend files
    '')
  ];
}
```

**Mixed usage:**
```nix
jobs.test = {
  needs = [ "build" "lint" ];
  inputs = [
    "dist"                          # Default: to root
    { name = "lint-results"; path = "reports/"; }  # Custom: to reports/
  ];
  actions = [
    (actions.runCommand ''
      cat dist/package.json
      cat reports/lint.txt
    '')
  ];
}
```

**Monorepo deployment:**
```nix
jobs.deploy-all = {
  needs = [ "build-api" "build-worker" "build-frontend" ];
  inputs = [
    { name = "api-dist"; path = "services/api/"; }
    { name = "worker-dist"; path = "services/worker/"; }
    { name = "frontend-dist"; path = "public/"; }
    { name = "shared-config"; path = "config/"; }
  ];
  actions = [
    (actions.runCommand "deploy-monorepo")
  ];
}
```

#### Implementation

Custom restore paths are implemented in:
- `lib/mk-workflow.nix` - `normalizeInput()` function converts strings to attribute sets
- `lib/executors/local-helpers.nix` - `restore_local_artifact()` accepts `target_path` parameter
- `lib/executors/oci-helpers.nix` - `restore_oci_artifact()` accepts `target_path` parameter
- `lib/executors/local.nix` - `restoreArtifact` function signature updated
- `lib/executors/oci.nix` - `restoreArtifact` function signature updated

**Normalization (mk-workflow.nix):**
```nix
# Convert inputs to normalized form
normalizeInput = input:
  if builtins.isString input
  then { name = input; path = "."; }
  else input;

normalizedInputs = map normalizeInput (job.inputs or []);
```

**Local executor (local-helpers.nix):**
```bash
restore_local_artifact() {
  local name=$1
  local target_path=$2  # NEW: target path
  local job_name=$3
  
  JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
  
  if [ -e "$NIXACTIONS_ARTIFACTS_DIR/$name" ]; then
    # Create target directory
    TARGET="$JOB_DIR/$target_path"
    mkdir -p "$(dirname "$TARGET")"
    
    # Handle different path cases
    if [ "$target_path" = "." ] || [ "$target_path" = "./" ]; then
      # Restore to root
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$JOB_DIR/" 2>/dev/null || true
    else
      # Restore to specific path
      mkdir -p "$TARGET"
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$TARGET/" 2>/dev/null || true
    fi
    
    return 0
  else
    _log_workflow artifact "$name" event "✗" "Artifact not found"
    return 1
  fi
}
```

**OCI executor (oci-helpers.nix):**
```bash
restore_oci_artifact() {
  local name=$1
  local target_path=$2  # NEW
  local job_name=$3
  local container_id=$4
  
  # Docker cp to specific path in container
  if [ "$target_path" = "." ]; then
    docker cp "$NIXACTIONS_ARTIFACTS_DIR/$name"/. "$container_id:$JOB_DIR/"
  else
    docker exec "$container_id" mkdir -p "$JOB_DIR/$target_path"
    docker cp "$NIXACTIONS_ARTIFACTS_DIR/$name"/. "$container_id:$JOB_DIR/$target_path/"
  fi
}
```

#### Backward Compatibility

Existing code continues to work:

```nix
# Old syntax (still works)
inputs = [ "dist" "binary" ]

# Equivalent to:
inputs = [
  { name = "dist"; path = "."; }
  { name = "binary"; path = "."; }
]
```

Users can mix old and new syntax:

```nix
inputs = [
  "dist"                              # Old syntax
  { name = "config"; path = "etc/"; } # New syntax
]
```

#### Testing

Comprehensive test available in `examples/02-features/artifacts.nix`:
- Default restore (backward compatibility)
- Custom restore paths
- Mixed syntax
- Multiple artifacts to different locations

---

## API Reference

### Platform API

```nix
platform :: {
  # Core constructors
  mkAction    :: ActionConfig -> Derivation,
  mkExecutor  :: ExecutorConfig -> Executor,
  mkWorkflow  :: WorkflowConfig -> Derivation,
  
  # Built-in executors
  executors :: {
    local           :: Executor,
    nixos-container :: Executor,
    oci             :: { image :: String } -> Executor,
    ssh             :: { host :: String, user :: String, port :: Int } -> Executor,
    k8s             :: { namespace :: String } -> Executor,
    nomad           :: { datacenter :: String } -> Executor,
  },
  
  # Standard actions (all return Derivation)
  actions :: {
    # Setup
    checkout     :: Derivation,
    setupNode    :: { version :: String } -> Derivation,
    setupPython  :: { version :: String } -> Derivation,
    setupRust    :: Derivation,
    
    # Package management
    nixShell     :: [String] -> Derivation,
    
    # NPM actions
    npmInstall   :: Derivation,
    npmTest      :: Derivation,
    npmBuild     :: Derivation,
    npmLint      :: Derivation,
    
    # Secrets management
    sopsLoad     :: { file :: Path, format :: "yaml" | "json" | "dotenv" } -> Derivation,
    vaultLoad    :: { path :: String, addr :: String, token :: String | Null } -> Derivation,
    opLoad       :: { vault :: String, item :: String } -> Derivation,
    ageDecrypt   :: { file :: Path, identity :: Path } -> Derivation,
    bwLoad       :: { itemId :: String } -> Derivation,
    requireEnv   :: [String] -> Derivation,
  },
}
```

---

### mkAction

```nix
mkAction :: {
  name      :: String,
  bash      :: String,
  deps      :: [Derivation] = [],
  env       :: AttrSet String = {},
  workdir   :: Path | Null = null,
  condition :: Condition | Null = null,
} -> Derivation
```

**Example:**

```nix
let
  testAction = platform.mkAction {
    name = "test";
    bash = "npm test";
    deps = [ pkgs.nodejs ];
    env = {
      NODE_ENV = "test";
      CI = "true";
    };
    condition = "always()";
  };
in {
  actions = [ testAction ];
}
```

---

### mkExecutor

```nix
mkExecutor :: {
  name :: String,
  
  setupWorkspace :: {
    actionDerivations :: [Derivation]  # All actions that will be executed
  } -> Bash,
  
  cleanupWorkspace :: Bash,
  
  executeJob :: {
    jobName           :: String,
    actionDerivations :: [Derivation],
    env               :: AttrSet,
  } -> Bash,
  
  saveArtifact :: {
    name    :: String,
    path    :: String,
    jobName :: String,
  } -> Bash,
  
  restoreArtifact :: {
    name    :: String,
    jobName :: String,
  } -> Bash,
} -> Executor
```

**Example:**

```nix
platform.mkExecutor {
  name = "custom";
  
  setupWorkspace = { actionDerivations }: ''
    # Lazy init - only create if not exists
    if [ -z "''${CUSTOM_EXECUTOR_INITIALIZED:-}" ]; then
      echo "→ Setting up workspace"
      echo "→ Received ${toString (builtins.length actionDerivations)} action derivations"
      
      # Setup environment (build image, start VM, etc.)
      mkdir -p /workspace
      
      # Provision actions (copy to image, VM, remote host, etc.)
      for drv in ${toString actionDerivations}; do
        echo "  - Provisioning: $drv"
        # Example: copy to remote, build into image, etc.
      done
      
      export CUSTOM_EXECUTOR_INITIALIZED=1
    fi
  '';
  
  cleanupWorkspace = ''
    echo "→ Cleaning up workspace"
    rm -rf /workspace
  '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    echo "→ Executing job: ${jobName}"
    
    # Create job directory
    mkdir -p /workspace/jobs/${jobName}
    cd /workspace/jobs/${jobName}
    
    # Set job-level environment
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: 
        "export ${k}=${lib.escapeShellArg (toString v)}"
      ) env
    )}
    
    # Execute action derivations
    ${lib.concatMapStringsSep "\n" (action: ''
      echo "→ ${action.passthru.name or "action"}"
      ${action}/bin/${action.passthru.name or "run"}
    '') actionDerivations}
  '';
  
  saveArtifact = { name, path, jobName }: ''
    # Copy from execution env to $NIXACTIONS_ARTIFACTS_DIR on HOST
    if [ -e "/workspace/jobs/${jobName}/${path}" ]; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      cp -r "/workspace/jobs/${jobName}/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      echo "  ✗ Path not found: ${path}"
      return 1
    fi
  '';
  
  restoreArtifact = { name, jobName }: ''
    # Copy from $NIXACTIONS_ARTIFACTS_DIR on HOST to execution env
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      mkdir -p "/workspace/jobs/${jobName}"
      
      # Copy each file/directory from artifact
      for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
        if [ -e "$item" ]; then
          cp -r "$item" "/workspace/jobs/${jobName}/"
        fi
      done
    else
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
```

---

### mkWorkflow

```nix
mkWorkflow :: {
  name :: String,
  jobs :: AttrSet Job,
  env  :: AttrSet String = {},
} -> Derivation
```

**Example:**

```nix
platform.mkWorkflow {
  name = "ci";
  
  env = {
    CI = "true";
  };
  
  jobs = {
    test = {
      executor = platform.executors.local;
      
      actions = [
        (platform.mkAction {
          name = "test";
          bash = "npm test";
          deps = [ pkgs.nodejs ];
        })
      ];
    };
  };
}
```

---

## Implementation

### Executor: Local

```nix
# lib/executors/local.nix
{ pkgs, lib, mkExecutor }:

mkExecutor {
  name = "local";
  
  # Setup local workspace in /tmp
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: ''
    # Lazy init - only create if not exists
    if [ -z "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      export WORKSPACE_DIR_LOCAL
      echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
    fi
  '';
  
  # Cleanup workspace (respects NIXACTIONS_KEEP_WORKSPACE)
  cleanupWorkspace = ''
    if [ -n "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        echo ""
        echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
        rm -rf "$WORKSPACE_DIR_LOCAL"
      else
        echo ""
        echo "→ Local workspace preserved: $WORKSPACE_DIR_LOCAL"
      fi
    fi
  '';
  
  # Execute job locally in isolated directory
  executeJob = { jobName, actionDerivations, env }: ''
    # Create isolated directory for this job
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    echo "╔════════════════════════════════════════╗"
    echo "║ JOB: ${jobName}"
    echo "║ EXECUTOR: local"
    echo "║ WORKDIR: $JOB_DIR"
    echo "╚════════════════════════════════════════╝"
    
    # Set job-level environment
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: 
        "export ${k}=${lib.escapeShellArg (toString v)}"
      ) env
    )}
    
    # Execute action derivations
    ${lib.concatMapStringsSep "\n\n" (action: ''
      echo "→ ${action.passthru.name or "action"}"
      ${action}/bin/${action.passthru.name or "run"}
    '') actionDerivations}
  '';
  
  # Local executor doesn't need fetch/push - artifacts already on control node
  fetchArtifacts = null;
  pushArtifacts = null;
  
  # Save artifact (executed on HOST after job completes)
  saveArtifact = { name, path, jobName }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    if [ -e "$JOB_DIR/${path}" ]; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Save preserving original path structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      cp -r "$JOB_DIR/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      echo "  ✗ Path not found: ${path}"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  restoreArtifact = { name, path, jobName }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      # Restore to job directory (will be created by executeJob)
      mkdir -p "$JOB_DIR"
      
      # Handle custom restore path
      if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
        cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}"/* "$JOB_DIR/" 2>/dev/null || true
      else
        mkdir -p "$JOB_DIR/${path}"
        cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}"/* "$JOB_DIR/${path}/" 2>/dev/null || true
      fi
    else
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
```

---

### Executor: OCI

```nix
# lib/executors/oci.nix
{ pkgs, lib, mkExecutor }:

{ image ? "nixos/nix" }:

mkExecutor {
  name = "oci-${lib.strings.sanitizeDerivationName image}";
  
  # Setup container workspace
  # Expects $WORKFLOW_ID to be set
  setupWorkspace = { actionDerivations }: ''
    # Lazy init - only create if not exists
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "→ Creating OCI container from image: ${image}"
      
      # Create and start long-running container with /nix/store mounted
      CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}=$(${pkgs.docker}/bin/docker create \
        -v /nix/store:/nix/store:ro \
        ${image} \
        sleep infinity)
      
      ${pkgs.docker}/bin/docker start "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}"
      
      export CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}
      
      # Create workspace directory in container
      ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" mkdir -p /workspace
      
      echo "→ OCI workspace: container $CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:/workspace"
      
      # Actions available via /nix/store mount (no need to copy)
      # Could also build custom image with actionDerivations baked in
    fi
  '';
  
  # Cleanup container
  cleanupWorkspace = ''
    if [ -n "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo ""
      echo "→ Stopping and removing OCI container: $CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}"
      ${pkgs.docker}/bin/docker stop "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" >/dev/null 2>&1 || true
      ${pkgs.docker}/bin/docker rm "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" >/dev/null 2>&1 || true
    fi
  '';
  
  # Execute job in container
  executeJob = { jobName, actionDerivations, env }: ''
    # Ensure workspace is initialized
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "Error: OCI workspace not initialized for ${image}"
      exit 1
    fi
    
    ${pkgs.docker}/bin/docker exec \
      ${lib.concatMapStringsSep " " (k: "-e ${k}") (lib.attrNames env)} \
      "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" \
      bash -c ${lib.escapeShellArg ''
        set -euo pipefail
        
        # Create job directory
        JOB_DIR="/workspace/jobs/${jobName}"
        mkdir -p "$JOB_DIR"
        cd "$JOB_DIR"
        
        echo "╔════════════════════════════════════════╗"
        echo "║ JOB: ${jobName}"
        echo "║ EXECUTOR: oci-${lib.strings.sanitizeDerivationName image}"
        echo "║ WORKDIR: $JOB_DIR"
        echo "╚════════════════════════════════════════╝"
        
        # Set job-level environment
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: 
            "export ${k}=${lib.escapeShellArg (toString v)}"
          ) env
        )}
        
        # Execute action derivations
        ${lib.concatMapStringsSep "\n\n" (action: ''
          echo "→ ${action.passthru.name or "action"}"
          ${action}/bin/${action.passthru.name or "run"}
        '') actionDerivations}
      ''}
  '';
  
  fetchArtifacts = null;
  pushArtifacts = null;
  
  # Save artifact (executed on HOST after job completes)
  # Uses docker cp to copy from container to host
  saveArtifact = { name, path, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "  ✗ Container not initialized"
      return 1
    fi
    
    JOB_DIR="/workspace/jobs/${jobName}"
    
    # Check if path exists in container
    if ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" test -e "$JOB_DIR/${path}"; then
      rm -rf "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
      
      # Preserve directory structure
      PARENT_DIR=$(dirname "${path}")
      if [ "$PARENT_DIR" != "." ]; then
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}/$PARENT_DIR"
      fi
      
      # Copy from container to host
      ${pkgs.docker}/bin/docker cp \
        "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:$JOB_DIR/${path}" \
        "$NIXACTIONS_ARTIFACTS_DIR/${name}/${path}"
    else
      echo "  ✗ Path not found: ${path}"
      return 1
    fi
  '';
  
  # Restore artifact (executed on HOST before job starts)
  # Uses docker cp to copy from host to container
  restoreArtifact = { name, path, jobName }: ''
    if [ -z "''${CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:-}" ]; then
      echo "  ✗ Container not initialized"
      return 1
    fi
    
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      JOB_DIR="/workspace/jobs/${jobName}"
      
      # Ensure job directory exists in container
      ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" mkdir -p "$JOB_DIR"
      
      # Handle custom restore path
      if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
        # Restore to root of job directory
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:$JOB_DIR/"
          fi
        done
      else
        # Restore to custom path
        ${pkgs.docker}/bin/docker exec "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}" mkdir -p "$JOB_DIR/${path}"
        for item in "$NIXACTIONS_ARTIFACTS_DIR/${name}"/*; do
          if [ -e "$item" ]; then
            ${pkgs.docker}/bin/docker cp "$item" "$CONTAINER_ID_OCI_${lib.strings.sanitizeDerivationName image}:$JOB_DIR/${path}/"
          fi
        done
      fi
    else
      echo "  ✗ Artifact not found: ${name}"
      return 1
    fi
  '';
}
```

---

## User Guide

### Quick Start

#### 1. Add NixActions to project

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixactions.url = "github:yourorg/nixactions";
  };

  outputs = { nixpkgs, nixactions, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      platform = nixactions.lib.${system};
    in {
      packages.${system}.ci = platform.mkWorkflow {
        name = "ci";
        
        jobs = {
          test = {
            executor = platform.executors.local;
            actions = [
              (platform.mkAction {
                name = "test";
                bash = "npm test";
                deps = [ pkgs.nodejs ];
              })
            ];
          };
        };
      };
    };
}
```

#### 2. Build workflow

```bash
$ nix build .#ci
# Compiles workflow + all actions to /nix/store
```

#### 3. Run workflow

```bash
$ nix run .#ci

════════════════════════════════════════
 Workflow: ci
 Execution: GitHub Actions style (parallel)
 Levels: 1
════════════════════════════════════════

→ Setting up executor: local
→ Provisioned 1 derivations

→ Level 0: test

╔════════════════════════════════════════╗
║ JOB: test
║ EXECUTOR: local
╚════════════════════════════════════════╝
→ test
✓ Job test succeeded

════════════════════════════════════════
✓ Workflow completed successfully

All jobs succeeded:
  ✓ test
════════════════════════════════════════
```

---

### Complete Example

```nix
{ pkgs, platform }:

platform.mkWorkflow {
  name = "production-ci";
  
  jobs = {
    # === Level 0: Parallel checks ===
    
    lint = {
      executor = platform.executors.local;
      actions = [
        (platform.mkAction {
          name = "lint";
          bash = "eslint src/";
          deps = [ pkgs.nodejs ];
        })
      ];
    };
    
    security = {
      executor = platform.executors.local;
      actions = [
        (platform.mkAction {
          name = "audit";
          bash = "npm audit";
          deps = [ pkgs.nodejs ];
        })
      ];
      continueOnError = true;
    };
    
    # === Level 1: Tests (after checks) ===
    
    test = {
      needs = ["lint"];
      executor = platform.executors.oci { image = "node:20"; };
      
      outputs = {
        coverage = "coverage/";
      };
      
      actions = [
        (platform.mkAction {
          name = "test";
          bash = "npm test";
          deps = [ pkgs.nodejs ];
        })
      ];
    };
    
    # === Level 2: Build (after tests) ===
    
    build = {
      needs = ["test"];
      executor = platform.executors.local;
      
      inputs = ["coverage"];
      outputs = {
        dist = "dist/";
      };
      
      actions = [
        (platform.mkAction {
          name = "build";
          bash = "npm run build";
          deps = [ pkgs.nodejs ];
        })
      ];
    };
    
    # === Level 3: Deploy (only on main branch) ===
    
    deploy = {
      needs = ["build"];
      condition = ''[ "$BRANCH" = "main" ]'';
      
      executor = platform.executors.k8s {
        namespace = "production";
      };
      
      inputs = ["dist"];
      
      actions = [
        # Load secrets
        (platform.actions.sopsLoad {
          file = ./secrets/production.sops.yaml;
        })
        
        # Validate secrets
        (platform.actions.requireEnv ["DEPLOY_KEY"])
        
        # Deploy
        (platform.mkAction {
          name = "deploy";
          bash = "kubectl apply -f k8s/";
          deps = [ pkgs.kubectl ];
        })
      ];
    };
    
    # === Level 3: Notifications (always run) ===
    
    notify = {
      needs = ["build"];
      condition = "always()";
      
      executor = platform.executors.local;
      
      actions = [
        (platform.mkAction {
          name = "notify";
          bash = ''
            STATUS="''${FAILED_JOBS[@]:-success}"
            curl -X POST $WEBHOOK -d "{\"status\": \"$STATUS\"}"
          '';
          deps = [ pkgs.curl ];
          condition = "always()";
        })
      ];
    };
  };
}
```

---

## Comparison

### vs GitHub Actions

| Feature | GitHub Actions | NixActions |
|---------|---------------|------------|
| **Execution model** | Parallel + needs | ✅ Same |
| **Dependencies** | `needs: [...]` | ✅ Same |
| **Conditions** | `if: success()` etc | ✅ `condition` (unified) |
| **Step conditions** | `steps[].if` | ✅ `actions[].condition` |
| **Continue on error** | `continue-on-error` | ✅ Same (`continueOnError`) |
| **Actions** | JavaScript/Docker | ✅ Nix derivations |
| **Build-time validation** | ❌ Runtime only | ✅ Yes (Nix) |
| **Infrastructure** | GitHub.com | ✅ None (agentless) |
| **Local execution** | `act` (hacky) | ✅ Native `nix run` |
| **Reproducibility** | ❌ Variable | ✅ Guaranteed (Nix) |
| **Type safety** | ❌ YAML | ✅ Nix |
| **Cost** | $21/month | ✅ $0 |

---

## Roadmap

### Phase 1: MVP ✅

- ✅ Actions as derivations
- ✅ Build-time compilation
- ✅ Executor provisioning
- ✅ Condition system (job + step level)
- ✅ Local executor
- ✅ Basic actions library

### Phase 2: Remote Executors ⏳

- ⏳ OCI executor with provisioning
- ⏳ SSH executor with nix-copy-closure
- ⏳ K8s executor
- ✅ Artifacts (inputs/outputs)
- ✅ Custom restore paths for artifacts

### Phase 3: Ecosystem ⏳

- ⏳ Extended actions library
- ⏳ Documentation
- ⏳ Examples
- ⏳ Templates

---

## Summary

**NixActions v4.0 = GitHub Actions execution + Nix reproducibility + Actions as Derivations**

**Key innovations:**
- ✅ Actions are Nix derivations (build-time compilation)
- ✅ Executors provision derivations once (not per-job)
- ✅ Unified `condition` system (jobs + actions)
- ✅ Build-time validation
- ✅ Caching via Nix store
- ✅ Parallel execution (GitHub Actions style)
- ✅ Explicit dependencies via `needs`
- ✅ Agentless (SSH/containers/local)
- ✅ Type-safe (Nix, not YAML)

**Positioning:**
> "GitHub Actions execution model + Nix reproducibility + Build-time action compilation = NixActions"

**This is the v4.0 design!** 🚀
