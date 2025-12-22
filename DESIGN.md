# NixActions Design Document v3.0 - GitHub Actions Style

## Executive Summary

**NixActions** - agentless CI/CD platform powered by Nix, following GitHub Actions execution model.

**Elevator pitch:** "Ansible for CI/CD with a type-safe DSL and deterministic environments"

**Core concept:** Compile workflows into self-contained executables that run anywhere without agents or central infrastructure.

**Execution model:** GitHub Actions style - parallel by default, explicit dependencies via `needs`.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Architecture](#architecture)
3. [Core Contracts](#core-contracts)
4. [Execution Model](#execution-model)
5. [Secrets Management](#secrets-management)
6. [Artifacts Management](#artifacts-management)
7. [API Reference](#api-reference)
8. [Implementation](#implementation)
9. [User Guide](#user-guide)
10. [Comparison](#comparison)
11. [Roadmap](#roadmap)

---

## Philosophy

### Core Principles

1. **Local-first**: CI should work locally first, remote is optional
2. **Agentless**: No persistent agents, no polling, no registration
3. **Deterministic**: Nix guarantees reproducibility
4. **Composable**: Everything is a function, everything composes
5. **Simple**: Minimal abstractions, maximum power
6. **Parallel**: Jobs without dependencies run in parallel (like GitHub Actions)

### Design Philosophy

```
GitHub Actions execution model:
  ✅ Parallel by default
  ✅ Explicit dependencies (needs)
  ✅ Conditional execution (if)
  ✅ DAG-based ordering

+ Nix reproducibility:
  ✅ Deterministic builds
  ✅ Self-contained
  ✅ Type-safe

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
│  └─ { executor, actions, needs, if }    │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 2: Executor (где выполнить)       │
│  └─ mkExecutor { execute, provision }   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 1: Action (что делать)            │
│  └─ { name, bash, deps }                │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ Level 0: Derivations (artifacts)        │
│  └─ Built with Nix, stored in /nix/store│
└─────────────────────────────────────────┘
```

---

## Core Contracts

### Contract 1: Action

**Definition:** Atomic unit of work = bash script + dependencies

**Type Signature:**
```nix
Action :: {
  name     :: String,          # Optional, default "action"
  bash     :: String,          # Required
  deps     :: [Derivation],    # Optional, default []
  env      :: AttrSet String,  # Optional, default {}
  workdir  :: Path | Null,     # Optional, default null
}
```

**Contract:**
- Action is ALWAYS a bash script (not a derivation)
- Derivations are collected in `let`, used via `${drv}`
- `deps` - list of Nix packages for PATH
- Composition = bash concatenation

**Examples:**

```nix
# Minimal action
{
  bash = "npm test";
}

# With dependencies
{
  name = "test";
  deps = [ pkgs.nodejs ];
  bash = "npm test";
}

# Uses derivation
let
  app = pkgs.buildNpmPackage { /* ... */ };
in {
  name = "package";
  bash = "echo 'Built: ${app}'";
}
```

---

### Contract 2: Executor

**Definition:** Abstraction of "where to execute bash" + workspace management

**Type Signature:**
```nix
Executor :: {
  name             :: String,
  setupWorkspace   :: String,                                    # Lazy init workspace
  cleanupWorkspace :: String,                                    # Cleanup at workflow end
  executeJob       :: { jobName :: String, script :: String } -> String,  # Execute job
  provision        :: ([Derivation] -> String) | Null,           # Optional provision
  canProvision     :: Bool,                                      # Computed
}
```

**Constructor:**
```nix
mkExecutor :: {
  name             :: String,
  setupWorkspace   :: String,                                    # Bash: setup workspace
  cleanupWorkspace :: String,                                    # Bash: cleanup workspace
  executeJob       :: { jobName, script } -> String,             # Bash: execute job
  provision        :: (([Derivation] -> String) | Null) = null,
} -> Executor
```

**Responsibilities:**

1. **Workspace Management**
   - `setupWorkspace`: Create workspace (lazy-init, expects `$WORKFLOW_ID`)
   - `cleanupWorkspace`: Remove workspace at workflow end
   - Jobs create isolated directories: `$WORKSPACE_DIR/jobs/${jobName}`

2. **Job Execution**
   - `executeJob`: Execute job script in isolated directory
   - Each job runs in: `$WORKSPACE_DIR/jobs/${jobName}`

3. **Artifacts Integration**
   - Executor provides `$NIXACTIONS_ARTIFACTS_DIR` to jobs
   - Artifacts storage mounted/accessible outside workspace (survives cleanup)

**Key Design:**
- **Job isolation by convention** - each job gets own directory
- **Artifacts = explicit data flow** - recommended for sharing between jobs
- **Lazy init** - executor only sets up when first job runs

**⚠️ IMPORTANT - File Sharing Behavior:**

Reading files from other jobs' directories is **undefined behavior**:

```nix
# ❌ BAD - Undefined behavior (might work, might not)
jobs = {
  build.steps = [ "echo output > result.txt" ];
  test.steps = [ "cat ../build/result.txt" ];  # UB!
}

# ✅ GOOD - Explicit artifacts
jobs = {
  build.steps = [ 
    "echo output > result.txt"
    "saveArtifacts build-output result.txt"
  ];
  test.steps = [
    "restoreArtifacts build-output"
    "cat result.txt"
  ];
}
```

**Why UB?**
- Different executors have different cleanup behavior
- File visibility depends on timing and executor implementation
- Multi-machine executors (SSH, K8s) can't access local files
- Future optimizations may add aggressive cleanup

**When it might work anyway:**
- Same executor for all jobs
- Jobs run sequentially (not parallel)
- Local executor with no cleanup

**We don't prevent it, but we don't guarantee it works.** Use artifacts for reliable data flow.

---

### Contract 3: Job (GitHub Actions Style)

**Definition:** Composition of actions + executor + metadata

**Type Signature:**
```nix
Job :: {
  # Required
  executor :: Executor,
  actions  :: [Action],
  
  # Dependencies (GitHub Actions style)
  needs :: [String] = [],
  
  # Conditional execution (GitHub Actions style)
  if :: "success()" | "failure()" | "always()" | "cancelled()" = "success()",
  
  # Error handling
  continueOnError :: Bool = false,
}
```

**Conditions:**
- `"success()"` - run only if all needed jobs succeeded (default)
- `"failure()"` - run only if any needed job failed
- `"always()"` - run regardless of previous job status
- `"cancelled()"` - run only if workflow was cancelled

**Examples:**

```nix
jobs = {
  # No needs - runs immediately (parallel with others)
  lint = {
    executor = executors.local;
    actions = [{ bash = "npm run lint"; }];
  };
  
  # Runs after lint succeeds
  test = {
    needs = [ "lint" ];
    executor = executors.nixos-container;
    actions = [{ bash = "npm test"; }];
  };
  
  # Always runs (notification)
  notify = {
    needs = [ "test" ];
    if = "always()";
    actions = [{
      bash = ''
        curl -X POST $SLACK_WEBHOOK \
          -d '{"text": "Tests completed"}'
      '';
    }];
  };
  
  # Only on failure (cleanup)
  cleanup-on-failure = {
    needs = [ "test" ];
    if = "failure()";
    actions = [{ bash = "rm -rf /tmp/test-data"; }];
  };
}
```

---

### Contract 4: Workflow (GitHub Actions Style)

**Definition:** DAG of jobs with parallel execution

**Type Signature:**
```nix
WorkflowConfig :: {
  name :: String,
  jobs :: AttrSet Job,
}
```

**Constructor:**
```nix
mkWorkflow :: {
  name :: String,
  jobs :: AttrSet Job,
} -> Derivation  # Bash script
```

**Execution Model (GitHub Actions):**
1. Group jobs by dependency level
2. Execute each level in parallel
3. Wait for level completion before proceeding
4. Apply `if` conditions
5. Stop on failure (unless `continueOnError`)

**Example:**

```nix
mkWorkflow {
  name = "ci";
  
  jobs = {
    # Level 0 (parallel)
    lint-js = {
      executor = executors.local;
      actions = [{ bash = "eslint ."; }];
    };
    
    lint-css = {
      executor = executors.local;
      actions = [{ bash = "stylelint ."; }];
    };
    
    # Level 1 (parallel, after level 0)
    test = {
      needs = [ "lint-js" "lint-css" ];
      executor = executors.nixos-container;
      actions = [{ bash = "npm test"; }];
    };
    
    build-docs = {
      needs = [ "lint-js" "lint-css" ];
      actions = [{ bash = "npm run docs"; }];
    };
    
    # Level 2 (after level 1)
    deploy = {
      needs = [ "test" "build-docs" ];
      actions = [{ bash = "kubectl apply -f k8s/"; }];
    };
    
    # Level 2 (parallel with deploy, always runs)
    notify = {
      needs = [ "test" "build-docs" ];
      if = "always()";
      actions = [{
        bash = "curl -X POST $SLACK_WEBHOOK -d '{\"text\": \"CI done\"}'";
      }];
    };
  };
}
```

**Execution Visualization:**
```
Level 0 (parallel):
  ├─ lint-js ────┤
  └─ lint-css ───┤

Level 1 (parallel, after level 0):
                 ├─ test ──────┤
                 └─ build-docs ─┤

Level 2 (parallel, after level 1):
                                ├─ deploy ────┤
                                └─ notify ────┤
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

3. Execute level by level:
   for each level:
     - Start all jobs in level in parallel
     - Wait for all to complete
     - Check conditions (if: success/failure/always)
     - Proceed to next level

4. Stop on failure:
   - If job fails and continueOnError = false → stop workflow
   - If job fails and continueOnError = true → continue
   - Jobs with if: always() always run
   - Jobs with if: failure() only run if failures occurred
```

### Condition Evaluation

```nix
# Job status tracking
JOB_STATUS = {
  "job-name" => "success" | "failure" | "skipped" | "cancelled"
}

FAILED_JOBS = [list of failed job names]

# Condition check
shouldRun(job) =
  case job.if:
    "success()" => FAILED_JOBS is empty AND all(needs) succeeded
    "failure()" => FAILED_JOBS is not empty
    "always()"  => true
    "cancelled()" => workflow was cancelled
```

### Parallel Execution

Jobs in the same level run in parallel:

```bash
# Level execution (simplified)
run_level() {
  local -a pids=()
  
  for job in level_jobs; do
    run_job "$job" &
    pids+=($!)
  done
  
  # Wait for all
  for pid in "${pids[@]}"; do
    wait "$pid" || handle_failure
  done
}
```

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

#### Action-level Environment

```nix
{
  env = {
    NODE_ENV = "production";
    LOG_LEVEL = "info";
  };
  bash = ''
    echo "Environment: $NODE_ENV"
    npm run build
  '';
}
```

#### Job-level Environment

```nix
Job :: {
  env :: AttrSet String = {},
  ...
}

# All actions inherit job env
test = {
  env = {
    CI = "true";
    NODE_ENV = "test";
  };
  
  actions = [
    { bash = "echo $CI"; }        # "true"
    { bash = "echo $NODE_ENV"; }  # "test"
    {
      env.NODE_ENV = "production";  # Override
      bash = "echo $NODE_ENV";      # "production"
    }
  ];
};
```

#### Workflow-level Environment

```nix
WorkflowConfig :: {
  env :: AttrSet String = {},
  ...
}

# All jobs inherit workflow env
platform.mkWorkflow {
  name = "ci";
  
  env = {
    COMPANY = "acme";
    REGION = "us-east-1";
  };
  
  jobs = {
    test = {
      actions = [
        { bash = "echo $COMPANY"; }  # "acme"
      ];
    };
  };
}
```

#### Runtime Environment

```bash
# Override any env at runtime (highest priority)
$ API_KEY=xyz123 nix run .#ci

# Load from .env file
$ export $(cat .env | xargs)
$ nix run .#ci

# One-liner with secrets
$ VAULT_TOKEN=$(vault login -token-only) nix run .#deploy
```

---

### Built-in Secrets Actions

#### SOPS (Mozilla) - Recommended

```nix
platform.actions.sopsLoad :: {
  file   :: Path,
  format :: "yaml" | "json" | "dotenv" = "yaml",
} -> Action
```

**Example:**
```nix
{
  actions = [
    (platform.actions.sopsLoad {
      file = ./secrets.sops.yaml;
    })
    {
      bash = ''
        echo "Deploying with key: $API_KEY"
        kubectl create secret generic app-secrets \
          --from-literal=api-key="$API_KEY"
      '';
    }
  ];
}
```

**Implementation:**
```nix
# lib/actions/sops.nix
{ pkgs }:

{ file, format ? "yaml" }:

{
  name = "sops-load";
  deps = [ pkgs.sops pkgs.yq pkgs.jq ];
  
  bash = ''
    echo "→ Loading secrets from ${file}"
    
    # Export all keys from SOPS file
    ${if format == "dotenv" then ''
      # .env format - direct export
      export $(sops -d ${file} | xargs)
    '' else if format == "yaml" then ''
      # YAML - convert to env vars
      eval $(sops -d ${file} | yq -r 'to_entries | .[] | "export \(.key)=\(.value)"')
    '' else if format == "json" then ''
      # JSON - convert to env vars
      eval $(sops -d ${file} | jq -r 'to_entries | .[] | "export \(.key)=\(.value)"')
    '' else
      throw "Unknown format: ${format}"
    }
    
    echo "✓ Loaded secrets"
  '';
}
```

#### HashiCorp Vault

```nix
platform.actions.vaultLoad :: {
  path  :: String,
  addr  :: String = "$VAULT_ADDR",
  token :: String | Null = null,
} -> Action
```

**Example:**
```nix
{
  actions = [
    (platform.actions.vaultLoad {
      path = "secret/data/production/app";
      addr = "https://vault.company.com";
      # token from $VAULT_TOKEN env
    })
    {
      bash = ''
        echo "DB password: $DB_PASSWORD"
        psql "postgresql://user:$DB_PASSWORD@host/db"
      '';
    }
  ];
}
```

**Implementation:**
```nix
# lib/actions/vault.nix
{ pkgs }:

{ path, addr ? "$VAULT_ADDR", token ? null }:

{
  name = "vault-load";
  deps = [ pkgs.vault pkgs.jq ];
  
  bash = ''
    echo "→ Loading secrets from Vault: ${path}"
    
    export VAULT_ADDR="${addr}"
    ${if token != null then ''
      export VAULT_TOKEN="${token}"
    '' else ""}
    
    # Read secrets and export as env vars
    vault kv get -format=json ${path} | \
      jq -r '.data.data | to_entries | .[] | "export \(.key)=\(.value)"' | \
      while IFS= read -r line; do
        eval "$line"
      done
    
    echo "✓ Loaded secrets from Vault"
  '';
}
```

#### 1Password

```nix
platform.actions.opLoad :: {
  vault :: String,
  item  :: String,
} -> Action
```

**Example:**
```nix
{
  actions = [
    (platform.actions.opLoad {
      vault = "Production";
      item = "AWS Credentials";
    })
    { bash = "aws s3 ls"; }
  ];
}
```

#### Age (simple file encryption)

```nix
platform.actions.ageDecrypt :: {
  file     :: Path,
  identity :: Path,
} -> Action
```

**Example:**
```nix
{
  actions = [
    (platform.actions.ageDecrypt {
      file = ./secrets.age;
      identity = /home/user/.age/key.txt;
    })
    { bash = "echo $API_KEY > /tmp/key"; }
  ];
}
```

#### Bitwarden

```nix
platform.actions.bwLoad :: {
  itemId :: String,
} -> Action
```

#### Environment Validation

```nix
platform.actions.requireEnv :: [String] -> Action
```

**Example:**
```nix
{
  actions = [
    (platform.actions.sopsLoad { file = ./secrets.sops.yaml; })
    (platform.actions.requireEnv [ "API_KEY" "DB_PASSWORD" ])
    { bash = "deploy.sh"; }
  ];
}
```

**Implementation:**
```nix
# lib/actions/require-env.nix
{ pkgs, lib }:

vars:

{
  name = "require-env";
  bash = lib.concatMapStringsSep "\n" (var: ''
    if [ -z "''${${var}:-}" ]; then
      echo "ERROR: Required env var not set: ${var}"
      exit 1
    fi
  '') vars;
}
```

---

### Complete Secrets Example

```nix
# ci.nix
{ pkgs, platform }:

platform.mkWorkflow {
  name = "deploy-with-secrets";
  
  jobs = {
    deploy-staging = {
      executor = platform.executors.ssh {
        host = "staging.company.com";
      };
      
      actions = [
        # 1. Load secrets from SOPS
        (platform.actions.sopsLoad {
          file = ./secrets/staging.sops.yaml;
        })
        
        # 2. Load additional secrets from Vault
        (platform.actions.vaultLoad {
          path = "secret/data/staging/database";
          addr = "https://vault.internal";
        })
        
        # 3. Validate secrets are present
        (platform.actions.requireEnv [
          "API_KEY"
          "DB_PASSWORD"
        ])
        
        # 4. Use secrets
        {
          bash = ''
            echo "→ Deploying with secrets"
            
            kubectl create secret generic app-secrets \
              --from-literal=api-key="$API_KEY" \
              --from-literal=db-password="$DB_PASSWORD"
            
            kubectl apply -f k8s/
          '';
        }
      ];
    };
    
    deploy-production = {
      needs = [ "deploy-staging" ];
      
      executor = platform.executors.k8s {
        namespace = "production";
      };
      
      actions = [
        # Production uses different secrets
        (platform.actions.sopsLoad {
          file = ./secrets/production.sops.yaml;
        })
        
        # And different Vault path
        (platform.actions.vaultLoad {
          path = "secret/data/production/database";
        })
        
        (platform.actions.requireEnv [
          "API_KEY"
          "DB_PASSWORD"
        ])
        
        {
          bash = ''
            kubectl create secret generic app-secrets \
              --from-literal=api-key="$API_KEY" \
              --from-literal=db-password="$DB_PASSWORD"
            
            kubectl apply -f k8s/
          '';
        }
      ];
    };
  };
}
```

---

### Security Best Practices

#### 1. Never commit secrets to Nix files

```nix
# ❌ BAD - hardcoded secret
{
  env.API_KEY = "xyz123";
  bash = "curl -H 'Authorization: Bearer $API_KEY' ...";
}

# ✅ GOOD - read from runtime env
{
  bash = ''
    if [ -z "$API_KEY" ]; then
      echo "ERROR: API_KEY not set"
      exit 1
    fi
    
    curl -H "Authorization: Bearer $API_KEY" ...
  '';
}

# ✅ BEST - use secrets manager
{
  actions = [
    (platform.actions.sopsLoad {
      file = ./secrets.sops.yaml;
    })
    (platform.actions.requireEnv [ "API_KEY" ])
    { bash = "curl -H \"Authorization: Bearer $API_KEY\" ..."; }
  ];
}
```

#### 2. Validate secrets are loaded

Always use `requireEnv` after loading secrets:

```nix
{
  actions = [
    (platform.actions.sopsLoad { file = ./secrets.sops.yaml; })
    (platform.actions.requireEnv [ "API_KEY" "DB_PASSWORD" ])
    { bash = "deploy.sh"; }
  ];
}
```

#### 3. Use encrypted files (SOPS recommended)

```bash
# Create encrypted secrets file
$ sops secrets/production.sops.yaml

# File content (encrypted at rest):
api_key: ENC[AES256_GCM,data:...,tag:...]
db_password: ENC[AES256_GCM,data:...,tag:...]

# Commit encrypted file to git
$ git add secrets/production.sops.yaml
$ git commit -m "Add production secrets (encrypted)"
```

#### 4. Secrets masking in logs

```nix
# lib/mk-workflow.nix
# Mask common secret patterns in output

execute = script: ''
  # Mask secrets in logs
  ${script} 2>&1 | sed \
    -e 's/password=[^& ]*/password=***/g' \
    -e 's/token=[^& ]*/token=***/g' \
    -e 's/key=[^& ]*/key=***/g' \
    -e 's/apikey=[^& ]*/apikey=***/g'
'';
```

---

### Runtime Usage Examples

#### Load from SOPS

```bash
# Secrets are decrypted on-the-fly during workflow execution
$ nix run .#deploy
→ Loading secrets from ./secrets/production.sops.yaml
✓ Loaded secrets
→ Deploying...
```

#### Load from Vault

```bash
# Authenticate with Vault first
$ export VAULT_TOKEN=$(vault login -token-only)
$ nix run .#deploy
→ Loading secrets from Vault: secret/data/production/app
✓ Loaded secrets from Vault
→ Deploying...
```

#### Override at runtime

```bash
# Override specific secrets
$ API_KEY=custom-key nix run .#deploy

# Load all secrets from environment
$ export $(sops -d secrets/dev.sops.yaml | xargs)
$ nix run .#deploy
```

---

## Artifacts Management

### Philosophy

**Artifacts allow jobs to share files explicitly and safely.**

**Key principles:**
1. ✅ **Explicit transfer** - artifacts API for reliable file sharing
2. ✅ **Executor-scoped** - artifacts work within same executor
3. ✅ **Survives cleanup** - artifacts stored outside workspace
4. ⚠️ **Job isolation by convention** - job directories persist but reading across jobs is UB

**Design decision:** Artifacts provide **guaranteed** file sharing. Reading files from other job directories is **undefined behavior** (might work, but not guaranteed).

---

### Storage Architecture

#### Location

Artifacts are stored **outside workspace** to survive job cleanup:

```
Host machine:
  $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/
  ├── dist.tar.gz
  ├── coverage.tar.gz
  └── test-results.tar.gz

Workspace (persists until workflow end):
  /tmp/nixactions/$WORKFLOW_ID/jobs/build/     ← may persist (UB to rely on this)
  /tmp/nixactions/$WORKFLOW_ID/jobs/test/      ← may persist (UB to rely on this)
```

#### Executor Integration

Each executor mounts artifacts storage:

**Local executor:**
```
Workspace:    /tmp/nixactions/$WORKFLOW_ID/
Artifacts:    $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/
```

**OCI executor:**
```
Workspace:    /workspace/ (inside container)
Artifacts:    /artifacts (bind-mount from $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/)
```

**SSH executor:**
```
Workspace:    /var/tmp/nixactions/$WORKFLOW_ID/ (on remote)
Artifacts:    $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/ (on remote)
```

**K8s executor:**
```
Workspace:    /workspace/ (inside pod)
Artifacts:    /artifacts (PVC or hostPath mount)
```

---

### Lifecycle

```
1. Job starts
   → Workspace created: /tmp/nixactions/$WORKFLOW_ID/jobs/build/
   → Artifacts dir available: $NIXACTIONS_ARTIFACTS_DIR

2. Job executes
   → Can save artifacts: saveArtifacts { name = "dist"; paths = ["dist/"]; }
   → Can restore artifacts: restoreArtifacts { name = "dist"; }

3. Job ends
   → Job dir may persist (executor-dependent, UB to rely on)
   → Artifacts PRESERVED: $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/

4. Workflow ends
   → All job workspaces deleted
   → Artifacts preserved (unless NIXACTIONS_KEEP_ARTIFACTS=0)
```

---

### Actions API

#### saveArtifacts

Save files from current job for use in later jobs.

**Type:**
```nix
saveArtifacts :: {
  name  :: String,           # Artifact name (must be unique)
  paths :: String | [String] # Files/directories to save
} -> Action
```

**Example:**
```nix
{
  actions = [
    { bash = "npm run build"; }
    
    (platform.actions.saveArtifacts {
      name = "dist";
      paths = [ "dist/" "package.json" ];
    })
  ];
}
```

**Implementation:**
```bash
# Creates tarball in artifacts directory
tar czf $NIXACTIONS_ARTIFACTS_DIR/dist.tar.gz dist/ package.json
```

#### restoreArtifacts

Restore previously saved artifacts to current job.

**Type:**
```nix
restoreArtifacts :: {
  name :: String  # Artifact name to restore
} -> Action
```

**Example:**
```nix
{
  needs = ["build"];
  actions = [
    (platform.actions.restoreArtifacts {
      name = "dist";
    })
    
    { bash = "npm test"; }  # Uses restored dist/
  ];
}
```

**Implementation:**
```bash
# Extracts tarball to current directory
tar xzf $NIXACTIONS_ARTIFACTS_DIR/dist.tar.gz
```

---

### Usage Examples

#### Single Executor Workflow

```nix
platform.mkWorkflow {
  name = "ci";
  
  jobs = {
    build = {
      executor = platform.executors.local;
      actions = [
        { bash = "npm run build"; }
        
        # Save build artifacts
        (platform.actions.saveArtifacts {
          name = "dist";
          paths = ["dist/"];
        })
      ];
    };
    
    test = {
      needs = ["build"];
      executor = platform.executors.local;  # Same executor
      actions = [
        # Restore build artifacts
        (platform.actions.restoreArtifacts {
          name = "dist";
        })
        
        { bash = "npm test"; }
      ];
    };
    
    deploy = {
      needs = ["test"];
      executor = platform.executors.local;  # Same executor
      actions = [
        # Restore build artifacts again
        (platform.actions.restoreArtifacts {
          name = "dist";
        })
        
        { bash = "rsync dist/ server:/var/www/"; }
      ];
    };
  };
}
```

**Result:**
- ✅ build creates `dist/`
- ✅ build saves to `$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/dist.tar.gz`
- ✅ build workspace cleaned (dist/ deleted from job directory)
- ✅ test restores `dist/` from artifacts
- ✅ test workspace cleaned
- ✅ deploy restores `dist/` from artifacts
- ✅ deploy completes, workflow ends
- ✅ artifacts preserved in `$HOME/.cache/`

---

#### Multi-Executor Workflow (Same Executor Type)

```nix
jobs = {
  test-node-16 = {
    executor = platform.executors.oci { image = "node:16"; };
    actions = [
      { bash = "npm test"; }
      (platform.actions.saveArtifacts {
        name = "coverage";
        paths = ["coverage/"];
      })
    ];
  };
  
  test-node-18 = {
    executor = platform.executors.oci { image = "node:18"; };
    actions = [
      { bash = "npm test"; }
      (platform.actions.saveArtifacts {
        name = "coverage-18";
        paths = ["coverage/"];
      })
    ];
  };
  
  report = {
    needs = ["test-node-16" "test-node-18"];
    executor = platform.executors.local;  # Different executor!
    actions = [
      # ✅ Can restore from OCI containers
      (platform.actions.restoreArtifacts { name = "coverage"; })
      (platform.actions.restoreArtifacts { name = "coverage-18"; })
      
      { bash = "merge-coverage coverage/ coverage-18/"; }
    ];
  };
}
```

**How it works:**
- All executors share same artifacts directory on host: `$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/`
- OCI containers bind-mount this directory to `/artifacts`
- Local executor accesses it directly
- Artifacts survive container cleanup

---

#### Cross-Executor Transfer (Advanced)

For transferring artifacts between **different machines** (e.g., local → SSH), use explicit commands:

```nix
jobs = {
  build = {
    executor = platform.executors.local;  # Runs on laptop
    actions = [
      { bash = "npm run build"; }
      (platform.actions.saveArtifacts {
        name = "dist";
        paths = ["dist/"];
      })
      
      # Explicitly transfer to remote
      {
        bash = ''
          scp $NIXACTIONS_ARTIFACTS_DIR/dist.tar.gz server:~/artifacts/
        '';
      }
    ];
  };
  
  deploy = {
    needs = ["build"];
    executor = platform.executors.ssh { host = "server"; };  # Runs on server
    actions = [
      # Explicitly fetch from known location
      {
        bash = ''
          mkdir -p $NIXACTIONS_ARTIFACTS_DIR
          cp ~/artifacts/dist.tar.gz $NIXACTIONS_ARTIFACTS_DIR/
        '';
      }
      
      (platform.actions.restoreArtifacts {
        name = "dist";
      })
      
      { bash = "rsync dist/ /var/www/"; }
    ];
  };
}
```

**Note:** This is intentionally explicit. For automated cross-machine artifacts, configure a shared storage backend (future feature).

---

### Cleanup Strategy

#### Default Behavior

```bash
# During workflow
- Job workspace cleaned after each job
- Artifacts preserved

# After workflow
- All workspaces cleaned
- Artifacts preserved in $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/
```

#### Manual Cleanup

```bash
# Keep artifacts after workflow
NIXACTIONS_KEEP_ARTIFACTS=1 nix run .#ci

# Remove old artifacts
rm -rf $HOME/.cache/nixactions/*/artifacts/

# Auto-cleanup (future feature)
# Artifacts older than 7 days automatically removed
```

---

### Constraints

#### Same-Executor Sharing

Artifacts work seamlessly within the same executor:

```nix
# ✅ Works - both jobs use platform.executors.local
build = { executor = platform.executors.local; ... }
test  = { executor = platform.executors.local; ... }

# ✅ Works - both jobs use OCI with same image
test1 = { executor = platform.executors.oci { image = "node:20"; }; ... }
test2 = { executor = platform.executors.oci { image = "node:20"; }; ... }

# ✅ Works - same host, different containers
build = { executor = platform.executors.local; ... }
test  = { executor = platform.executors.oci { image = "node:20"; }; ... }
```

#### Cross-Machine Limitations

```nix
# ⚠️ Requires explicit transfer - different physical machines
build  = { executor = platform.executors.local; ... }      # Laptop
deploy = { executor = platform.executors.ssh { ... }; ... } # Remote server
```

For cross-machine scenarios, use explicit file transfer (scp/rsync/s3) or configure shared storage.

---

### Benefits

1. **No accidental coupling** - Jobs can't accidentally depend on files from other jobs
2. **Clean workspaces** - Each job starts with empty workspace
3. **Explicit data flow** - Easy to see what data flows between jobs
4. **Portable** - Same pattern works across executors
5. **Debuggable** - Artifacts preserved for inspection after workflow

---

## API Reference

### Platform API

```nix
platform :: {
  # Core constructors
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
  
  # Standard actions
  actions :: {
    # Setup
    checkout     :: Action,
    setupNode    :: { version :: String } -> Action,
    setupPython  :: { version :: String } -> Action,
    setupRust    :: Action,
    
    # Package management
    nixShell     :: [String] -> Action,  # Dynamic package loading
    
    # NPM actions
    npmInstall   :: Action,
    npmTest      :: Action,
    npmBuild     :: Action,
    npmLint      :: Action,
    
    # Artifacts
    saveArtifacts    :: { name :: String, paths :: String | [String] } -> Action,
    restoreArtifacts :: { name :: String } -> Action,
    
    # Secrets management
    sopsLoad     :: { file :: Path, format :: "yaml" | "json" | "dotenv" } -> Action,
    vaultLoad    :: { path :: String, addr :: String, token :: String | Null } -> Action,
    opLoad       :: { vault :: String, item :: String } -> Action,
    ageDecrypt   :: { file :: Path, identity :: Path } -> Action,
    bwLoad       :: { itemId :: String } -> Action,
    requireEnv   :: [String] -> Action,
  },
}
```

### Built-in Executors

All executors follow the same interface contract defined in Contract 2.

#### Local Executor

Executes jobs on the local machine.

```nix
executors.local :: Executor

# Implementation
{
  name = "local";
  
  # Lazy init - creates /tmp/nixactions/$WORKFLOW_ID
  setupWorkspace = ''
    if [ -z "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      export WORKSPACE_DIR_LOCAL
      echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
    fi
  '';
  
  # Cleanup workspace directory
  cleanupWorkspace = ''
    if [ -n "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        rm -rf "$WORKSPACE_DIR_LOCAL"
      fi
    fi
  '';
  
  # Execute job in isolated directory
  executeJob = { jobName, script }: ''
    # Setup workspace and artifacts
    if [ -z "''${WORKSPACE_DIR_LOCAL:-}" ]; then
      WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
      mkdir -p "$WORKSPACE_DIR_LOCAL"
      export WORKSPACE_DIR_LOCAL
    fi
    
    NIXACTIONS_ARTIFACTS_DIR="''${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
    export NIXACTIONS_ARTIFACTS_DIR
    
    # Create and enter job directory
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    mkdir -p "$JOB_DIR"
    cd "$JOB_DIR"
    
    # Execute
    ${script}
  '';
  
  # Cleanup job directory after execution
  cleanupJob = { jobName }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    if [ -d "$JOB_DIR" ]; then
      rm -rf "$JOB_DIR"
    fi
  '';
  
  provision = null;
}
```

**Key features:**
- ✅ Workspace in `/tmp/nixactions/$WORKFLOW_ID`
- ✅ Artifacts in `$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts`
- ✅ Per-job cleanup (no implicit file sharing)

---

#### SSH Executor

Executes jobs on remote host via SSH.

```nix
executors.ssh :: {
  host :: String,
  user :: String = "runner",
  port :: Int = 22,
} -> Executor

# Implementation
{
  name = "ssh-${host}";
  
  # Create remote workspace
  setupWorkspace = ''
    if [ -z "''${WORKSPACE_DIR_SSH_${host}:-}" ]; then
      WORKSPACE_DIR_SSH_${host}="/var/tmp/nixactions/$WORKFLOW_ID"
      export WORKSPACE_DIR_SSH_${host}
      
      # Create workspace and artifacts on remote
      ssh -p ${port} ${user}@${host} \
        "mkdir -p $WORKSPACE_DIR_SSH_${host} \$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
      
      echo "→ SSH workspace: ${user}@${host}:$WORKSPACE_DIR_SSH_${host}"
    fi
  '';
  
  # Cleanup remote workspace
  cleanupWorkspace = ''
    if [ -n "''${WORKSPACE_DIR_SSH_${host}:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        ssh -p ${port} ${user}@${host} "rm -rf $WORKSPACE_DIR_SSH_${host}"
      fi
    fi
  '';
  
  # Execute job on remote
  executeJob = { jobName, script }: ''
    ssh -p ${port} ${user}@${host} bash -c ${escapeShellArg ''
      # Setup artifacts
      export NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
      
      # Create job directory
      JOB_DIR="$WORKSPACE_DIR_SSH_${host}/jobs/${jobName}"
      mkdir -p "$JOB_DIR"
      cd "$JOB_DIR"
      
      # Execute
      ${script}
    ''}
  '';
  
  # Cleanup job directory on remote
  cleanupJob = { jobName }: ''
    ssh -p ${port} ${user}@${host} \
      "rm -rf $WORKSPACE_DIR_SSH_${host}/jobs/${jobName}"
  '';
  
  # Copy Nix closures to remote
  provision = derivations: ''
    nix-copy-closure --to ${user}@${host} ${toString derivations}
  '';
}
```

**Key features:**
- ✅ Remote workspace in `/var/tmp/nixactions/$WORKFLOW_ID`
- ✅ Artifacts on remote host `$HOME/.cache/...`
- ✅ Nix closure provisioning
- ✅ SSH key-based auth (no password)

---

#### OCI Executor

Executes jobs in Docker containers.

```nix
executors.oci :: {
  image :: String = "nixos/nix",
} -> Executor

# Implementation
{
  name = "oci-${sanitize(image)}";
  
  # Create long-running container with artifacts mount
  setupWorkspace = ''
    if [ -z "''${CONTAINER_ID_OCI_${sanitize(image)}:-}" ]; then
      # Setup artifacts on host
      NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
      mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
      export NIXACTIONS_ARTIFACTS_DIR
      
      # Create container with bind-mounts
      CONTAINER_ID_OCI_${sanitize(image)}=$(docker create \
        -v /nix/store:/nix/store:ro \
        -v "$NIXACTIONS_ARTIFACTS_DIR:/artifacts" \
        ${image} \
        sleep infinity)
      
      docker start "$CONTAINER_ID_OCI_${sanitize(image)}"
      export CONTAINER_ID_OCI_${sanitize(image)}
      
      docker exec "$CONTAINER_ID_OCI_${sanitize(image)}" mkdir -p /workspace
      
      echo "→ OCI workspace: container $CONTAINER_ID_OCI_${sanitize(image)}"
    fi
  '';
  
  # Stop and remove container
  cleanupWorkspace = ''
    if [ -n "''${CONTAINER_ID_OCI_${sanitize(image)}:-}" ]; then
      docker stop "$CONTAINER_ID_OCI_${sanitize(image)}" >/dev/null 2>&1
      docker rm "$CONTAINER_ID_OCI_${sanitize(image)}" >/dev/null 2>&1
    fi
  '';
  
  # Execute job in container
  executeJob = { jobName, script }: ''
    docker exec "$CONTAINER_ID_OCI_${sanitize(image)}" bash -c ${escapeShellArg ''
      # Artifacts available at /artifacts
      export NIXACTIONS_ARTIFACTS_DIR="/artifacts"
      
      # Create job directory
      JOB_DIR="/workspace/jobs/${jobName}"
      mkdir -p "$JOB_DIR"
      cd "$JOB_DIR"
      
      # Execute
      ${script}
    ''}
  '';
  
  # Cleanup job directory in container
  cleanupJob = { jobName }: ''
    docker exec "$CONTAINER_ID_OCI_${sanitize(image)}" \
      bash -c "rm -rf /workspace/jobs/${jobName}"
  '';
  
  provision = null;
}
```

**Key features:**
- ✅ One long-running container per executor
- ✅ Artifacts bind-mounted from host
- ✅ `/nix/store` read-only mount
- ✅ Job workspace inside container

---

#### K8s Executor

Executes jobs in Kubernetes pods.

```nix
executors.k8s :: {
  namespace :: String = "default",
  image :: String = "nixos/nix",
} -> Executor

# Implementation
{
  name = "k8s-${namespace}";
  
  # Create persistent pod
  setupWorkspace = ''
    POD_NAME="nixactions-$WORKFLOW_ID"
    export POD_NAME
    
    kubectl run "$POD_NAME" \
      --namespace=${namespace} \
      --image=${image} \
      --command -- sleep infinity
    
    kubectl wait --for=condition=Ready --timeout=60s \
      "pod/$POD_NAME" --namespace=${namespace}
    
    kubectl exec --namespace=${namespace} "$POD_NAME" -- \
      mkdir -p /workspace /artifacts
  '';
  
  # Delete pod
  cleanupWorkspace = ''
    kubectl delete pod "$POD_NAME" --namespace=${namespace} --ignore-not-found
  '';
  
  # Execute in pod
  executeJob = { jobName, script }: ''
    kubectl exec --namespace=${namespace} "$POD_NAME" -- bash -c ${escapeShellArg ''
      export NIXACTIONS_ARTIFACTS_DIR="/artifacts"
      JOB_DIR="/workspace/jobs/${jobName}"
      mkdir -p "$JOB_DIR"
      cd "$JOB_DIR"
      ${script}
    ''}
  '';
  
  cleanupJob = { jobName }: ''
    kubectl exec --namespace=${namespace} "$POD_NAME" -- \
      rm -rf "/workspace/jobs/${jobName}"
  '';
}
```

**Key features:**
- ✅ One pod per workflow
- ✅ Artifacts in pod (ephemeral)
- ✅ Namespace isolation

---

#### NixOS Container Executor

Executes jobs in systemd-nspawn containers.

```nix
executors.nixos-container :: Executor

{
  name = "nixos-container";
  
  setupWorkspace = ''
    WORKSPACE_DIR="/tmp/nixactions/$WORKFLOW_ID"
    mkdir -p "$WORKSPACE_DIR"
    export WORKSPACE_DIR
  '';
  
  cleanupWorkspace = ''
    if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
      rm -rf "$WORKSPACE_DIR"
    fi
  '';
  
  # Each job runs in ephemeral container with bind-mount
  executeJob = { jobName, script }: ''
    systemd-nspawn --ephemeral \
      --bind="$WORKSPACE_DIR:/workspace" \
      --chdir=/workspace \
      bash -c ${escapeShellArg ''
        export NIXACTIONS_ARTIFACTS_DIR="/workspace/artifacts"
        mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
        
        JOB_DIR="/workspace/jobs/${jobName}"
        mkdir -p "$JOB_DIR"
        cd "$JOB_DIR"
        ${script}
      ''}
  '';
  
  cleanupJob = { jobName }: ''
    rm -rf "$WORKSPACE_DIR/jobs/${jobName}"
  '';
}
```

**Key features:**
- ✅ Ephemeral containers (no cleanup needed)
- ✅ Workspace bind-mounted from host
- ✅ Full NixOS environment

---

## Implementation

### Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Workflow Execution (GitHub Actions Style)                       │
└─────────────────────────────────────────────────────────────────┘

1. SETUP PHASE
   ┌──────────────────────────────────────┐
   │ Generate WORKFLOW_ID                  │
   │ Set up status tracking               │
   │ Install cleanup traps                │
   └──────────────────────────────────────┘
               │
               ▼
   ┌──────────────────────────────────────┐
   │ Lazy Workspace Init                  │
   │ (per unique executor)                │
   │                                      │
   │ - Local:  /tmp/nixactions/$ID       │
   │ - SSH:    remote:/var/tmp/...       │
   │ - OCI:    docker create + start     │
   │ - K8s:    kubectl run pod           │
   └──────────────────────────────────────┘
               │
               ▼
2. EXECUTION PHASE (Level-by-Level DAG)
   ┌──────────────────────────────────────┐
   │ Level 0: Jobs with no dependencies   │
   ├──────────────────────────────────────┤
   │ ┌──────┐  ┌──────┐  ┌──────┐        │
   │ │ lint │  │ test │  │ scan │        │
   │ └───┬──┘  └───┬──┘  └───┬──┘        │
   │     └─────────┴─────────┘            │
   │     (run in parallel with &)         │
   │     wait for all to complete         │
   └──────────────────────────────────────┘
               │
               ▼
   ┌──────────────────────────────────────┐
   │ Level 1: needs=[level 0 jobs]        │
   ├──────────────────────────────────────┤
   │ ┌──────────┐                         │
   │ │  build   │                         │
   │ └────┬─────┘                         │
   │      │ executeJob:                   │
   │      │ 1. Create job dir             │
   │      │ 2. cd into job dir            │
   │      │ 3. export ARTIFACTS_DIR       │
   │      │ 4. run actions                │
   │      │ 5. cleanupJob (rm job dir)    │
   │      │                               │
   │      ▼                               │
   │   ✓ Job succeeded                    │
   └──────────────────────────────────────┘
               │
               ▼
   ┌──────────────────────────────────────┐
   │ Level 2: needs=[build]               │
   ├──────────────────────────────────────┤
   │ ┌───────┐  ┌────────┐               │
   │ │deploy │  │ notify │               │
   │ └───────┘  └────────┘               │
   │  (parallel execution)                │
   └──────────────────────────────────────┘
               │
               ▼
3. CLEANUP PHASE
   ┌──────────────────────────────────────┐
   │ cleanupWorkspace (all executors)     │
   │                                      │
   │ - Local:  rm -rf /tmp/nixactions/$ID│
   │ - SSH:    ssh rm -rf remote:...     │
   │ - OCI:    docker stop + rm          │
   │ - K8s:    kubectl delete pod        │
   │                                      │
   │ Artifacts PRESERVED:                 │
   │ $HOME/.cache/nixactions/$ID/artifacts│
   └──────────────────────────────────────┘
```

---

### Artifacts Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│ Artifacts: Explicit File Sharing Between Jobs                   │
└─────────────────────────────────────────────────────────────────┘

STORAGE LAYOUT:
┌──────────────────────────────────────────────────────────────┐
│ Host Machine                                                  │
├──────────────────────────────────────────────────────────────┤
│ Workspace (temporary, cleaned after each job):               │
│   /tmp/nixactions/$WORKFLOW_ID/                              │
│   ├── jobs/                                                  │
│   │   ├── build/    ← Created for job, DELETED after job    │
│   │   ├── test/     ← Created for job, DELETED after job    │
│   │   └── deploy/   ← Created for job, DELETED after job    │
│                                                              │
│ Artifacts (persistent, survives cleanup):                    │
│   $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/            │
│   ├── dist.tar.gz                                            │
│   ├── coverage.tar.gz                                        │
│   └── reports.tar.gz                                         │
└──────────────────────────────────────────────────────────────┘

LIFECYCLE:
┌─────────────┐
│ Job: build  │
├─────────────┤
│ 1. Create:  │
│    /tmp/.../jobs/build/                                      │
│                                                              │
│ 2. Execute: │
│    npm run build                                             │
│    → dist/ created in job dir                                │
│                                                              │
│ 3. Save:    │
│    saveArtifacts { name="dist"; paths=["dist/"]; }           │
│    → tar czf $ARTIFACTS_DIR/dist.tar.gz dist/                │
│                                                              │
│ 4. Cleanup: │
│    rm -rf /tmp/.../jobs/build/  ← dist/ DELETED             │
└─────────────┘
      │
      ▼ (artifacts survived!)
┌─────────────┐
│ Job: test   │
├─────────────┤
│ 1. Create:  │
│    /tmp/.../jobs/test/                                       │
│                                                              │
│ 2. Restore: │
│    restoreArtifacts { name="dist"; }                         │
│    → tar xzf $ARTIFACTS_DIR/dist.tar.gz                      │
│    → dist/ extracted to current dir                          │
│                                                              │
│ 3. Execute: │
│    npm test  ← uses restored dist/                           │
│                                                              │
│ 4. Cleanup: │
│    rm -rf /tmp/.../jobs/test/  ← dist/ DELETED again        │
└─────────────┘
      │
      ▼ (artifacts still alive!)
┌─────────────┐
│ Job: deploy │
├─────────────┤
│ 1. Restore: │
│    restoreArtifacts { name="dist"; }                         │
│    → dist/ available again                                   │
│                                                              │
│ 2. Execute: │
│    rsync dist/ server:/var/www/                             │
└─────────────┘

RESULT:
✅ No implicit file sharing (jobs can't accidentally depend on each other)
✅ Explicit data flow (saveArtifacts → restoreArtifacts)
✅ Clean workspaces (each job starts fresh)
✅ Artifacts survive workflow (for inspection/debugging)
```

---

### Multi-Executor Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Workflow with Multiple Executors                                │
└─────────────────────────────────────────────────────────────────┘

HOST MACHINE:
┌──────────────────────────────────────────────────────────────┐
│ Shared Artifacts Storage (all executors access this):        │
│   $HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/            │
│   ├── dist.tar.gz                                            │
│   └── coverage.tar.gz                                        │
└──────────────────────────────────────────────────────────────┘
     ▲                    ▲                    ▲
     │                    │                    │
┌────┴────┐         ┌─────┴─────┐       ┌─────┴──────┐
│ Local   │         │  OCI      │       │   SSH      │
│ Executor│         │  Executor │       │   Executor │
├─────────┤         ├───────────┤       ├────────────┤
│Workspace│         │ Container │       │   Remote   │
│/tmp/... │         │ + mount   │       │  Machine   │
│         │         │           │       │            │
│ job1/   │         │ /workspace│       │/var/tmp/...│
│ job2/   │         │ /artifacts│       │            │
│         │         │ (mounted) │       │  job3/     │
└─────────┘         └───────────┘       └────────────┘

EXECUTION:
job1 (local)     → saves artifacts to $HOME/.cache/.../artifacts/
job2 (oci)       → reads artifacts from /artifacts (mounted)
job3 (ssh)       → reads artifacts from $HOME/.cache/... (on remote)

KEY DESIGN:
- Each executor manages its own workspace
- Artifacts storage is SHARED (mounted/synced)
- Jobs explicitly save/restore artifacts
```

---

### Project Structure

```
nixactions/
├── flake.nix
├── lib/
│   ├── default.nix              # Main API
│   ├── mk-executor.nix          # mkExecutor
│   ├── mk-workflow.nix          # mkWorkflow (GitHub Actions style)
│   ├── executors/
│   │   ├── default.nix
│   │   ├── local.nix
│   │   ├── ssh.nix
│   │   ├── nixos-container.nix
│   │   ├── oci.nix
│   │   ├── k8s.nix
│   │   └── nomad.nix
│   ├── actions/
│   │   ├── default.nix          # All actions
│   │   ├── setup.nix            # Setup actions (node, python, rust)
│   │   ├── npm.nix              # NPM actions
│   │   ├── nix-shell.nix        # Dynamic package loading
│   │   ├── artifacts.nix        # Artifacts (save/restore)
│   │   ├── sops.nix             # SOPS secrets
│   │   ├── vault.nix            # HashiCorp Vault
│   │   ├── 1password.nix        # 1Password
│   │   ├── age.nix              # Age encryption
│   │   ├── bitwarden.nix        # Bitwarden
│   │   └── require-env.nix      # Env validation
│   └── utils/
│       └── default.nix
└── README.md
```

### `lib/mk-workflow.nix` (GitHub Actions Style)

```nix
{ pkgs, lib }:

{
  name,
  jobs,
}:

assert lib.assertMsg (name != "") "Workflow name cannot be empty";
assert lib.assertMsg (builtins.isAttrs jobs) "jobs must be an attribute set";

let
  # Calculate dependency depth for each job
  calcDepth = jobName: job:
    if (job.needs or []) == []
    then 0
    else 1 + lib.foldl' lib.max 0 (map (dep: calcDepth dep jobs.${dep}) job.needs);
  
  # Depths for all jobs
  depths = lib.mapAttrs (name: job: calcDepth name job) jobs;
  
  # Max depth
  maxDepth = lib.foldl' lib.max 0 (lib.attrValues depths);
  
  # Group jobs by level
  levels = lib.genList (level:
    lib.filterAttrs (name: job: depths.${name} == level) jobs
  ) (maxDepth + 1);
  
  # Extract deps from actions
  extractDeps = actions: 
    lib.unique (lib.concatMap (a: a.deps or []) actions);
  
  # Generate single job bash function
  generateJob = jobName: job:
    let
      executor = job.executor;
      allDeps = extractDeps job.actions;
      
      # Compose actions into single script
      actionsScript = lib.concatMapStringsSep "\n\n" (action:
        let
          pathSetup = lib.optionalString (action.deps or [] != []) ''
            export PATH=${lib.makeBinPath action.deps}:$PATH
          '';
          
          envSetup = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: 
              "export ${k}=${lib.escapeShellArg (toString v)}"
            ) (action.env or {})
          );
          
          wdSetup = lib.optionalString (action.workdir or null != null)
            "cd ${action.workdir}";
          
        in ''
          # === ${action.name or "action"} ===
          ${pathSetup}
          ${envSetup}
          ${wdSetup}
          ${action.bash}
        ''
      ) job.actions;
      
    in ''
      job_${jobName}() {
        echo "╔════════════════════════════════════════╗"
        echo "║ JOB: ${jobName}"
        echo "║ EXECUTOR: ${executor.name}"
        ${lib.optionalString ((job.if or "success()") != "success()") ''
          echo "║ CONDITION: ${job.if or "success()"}"
        ''}
        echo "╚════════════════════════════════════════╝"
        
        ${lib.optionalString (executor.canProvision && allDeps != []) ''
          echo "→ Provisioning ${toString (builtins.length allDeps)} derivations..."
          ${executor.provision allDeps}
        ''}
        
        ${lib.optionalString (executor.prepare != null) executor.prepare}
        
        ${executor.execute actionsScript}
        
        ${lib.optionalString (executor.cleanup != null) executor.cleanup}
      }
    '';

in pkgs.writeShellScript name ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # Job status tracking
  declare -A JOB_STATUS
  FAILED_JOBS=()
  WORKFLOW_CANCELLED=false
  
  # Trap cancellation
  trap 'WORKFLOW_CANCELLED=true; echo "⊘ Workflow cancelled"; exit 130' SIGINT SIGTERM
  
  # Check if condition is met
  check_condition() {
    local condition=$1
    
    case "$condition" in
      success\(\))
        if [ ''${#FAILED_JOBS[@]} -gt 0 ]; then
          return 1  # Has failures
        fi
        ;;
      failure\(\))
        if [ ''${#FAILED_JOBS[@]} -eq 0 ]; then
          return 1  # No failures
        fi
        ;;
      always\(\))
        return 0  # Always run
        ;;
      cancelled\(\))
        if [ "$WORKFLOW_CANCELLED" = "false" ]; then
          return 1
        fi
        ;;
      *)
        echo "Unknown condition: $condition"
        return 1
        ;;
    esac
    
    return 0
  }
  
  # Run single job with condition check
  run_job() {
    local job_name=$1
    local condition=''${2:-success()}
    local continue_on_error=''${3:-false}
    
    # Check condition
    if ! check_condition "$condition"; then
      echo "⊘ Skipping $job_name (condition not met: $condition)"
      JOB_STATUS[$job_name]="skipped"
      return 0
    fi
    
    # Execute job
    if job_$job_name; then
      echo "✓ Job $job_name succeeded"
      JOB_STATUS[$job_name]="success"
      return 0
    else
      local exit_code=$?
      echo "✗ Job $job_name failed (exit code: $exit_code)"
      FAILED_JOBS+=("$job_name")
      JOB_STATUS[$job_name]="failure"
      
      if [ "$continue_on_error" = "true" ]; then
        echo "→ Continuing despite failure (continueOnError: true)"
        return 0
      else
        return $exit_code
      fi
    fi
  }
  
  # Run jobs in parallel
  run_parallel() {
    local -a job_specs=("$@")
    local -a pids=()
    local failed=false
    
    # Start all jobs
    for spec in "''${job_specs[@]}"; do
      IFS='|' read -r job_name condition continue_on_error <<< "$spec"
      
      # Run in background
      (
        run_job "$job_name" "$condition" "$continue_on_error"
      ) &
      pids+=($!)
    done
    
    # Wait for all jobs
    for pid in "''${pids[@]}"; do
      if ! wait "$pid"; then
        failed=true
      fi
    done
    
    if [ "$failed" = "true" ]; then
      # Check if we should stop
      for spec in "''${job_specs[@]}"; do
        IFS='|' read -r job_name condition continue_on_error <<< "$spec"
        if [ "''${JOB_STATUS[$job_name]}" = "failure" ] && [ "$continue_on_error" != "true" ]; then
          echo "⊘ Stopping workflow due to job failure: $job_name"
          return 1
        fi
      done
    fi
    
    return 0
  }
  
  # Job functions
  ${lib.concatStringsSep "\n\n" 
    (lib.mapAttrsToList generateJob jobs)}
  
  # Main execution
  main() {
    echo "════════════════════════════════════════"
    echo " Workflow: ${name}"
    echo " Execution: GitHub Actions style (parallel)"
    echo " Levels: ${toString (maxDepth + 1)}"
    echo "════════════════════════════════════════"
    echo ""
    
    # Execute level by level
    ${lib.concatMapStringsSep "\n\n" (levelIdx:
      let
        level = lib.elemAt levels levelIdx;
        levelJobs = lib.attrNames level;
      in
        if levelJobs == [] then ""
        else ''
          echo "→ Level ${toString levelIdx}: ${lib.concatStringsSep ", " levelJobs}"
          
          # Build job specs (name|condition|continueOnError)
          run_parallel \
            ${lib.concatMapStringsSep " \\\n    " (jobName:
              let
                job = level.${jobName};
                condition = job.if or "success()";
                continueOnError = toString (job.continueOnError or false);
              in
                ''"${jobName}|${condition}|${continueOnError}"''
            ) levelJobs} || {
              echo "⊘ Level ${toString levelIdx} failed"
              exit 1
            }
          
          echo ""
        ''
    ) (lib.range 0 maxDepth)}
    
    # Final report
    echo "════════════════════════════════════════"
    if [ ''${#FAILED_JOBS[@]} -gt 0 ]; then
      echo "✗ Workflow failed"
      echo ""
      echo "Failed jobs:"
      printf '  - %s\n' "''${FAILED_JOBS[@]}"
      echo ""
      echo "Job statuses:"
      for job in ${lib.concatStringsSep " " (lib.attrNames jobs)}; do
        echo "  $job: ''${JOB_STATUS[$job]:-unknown}"
      done
      exit 1
    else
      echo "✓ Workflow completed successfully"
      echo ""
      echo "All jobs succeeded:"
      for job in ${lib.concatStringsSep " " (lib.attrNames jobs)}; do
        if [ "''${JOB_STATUS[$job]}" = "success" ]; then
          echo "  ✓ $job"
        elif [ "''${JOB_STATUS[$job]}" = "skipped" ]; then
          echo "  ⊘ $job (skipped)"
        fi
      done
    fi
    echo "════════════════════════════════════════"
  }
  
  main "$@"
''
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
      packages.${system}.ci = import ./ci.nix { 
        inherit pkgs platform; 
      };
    };
}
```

#### 2. Create workflow (GitHub Actions style)

```nix
# ci.nix
{ pkgs, platform }:

platform.mkWorkflow {
  name = "ci";
  
  jobs = {
    # Level 0 - parallel
    lint = {
      executor = platform.executors.local;
      actions = [
        platform.actions.checkout
        (platform.actions.setupNode {})
        { bash = "npm run lint"; }
      ];
    };
    
    # Level 1 - after lint
    test = {
      needs = [ "lint" ];
      executor = platform.executors.nixos-container;
      actions = [
        platform.actions.npmTest
      ];
    };
    
    # Level 2 - after test
    build = {
      needs = [ "test" ];
      actions = [
        platform.actions.npmBuild
      ];
    };
  };
}
```

#### 3. Run

```bash
# Local
$ nix run .#ci

# Remote
$ nix build .#ci
$ ssh server < result
```

---

### Complete Example (GitHub Actions Style)

```nix
# ci.nix
{ pkgs, platform }:

let
  # Build application
  app = pkgs.buildNpmPackage {
    pname = "my-app";
    version = "1.0.0";
    src = ./.;
    npmDepsHash = "sha256-...";
  };
  
  # Custom executors
  builder = platform.executors.ssh {
    host = "build-01.internal";
    user = "ci";
  };

in platform.mkWorkflow {
  name = "production-ci";
  
  jobs = {
    # === Level 0: Parallel checks ===
    
    lint-js = {
      executor = platform.executors.local;
      actions = [{
        deps = [ pkgs.nodejs ];
        bash = "eslint src/**/*.js";
      }];
    };
    
    lint-css = {
      executor = platform.executors.local;
      actions = [{
        deps = [ pkgs.nodejs ];
        bash = "stylelint src/**/*.css";
      }];
    };
    
    security-scan = {
      executor = platform.executors.local;
      actions = [{
        deps = [ pkgs.nodejs ];
        bash = "npm audit";
      }];
      continueOnError = true;  # Don't stop workflow
    };
    
    # === Level 1: Tests (after lints) ===
    
    test-unit = {
      needs = [ "lint-js" "lint-css" ];
      executor = platform.executors.nixos-container;
      actions = [
        platform.actions.npmInstall
        {
          bash = "npm run test:unit";
        }
      ];
    };
    
    test-integration = {
      needs = [ "lint-js" "lint-css" ];
      executor = platform.executors.nixos-container;
      actions = [
        platform.actions.npmInstall
        {
          bash = "npm run test:integration";
        }
      ];
    };
    
    # === Level 2: Build (after tests) ===
    
    build = {
      needs = [ "test-unit" "test-integration" ];
      executor = builder;
      actions = [{
        bash = ''
          echo "Building application: ${app}"
          echo "Version: ${app.version}"
        '';
      }];
    };
    
    # === Level 3: Deploy (after build) ===
    
    deploy = {
      needs = [ "build" ];
      # Only if all previous succeeded
      if = "success()";
      
      executor = platform.executors.k8s {
        namespace = "production";
      };
      
      actions = [{
        deps = [ pkgs.kubectl ];
        bash = ''
          kubectl set image deployment/my-app \
            app=${app}
          kubectl rollout status deployment/my-app
        '';
      }];
    };
    
    # === Level 3: Notifications (parallel with deploy) ===
    
    notify-success = {
      needs = [ "build" ];
      if = "success()";
      
      executor = platform.executors.local;
      actions = [{
        deps = [ pkgs.curl ];
        bash = ''
          curl -X POST $SLACK_WEBHOOK \
            -H 'Content-Type: application/json' \
            -d '{"text": "✅ CI passed - deploying to production"}'
        '';
      }];
    };
    
    notify-failure = {
      needs = [ "build" ];
      if = "failure()";
      
      executor = platform.executors.local;
      actions = [{
        deps = [ pkgs.curl ];
        bash = ''
          curl -X POST $SLACK_WEBHOOK \
            -H 'Content-Type: application/json' \
            -d '{"text": "❌ CI failed - check logs"}'
        '';
      }];
    };
    
    # Always runs (cleanup)
    cleanup = {
      needs = [ "deploy" "notify-success" "notify-failure" ];
      if = "always()";
      
      executor = platform.executors.local;
      actions = [{
        bash = ''
          echo "Cleaning up temporary files..."
          rm -rf /tmp/ci-*
        '';
      }];
    };
  };
}
```

**Execution visualization:**

```
Level 0 (parallel):
  ├─ lint-js ───────┤
  ├─ lint-css ──────┤
  └─ security-scan ─┤

Level 1 (parallel, after level 0):
                    ├─ test-unit ────────┤
                    └─ test-integration ─┤

Level 2 (after level 1):
                                         ├─ build ────┤

Level 3 (parallel, after level 2):
                                                      ├─ deploy ────────┤
                                                      ├─ notify-success ─┤
                                                      └─ notify-failure ─┤

Level 4 (always runs):
                                                                         ├─ cleanup ─┤
```

---

### Output Example

```bash
$ nix run .#ci

════════════════════════════════════════
 Workflow: production-ci
 Execution: GitHub Actions style (parallel)
 Levels: 5
════════════════════════════════════════

→ Level 0: lint-js, lint-css, security-scan

╔════════════════════════════════════════╗
║ JOB: lint-js
║ EXECUTOR: local
╚════════════════════════════════════════╝
→ Running ESLint...
✓ Job lint-js succeeded

╔════════════════════════════════════════╗
║ JOB: lint-css
║ EXECUTOR: local
╚════════════════════════════════════════╝
→ Running Stylelint...
✓ Job lint-css succeeded

╔════════════════════════════════════════╗
║ JOB: security-scan
║ EXECUTOR: local
╚════════════════════════════════════════╝
→ Running security audit...
✗ Job security-scan failed (exit code: 1)
→ Continuing despite failure (continueOnError: true)

→ Level 1: test-unit, test-integration

╔════════════════════════════════════════╗
║ JOB: test-unit
║ EXECUTOR: nixos-container
╚════════════════════════════════════════╝
→ Running unit tests...
✓ Job test-unit succeeded

╔════════════════════════════════════════╗
║ JOB: test-integration
║ EXECUTOR: nixos-container
╚════════════════════════════════════════╝
→ Running integration tests...
✓ Job test-integration succeeded

→ Level 2: build

╔════════════════════════════════════════╗
║ JOB: build
║ EXECUTOR: ssh-build-01.internal
╚════════════════════════════════════════╝
→ Provisioning 1 derivations...
→ Building application...
Building application: /nix/store/xxx-my-app
Version: 1.0.0
✓ Job build succeeded

→ Level 3: deploy, notify-success, notify-failure

╔════════════════════════════════════════╗
║ JOB: deploy
║ EXECUTOR: k8s-production
║ CONDITION: success()
╚════════════════════════════════════════╝
→ Deploying to Kubernetes...
deployment.apps/my-app image updated
Waiting for deployment "my-app" rollout to finish...
deployment "my-app" successfully rolled out
✓ Job deploy succeeded

╔════════════════════════════════════════╗
║ JOB: notify-success
║ EXECUTOR: local
║ CONDITION: success()
╚════════════════════════════════════════╝
→ Sending notification...
✓ Job notify-success succeeded

╔════════════════════════════════════════╗
║ JOB: notify-failure
║ EXECUTOR: local
║ CONDITION: failure()
╚════════════════════════════════════════╝
⊘ Skipping notify-failure (condition not met: failure())

→ Level 4: cleanup

╔════════════════════════════════════════╗
║ JOB: cleanup
║ EXECUTOR: local
║ CONDITION: always()
╚════════════════════════════════════════╝
→ Cleaning up...
Cleaning up temporary files...
✓ Job cleanup succeeded

════════════════════════════════════════
✓ Workflow completed successfully

All jobs succeeded:
  ✓ lint-js
  ✓ lint-css
  ✓ test-unit
  ✓ test-integration
  ✓ build
  ✓ deploy
  ✓ notify-success
  ⊘ notify-failure (skipped)
  ✓ cleanup
════════════════════════════════════════
```

---

## Comparison

### vs GitHub Actions

| Feature | GitHub Actions | NixActions |
|---------|---------------|------------|
| **Execution model** | Parallel + needs | ✅ Same |
| **Dependencies** | `needs: [...]` | ✅ Same |
| **Conditions** | `if: success()` etc | ✅ Same |
| **Continue on error** | `continue-on-error` | ✅ Same (`continueOnError`) |
| **Infrastructure** | GitHub.com | ✅ None (agentless) |
| **Agents** | Runners | ✅ None |
| **Local execution** | `act` (hacky) | ✅ Native `nix run` |
| **Reproducibility** | ❌ Variable | ✅ Guaranteed (Nix) |
| **Type safety** | ❌ YAML | ✅ Nix |
| **Cost** | $21/month | ✅ $0 |

### vs GitLab CI

| Feature | GitLab CI | NixActions |
|---------|----------|------------|
| **Execution** | Sequential by default | ✅ Parallel (like GH Actions) |
| **Stages** | Explicit phases | ✅ Implicit (via needs) |
| **Dependencies** | `needs:` | ✅ Same |
| **Infrastructure** | GitLab instance | ✅ None |
| **Local testing** | Limited | ✅ Native |

### vs Ansible

| Feature | Ansible | NixActions |
|---------|---------|------------|
| **Model** | Agentless ✅ | ✅ Agentless |
| **Execution** | Sequential | ✅ Parallel |
| **Type safety** | ❌ YAML | ✅ Nix |
| **Use case** | Config mgmt | ✅ CI/CD |

---

## Roadmap

### Phase 1: MVP (Week 1-2) ✅

**GitHub Actions execution model:**
- ✅ Parallel execution by default
- ✅ Level-based ordering
- ✅ `needs` dependencies
- ✅ `if` conditions (success/failure/always)
- ✅ `continueOnError`
- ✅ Local executor
- ✅ Basic actions library

**Environment & Secrets:**
- ✅ Environment variables (workflow/job/action level)
- ✅ Runtime env override
- ✅ SOPS action
- ✅ `requireEnv` validator

### Phase 2: Remote Executors (Week 3-4) ✅

- ✅ SSH executor with provisioning
- ✅ OCI executor
- ✅ NixOS container executor
- ✅ Executor-owned workspaces
- ✅ Artifacts (save/restore)
- ✅ Per-job cleanup

**Secrets:**
- ✅ Vault action
- ✅ 1Password action
- ✅ Age action
- ✅ Bitwarden action

**Package Management:**
- ✅ nixShell action (dynamic packages)

### Phase 3: Advanced (Week 5-6) ✅

- ✅ K8s executor
- ✅ Nomad executor
- ⏳ Smart provisioning
- ⏳ Binary cache
- ⏳ Artifacts storage backends (S3, HTTP)

### Phase 4: Ecosystem (Week 7-8)

- Extended actions
- Templates
- Documentation
- Examples

### Phase 5: Production (Week 9-12)

- ⏳ Secrets masking in logs
- ⏳ Audit logging  
- ⏳ Monitoring
- ⏳ Web UI (optional)
- ⏳ Matrix builds
- ⏳ Workflow caching
- ⏳ Artifacts auto-cleanup (age-based)

---

## Summary

**NixActions v3.0 = GitHub Actions execution + Nix reproducibility + Agentless**

**Key features:**
- ✅ Parallel execution by default (GitHub Actions style)
- ✅ Explicit dependencies via `needs`
- ✅ Conditional execution (`if: success/failure/always`)
- ✅ Continue on error
- ✅ Level-based DAG execution
- ✅ Self-contained (Nix)
- ✅ Agentless (SSH/containers/local)
- ✅ Type-safe (Nix, not YAML)
- ✅ Local-first development
- ✅ Artifacts management (explicit file sharing)
- ✅ Executor-owned workspaces
- ✅ Per-job cleanup (no implicit coupling)
- ✅ 6 executors (local/SSH/OCI/K8s/Nomad/NixOS-container)
- ✅ Dynamic package loading (nixShell)

**Positioning:**
> "GitHub Actions execution model + Nix reproducibility + Agentless deployment = NixActions"

**This is the final design!** 🎯