<div align="center">

# NixActions

**Agentless CI/CD Platform Powered by Nix**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nix](https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![GitHub Actions Style](https://img.shields.io/badge/Execution-GitHub%20Actions%20Style-2088FF.svg)](https://docs.github.com/en/actions)

*GitHub Actions execution model + Nix reproducibility + Agentless deployment*

[Features](#features) • [Quick Start](#quick-start) • [Examples](#examples) • [Documentation](#documentation)

</div>

---

## Features

✅ **GitHub Actions-style execution** - Parallel by default, explicit dependencies via `needs`  
✅ **Deterministic builds** - Nix guarantees reproducibility  
✅ **Agentless** - No infrastructure needed, run anywhere (SSH/containers/local)  
✅ **Type-safe** - Nix DSL instead of YAML  
✅ **Local-first** - Test workflows locally before deploying  
✅ **Composable** - Everything is a function  

## Quick Start

### 1. Add to your project

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

### 2. Create a workflow

```nix
# ci.nix
{ pkgs, platform }:

platform.mkWorkflow {
  name = "ci";
  
  jobs = {
    # Runs immediately (Level 0)
    lint = {
      executor = platform.executors.local;
      actions = [
        { bash = "npm run lint"; }
      ];
    };
    
    # Runs after lint succeeds (Level 1)
    test = {
      needs = [ "lint" ];
      executor = platform.executors.local;
      actions = [
        { bash = "npm test"; }
      ];
    };
    
    # Runs after test succeeds (Level 2)
    build = {
      needs = [ "test" ];
      actions = [
        { bash = "npm run build"; }
      ];
    };
  };
}
```

### 3. Run it

```bash
# Local execution
$ nix run .#ci

# Remote execution (SSH)
$ nix build .#ci
$ ssh server < result
```

## Examples

Examples are organized into categories:

### 01-basic/ - Core Concepts

**simple.nix** - Most basic workflow
```bash
$ nix run .#example-simple
```
Single job with basic actions (checkout, greet, system-info).

**parallel.nix** - Parallel execution with dependencies
```bash
$ nix run .#example-parallel
```
Jobs running in parallel (Level 0), sequential dependencies via `needs`, multi-level DAG execution.

**env-sharing.nix** - Environment variable sharing between actions
```bash
$ nix run .#example-env-sharing
```
Actions writing to `$JOB_ENV`, variable persistence across actions, multi-step calculations.

---

### 02-features/ - Advanced Features

**artifacts.nix** / **artifacts-paths.nix** - Artifact passing between jobs
```bash
$ nix run .#example-artifacts
$ nix run .#example-artifacts-paths
```
`outputs` to save artifacts, `inputs` to restore, custom restore paths, directory artifacts.

**retry.nix** - Automatic retry on failures
```bash
$ nix run .#example-retry
```
Three backoff strategies (exponential, linear, constant), configurable delays, retry at workflow/job/action levels.

**secrets.nix** - Secrets management with env-providers
```bash
$ nix run .#example-secrets
```
Multiple providers (SOPS, file, static, required), environment precedence, runtime override.

**nix-shell.nix** - Dynamic package loading
```bash
$ nix run .#example-nix-shell
```
Add packages on-the-fly with `platform.actions.nixShell`, no executor modification needed.

**matrix-builds.nix** - Compile-time matrix job generation
```bash
$ nix run .#example-matrix-builds
```
`platform.mkMatrixJobs` for cross-platform testing, multi-version testing, auto-generated job names.

**structured-logging.nix** - Log formats for observability
```bash
$ nix run .#example-structured-logging
```
Three formats: structured (default), JSON, simple. Duration tracking, exit code reporting.

**test-action-conditions.nix** - Action-level conditions
```bash
$ nix run .#example-test-action-conditions
```
`success()`, `failure()`, `always()` conditions, bash script conditions, `continue-on-error`.

**multi-executor.nix** - Multiple executors in one workflow
```bash
$ nix run .#example-multi-executor
```
Different jobs using different executors, executor-specific configuration.

**test-env.nix** / **test-isolation.nix** - Testing environment behavior
```bash
$ nix run .#example-test-env
$ nix run .#example-test-isolation
```
Environment propagation, job isolation, workspace isolation.

---

### 03-real-world/ - Production Pipelines

**complete.nix** - Full-featured CI/CD pipeline
```bash
$ nix run .#example-complete
```
Complete workflow: parallel validation → testing → building → conditional deployment → notifications → cleanup.

**python-ci.nix** / **python-ci-simple.nix** - Python CI/CD
```bash
$ nix run .#example-python-ci
$ nix run .#example-python-ci-simple
```
Real Python project: pytest, flake8, mypy, coverage, Docker building, deployment.

**nodejs-full-pipeline.nix** - Node.js CI/CD with OCI executor
```bash
$ nix run .#example-nodejs-full-pipeline
```
Full Node.js pipeline in containers: lint → test → build → artifacts.

**buildah-pipeline.nix** / **buildah-multi-image.nix** - Container image building
```bash
$ nix run .#example-buildah-pipeline
$ nix run .#example-buildah-multi-image
```
Build OCI images with Buildah (no Docker daemon), multi-arch builds.

---

### Comprehensive Test Suites

```bash
# Retry mechanism (10 test jobs)
$ nix run .#test-retry-comprehensive

# Action conditions (10 test jobs)  
$ nix run .#test-conditions-comprehensive
```

## Core Concepts

### Executors

Executors define **where** code runs:

```nix
# Local machine (default)
executor = platform.executors.local

# Local with options
executor = platform.executors.local { 
  copyRepo = false;  # Don't copy repository to job directory
  name = "build-env";  # Custom name for isolated workspace
}

# Docker container
executor = platform.executors.oci { 
  image = "node:20";
  copyRepo = true;   # Copy repo to job directory (default)
}

# Custom executor name (creates separate workspace)
executor = platform.executors.oci { 
  image = "nixos/nix"; 
  name = "test-env";  # Custom name
}
```

Available executors:
- `local` - Current machine with isolated job directories
- `oci` - Docker/OCI containers with volume mounts

Planned executors:
- `ssh` - Remote via SSH with nix-copy-closure
- `k8s` - Kubernetes pods
- `nixos-container` - systemd-nspawn
- `nomad` - Nomad jobs

**Executor Architecture:**
- Workspace-level hooks (`setupWorkspace`, `cleanupWorkspace`) - called once per unique executor
- Job-level hooks (`setupJob`, `executeJob`, `cleanupJob`) - called per job
- Jobs with same executor share workspace but get isolated directories

### Actions

Actions define **what** to do:

```nix
{
  name = "test";
  deps = [ pkgs.nodejs ];  # Nix packages for PATH
  bash = "npm test";       # Script to run
}
```

Standard actions library:

```nix
# Setup actions
platform.actions.checkout
platform.actions.setupNode { version = "20"; }
platform.actions.setupPython { version = "3.11"; }
platform.actions.setupRust

# Dynamic package loading
platform.actions.nixShell [ "curl" "jq" "git" ]

# NPM actions
platform.actions.npmInstall
platform.actions.npmTest
platform.actions.npmBuild
platform.actions.npmLint
```

#### Dynamic Package Loading with nixShell

The `nixShell` action allows you to dynamically add any Nix package to your job environment without modifying the executor:

```nix
{
  jobs = {
    api-test = {
      executor = platform.executors.local;
      actions = [
        # Add packages on-the-fly
        (platform.actions.nixShell [ "curl" "jq" ])
        
        # Use them in subsequent actions
        {
          bash = ''
            curl -s https://api.github.com/rate_limit | jq '.rate'
          '';
        }
      ];
    };
    
    # Different tools in different jobs
    file-processing = {
      executor = platform.executors.local;
      actions = [
        (platform.actions.nixShell [ "ripgrep" "fd" "bat" ])
        {
          bash = "fd -e nix -x rg -l 'TODO'";
        }
      ];
    };
  };
}
```

Benefits:
- **No executor modification needed** - Add packages per-job
- **Reproducible** - Packages come from nixpkgs
- **Scoped** - Packages only available in that job
- **Composable** - Can call multiple times in same job

See `examples/nix-shell.nix` for more examples.

### Secrets Management

```nix
{
  actions = [
    # Load from SOPS
    (platform.actions.sopsLoad {
      file = ./secrets.sops.yaml;
    })
    
    # Validate required vars
    (platform.actions.requireEnv [ 
      "API_KEY" 
      "DB_PASSWORD" 
    ])
    
    # Use secrets
    { 
      bash = ''
        kubectl create secret generic app \
          --from-literal=api-key="$API_KEY"
      ''; 
    }
  ];
}
```

Supported secrets managers:
- **SOPS** (recommended) - `platform.actions.sopsLoad`
- **HashiCorp Vault** - `platform.actions.vaultLoad`
- **1Password** - `platform.actions.opLoad`
- **Age** - `platform.actions.ageDecrypt`
- **Bitwarden** - `platform.actions.bwLoad`

### Environment Variables

Variables can be set at three levels (with precedence):

```nix
platform.mkWorkflow {
  # Workflow level (lowest priority)
  env = {
    PROJECT = "myapp";
  };
  
  jobs = {
    deploy = {
      # Job level (medium priority)
      env = {
        ENVIRONMENT = "production";
      };
      
      actions = [
        {
          # Action level (highest priority)
          env = {
            LOG_LEVEL = "debug";
          };
          bash = "deploy.sh";
        }
      ];
    };
  };
}
```

Runtime override (highest priority):
```bash
$ API_KEY=xyz123 nix run .#deploy
```

### GitHub Actions-Style Execution

#### Parallel by Default

Jobs without dependencies run in parallel:

```nix
jobs = {
  lint-js = { ... };    # Level 0
  lint-css = { ... };   # Level 0 (parallel with lint-js)
  test = {              # Level 1 (after both lints)
    needs = [ "lint-js" "lint-css" ];
    ...
  };
}
```

#### Conditional Execution

NixActions uses `condition` (not `if`) for unified semantics at both job and action levels:

```nix
# Built-in conditions (workflow-aware)
{
  condition = "success()";    # Default - run if all deps succeeded
  condition = "failure()";    # Run if any dep failed
  condition = "always()";     # Always run (notifications, cleanup)
  condition = "cancelled()";  # Run if workflow cancelled
}

# Bash script conditions (full power)
{
  condition = ''[ "$BRANCH" = "main" ]'';           # Environment check
  condition = ''[ -f package.json ]'';              # File check
  condition = ''git diff --quiet main..HEAD'';      # Git condition
  condition = ''[ "$CI" = "true" ] && test -n "$API_KEY"'';  # Combined
}
```

Example:

```nix
jobs = {
  test = { ... };
  
  # Only runs if test succeeded (default)
  deploy = {
    needs = [ "test" ];
    condition = "success()";
    ...
  };
  
  # Only runs if test failed
  rollback = {
    needs = [ "test" ];
    condition = "failure()";
    ...
  };
  
  # Always runs (cleanup, notifications)
  notify = {
    needs = [ "test" ];
    condition = "always()";
    ...
  };
  
  # Only on main branch
  deploy-prod = {
    needs = [ "test" ];
    condition = ''[ "$BRANCH" = "main" ]'';
    ...
  };
}
```

#### Action-level Conditions

```nix
actions = [
  { bash = "npm test"; }
  
  # Only deploy on main branch
  {
    name = "deploy";
    condition = ''[ "$BRANCH" = "main" ]'';
    bash = "deploy.sh";
  }
  
  # Always notify
  {
    name = "notify";
    condition = "always()";
    bash = "curl -X POST $WEBHOOK";
  }
];
```

#### Continue on Error

```nix
{
  continueOnError = true;  # Don't stop workflow if this job fails
  ...
}
```

## Project Structure

```
nixactions/
├── flake.nix              # Nix flake entry point
├── lib/
│   ├── default.nix        # Main API export
│   ├── mk-executor.nix    # Executor contract (5-hook model)
│   ├── mk-workflow.nix    # Workflow compiler
│   ├── mk-matrix-jobs.nix # Matrix job generator
│   ├── retry.nix          # Retry mechanism
│   ├── timeout.nix        # Timeout handling
│   ├── logging.nix        # Structured logging
│   ├── runtime-helpers.nix # Runtime bash helpers
│   ├── executors/         # Built-in executors
│   │   ├── local.nix      # Local machine
│   │   ├── oci.nix        # Docker/OCI containers
│   │   ├── action-runner.nix  # Action execution engine
│   │   ├── local-helpers.nix  # Local executor bash functions
│   │   └── oci-helpers.nix    # OCI executor bash functions
│   ├── actions/           # Standard actions
│   │   ├── checkout.nix   # Repository checkout
│   │   ├── nix-shell.nix  # Dynamic package loading
│   │   ├── npm.nix        # NPM actions
│   │   └── setup.nix      # Setup actions
│   ├── env-providers/     # Environment variable providers
│   │   ├── file.nix       # .env file loading
│   │   ├── sops.nix       # SOPS encrypted files
│   │   ├── static.nix     # Hardcoded values
│   │   └── required.nix   # Validation
│   └── jobs/              # Pre-built job templates
│       └── buildah-build-push.nix  # OCI image building
└── examples/              # Working examples (30+)
    ├── 01-basic/          # Core concepts
    ├── 02-features/       # Advanced features
    ├── 03-real-world/     # Production pipelines
    └── 99-untested/       # Reference examples
```

## API Reference

### Platform API

```nix
platform :: {
  # Core constructors
  mkExecutor   :: ExecutorConfig -> Executor,
  mkWorkflow   :: WorkflowConfig -> Derivation,
  mkMatrixJobs :: MatrixConfig -> AttrSet Job,
  
  # Built-in executors
  executors :: {
    local :: { copyRepo? :: Bool, name? :: String } -> Executor,
    oci   :: { image :: String, copyRepo? :: Bool, name? :: String } -> Executor,
  },
  
  # Standard actions
  actions :: {
    # Setup actions
    checkout     :: Action,
    setupNode    :: { version :: String } -> Action,
    setupPython  :: { version :: String } -> Action,
    
    # Package management
    nixShell     :: [String] -> Action,
    
    # NPM actions
    npmInstall   :: Action,
    npmTest      :: Action,
    npmBuild     :: Action,
    npmLint      :: Action,
  },
  
  # Environment providers
  envProviders :: {
    file     :: { path :: String, required? :: Bool } -> Derivation,
    sops     :: { file :: Path, format? :: String, required? :: Bool } -> Derivation,
    static   :: AttrSet String -> Derivation,
    required :: [String] -> Derivation,
  },
  
  # Pre-built jobs
  jobs :: {
    buildahBuildPush :: { ... } -> Job,
  },
}
```

### Workflow Config

```nix
{
  name :: String,
  jobs :: AttrSet Job,
  env  :: AttrSet String = {},
}
```

### Job Config

```nix
{
  executor        :: Executor,
  actions         :: [Action],
  needs           :: [String] = [],
  condition       :: Condition = "success()",  # success() | failure() | always() | cancelled() | BashScript
  continueOnError :: Bool = false,
  env             :: AttrSet String = {},
  envFrom         :: [Derivation] = [],        # Environment providers
  inputs          :: [String | { name, path }] = [],  # Artifacts to restore
  outputs         :: AttrSet String = {},             # Artifacts to save
  retry           :: RetryConfig | Null = null,
  timeout         :: Int | Null = null,        # Seconds
}
```

### Action Config

```nix
{
  name      :: String = "action",
  bash      :: String,
  deps      :: [Derivation] = [],
  env       :: AttrSet String = {},
  workdir   :: Path | Null = null,
  condition :: Condition | Null = null,  # Action-level condition
  retry     :: RetryConfig | Null = null,
  timeout   :: Int | Null = null,
}
```

### Retry Config

```nix
{
  max_attempts :: Int = 1,           # Total attempts (1 = no retry)
  backoff      :: "exponential" | "linear" | "constant" = "exponential",
  min_time     :: Int = 1,           # Minimum delay (seconds)
  max_time     :: Int = 60,          # Maximum delay (seconds)
}
```

## Comparison

### vs GitHub Actions

| Feature | GitHub Actions | NixActions |
|---------|---------------|------------|
| Execution model | Parallel + needs | ✅ Same |
| Dependencies | `needs: [...]` | ✅ Same |
| Conditions | `if: success()` | ✅ Same |
| Infrastructure | GitHub.com | ✅ None (agentless) |
| Local execution | `act` (limited) | ✅ Native |
| Reproducibility | ❌ Variable | ✅ Guaranteed (Nix) |
| Type safety | ❌ YAML | ✅ Nix |
| Cost | $21/month+ | ✅ $0 |

### vs GitLab CI

| Feature | GitLab CI | NixActions |
|---------|----------|------------|
| Execution | Sequential by default | ✅ Parallel |
| Infrastructure | GitLab instance | ✅ None |
| Local testing | Limited | ✅ Native |

## Philosophy

1. **Local-first** - CI should work locally first, remote is optional
2. **Agentless** - No agents, no polling, no registration
3. **Deterministic** - Nix guarantees reproducibility
4. **Composable** - Everything is a function
5. **Simple** - Minimal abstractions, maximum power
6. **Parallel** - Jobs run in parallel by default (like GitHub Actions)

## Development

```bash
# Enter development environment
$ nix develop

# Run basic examples
$ nix run .#example-simple
$ nix run .#example-parallel
$ nix run .#example-env-sharing

# Run feature examples
$ nix run .#example-artifacts
$ nix run .#example-retry
$ nix run .#example-secrets
$ nix run .#example-matrix-builds

# Run real-world examples
$ nix run .#example-complete
$ nix run .#example-python-ci
$ nix run .#example-nodejs-full-pipeline

# Run comprehensive test suites
$ nix run .#test-retry-comprehensive
$ nix run .#test-conditions-comprehensive

# Compile all examples to bash scripts
$ ./scripts/compile-examples.sh
```

## Roadmap

See [TODO.md](./TODO.md) for detailed implementation plan.

**Phase 1 (MVP)**: ✅ COMPLETED
- Core execution engine with DAG-based parallel execution
- Local executor with workspace/job isolation
- OCI executor with per-job containers
- Actions as Derivations (build-time compilation)
- Retry mechanism (3 backoff strategies)
- Timeout handling
- Condition system (built-in + bash scripts)
- Artifacts management with custom restore paths
- Environment providers (file, sops, static, required)
- Matrix job generation
- Structured logging (3 formats)
- 30+ working examples

**Phase 2 (Next)**: Remote Executors & Ecosystem
- SSH executor with nix-copy-closure
- Kubernetes executor
- Extended actions library
- Production hardening
- Documentation improvements

## License

MIT

## Documentation

- **[DESIGN.md](./DESIGN.md)** - Detailed architecture and design decisions
- **[TODO.md](./TODO.md)** - Implementation roadmap
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - Contribution guidelines
- **[compiled-examples/](./compiled-examples/)** - Compiled bash scripts showing generated code

## Contributing

Contributions are welcome! Please:
1. Read [DESIGN.md](./DESIGN.md) for architecture details
2. Check [TODO.md](./TODO.md) for planned features
3. Submit PRs with clear descriptions

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/nixactions/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/nixactions/discussions)
- **License**: MIT (see [LICENSE](./LICENSE))
