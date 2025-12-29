# NixActions Documentation

> **GitHub Actions execution model + Nix reproducibility + Agentless deployment**

NixActions compiles workflows into self-contained executables that run anywhere without agents or central infrastructure. Actions are Nix derivations, provisioned at build-time.

---

## Quick Navigation

### Getting Started

| Document | Description |
|----------|-------------|
| [User Guide](./user-guide.md) | Quick start, installation, first workflow |
| [Philosophy](./philosophy.md) | Why NixActions, core principles |

### Core Concepts

| Document | Description |
|----------|-------------|
| [Architecture](./architecture.md) | Layered design, system overview |
| [Core Contracts](./core-contracts.md) | Action, Executor, Job, Workflow contracts |
| [Execution Model](./execution-model.md) | Level-based parallel execution, DAG |

### Features

| Document | Description |
|----------|-------------|
| [Actions](./actions.md) | Actions as Derivations, `mkAction`, build-time compilation |
| [Executors](./executors.md) | Local, OCI, SSH, K8s executors, deduplication |
| [Conditions](./conditions.md) | `success()`, `failure()`, `always()`, bash conditions |
| [Retry](./retry.md) | Retry mechanism, backoff strategies |
| [Environment](./environment.md) | Env providers, secrets, multi-level config |
| [Artifacts](./artifacts.md) | `inputs`/`outputs`, custom restore paths |

### Reference

| Document | Description |
|----------|-------------|
| [API Reference](./api-reference.md) | `mkWorkflow`, `mkExecutor`, `mkAction`, full API |
| [Comparison](./comparison.md) | vs GitHub Actions, GitLab CI |
| [Roadmap](./roadmap.md) | Current status, planned features |

---

## How It Works

```
Nix Code                    Compiled Workflow           Execution
==========                  =================           =========

nixactions.mkWorkflow {       #!/usr/bin/env bash         $ nix run .#ci
  jobs = {                  
    test = {                setup_workspace()           -> Setting up workspace
      steps = [           job_test()                  -> Running job: test
        { bash = "..." }      /nix/store/xxx/bin/test   -> Action: test
      ];                    job_build()                 -> Running job: build
    };                        /nix/store/yyy/bin/build  -> Action: build
    build = { ... };        cleanup()                   -> Cleanup
  };                        
}                                                       All jobs succeeded!
```

### Key Concepts

**Actions are Derivations** - Every action compiles to a `/nix/store` path. Build-time validation, caching, and reproducibility come for free.

**Executors define where** - Local machine, Docker containers, SSH remotes, or Kubernetes pods. Same workflow, different execution environments.

**Jobs are parallel by default** - Like GitHub Actions, jobs without dependencies run in parallel. Use `needs` for explicit ordering.

**Conditions control flow** - Built-in conditions (`success()`, `failure()`, `always()`) and bash scripts for custom logic.

---

## Minimal Example

```nix
# ci.nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "ci";
  
  jobs = {
    test = {
      executor = nixactions.executors.local;
      steps = [
        { bash = "npm test"; }
      ];
    };
    
    build = {
      needs = [ "test" ];
      executor = nixactions.executors.local;
      steps = [
        { bash = "npm run build"; }
      ];
    };
  };
}
```

```bash
# Run locally
$ nix run .#ci

# Or on remote
$ nix build .#ci && ssh server < result
```

---

## Architecture Overview

```
+-----------------------------------------+
| Level 5: User Abstractions              |
|   Custom helpers, presets, wrappers     |
+-----------------------------------------+
                  |
+-----------------------------------------+
| Level 4: Workflow (DAG of jobs)         |
|   mkWorkflow { name, jobs }             |
+-----------------------------------------+
                  |
+-----------------------------------------+
| Level 3: Job (actions + executor)       |
|   { executor, actions, needs }          |
+-----------------------------------------+
                  |
+-----------------------------------------+
| Level 2: Executor (where to run)        |
|   local, oci, ssh, k8s                  |
+-----------------------------------------+
                  |
+-----------------------------------------+
| Level 1: Action = Derivation            |
|   /nix/store/xxx-action-name            |
+-----------------------------------------+
                  |
+-----------------------------------------+
| Level 0: Nix Store                      |
|   Content-addressed, cached, hermetic   |
+-----------------------------------------+
```

---

## Feature Highlights

### Parallel Execution

```nix
jobs = {
  lint = { ... };     # Level 0 - runs immediately
  test = { ... };     # Level 0 - runs in parallel with lint
  build = {
    needs = [ "lint" "test" ];  # Level 1 - waits for both
    ...
  };
};
```

### Conditional Execution

```nix
# Built-in conditions
condition = "success()";   # Run if deps succeeded (default)
condition = "failure()";   # Run if any dep failed
condition = "always()";    # Always run

# Bash conditions
condition = ''[ "$BRANCH" = "main" ]'';
condition = ''[ -f package.json ]'';
```

### Multiple Executors

```nix
jobs = {
  test = {
    executor = nixactions.executors.local;
    ...
  };
  
  build = {
    executor = nixactions.executors.oci { 
      extraPackages = [ pkgs.nodejs ]; 
    };
    ...
  };
};
```

### Artifacts

```nix
jobs = {
  build = {
    outputs = { dist = "dist/"; };
    ...
  };
  
  deploy = {
    needs = [ "build" ];
    inputs = [ "dist" ];
    ...
  };
};
```

### Retry Mechanism

```nix
{
  retry = {
    max_attempts = 3;
    backoff = "exponential";
    min_time = 1;
    max_time = 60;
  };
}
```

---

## Project Structure

```
nixactions/
+-- lib/
|   +-- mk-workflow.nix      # Workflow compiler
|   +-- mk-executor.nix      # Executor contract
|   +-- executors/           # local, oci, ssh, k8s
|   +-- actions/             # Standard actions library
|   +-- env-providers/       # file, sops, vault, etc.
+-- examples/
|   +-- 01-basic/            # Simple workflows
|   +-- 02-features/         # Advanced features
|   +-- 03-real-world/       # Production pipelines
+-- docs/                    # This documentation
```

---

## Next Steps

1. **[User Guide](./user-guide.md)** - Get started with your first workflow
2. **[Actions](./actions.md)** - Understand how actions work
3. **[Executors](./executors.md)** - Learn about execution environments
4. **[API Reference](./api-reference.md)** - Full API documentation
