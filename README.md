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

This repository includes 10 working examples:

### Simple Workflow
```bash
$ nix run .#example-simple
```
Basic sequential job execution with actions.

### Parallel Workflow
```bash
$ nix run .#example-parallel
```
Demonstrates parallel execution with multiple levels.

### Complete CI/CD Pipeline
```bash
$ nix run .#example-complete
```
Full-featured pipeline with:
- Parallel linting & validation
- Testing
- Building
- Deployment
- Notifications
- Cleanup (always runs)

### Secrets Management
```bash
$ nix run .#example-secrets

# With runtime environment override
$ API_KEY=secret123 nix run .#example-secrets
```
Demonstrates environment variables at workflow/job/action levels.

### Test Environment Propagation
```bash
$ nix run .#example-test-env
```
Demonstrates that environment variables (secrets) propagate between actions correctly.

### Test Job Isolation
```bash
$ nix run .#example-test-isolation
```
Demonstrates job isolation - environment variables don't leak between jobs (subshell by design).

### Python CI/CD Pipeline
```bash
$ nix run .#example-python-ci
$ nix run .#example-python-ci-simple
```
Real-world example: Python project with unit tests (pytest), linting (flake8), type checking (mypy), and Docker image building.

### Docker Executor
```bash
$ nix run .#example-docker-ci
```
Demonstrates running jobs inside Docker containers using the OCI executor.

### Dynamic Package Loading (nixShell)
```bash
$ nix run .#example-nix-shell
```
Shows how to dynamically add packages to job environments without modifying executors.

## Core Concepts

### Executors

Executors define **where** code runs:

```nix
# Local machine
executor = platform.executors.local;

# Remote via SSH
executor = platform.executors.ssh {
  host = "build-server.internal";
  user = "ci";
};

# Docker container
executor = platform.executors.oci {
  image = "nixos/nix";
};

# Kubernetes
executor = platform.executors.k8s {
  namespace = "ci";
};
```

Available executors:
- `local` - Current machine
- `ssh` - Remote via SSH
- `oci` - Docker/OCI containers
- `nixos-container` - systemd-nspawn
- `k8s` - Kubernetes pods
- `nomad` - Nomad jobs

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

```nix
{
  # Only if all needed jobs succeeded (default)
  "if" = "success()";
  
  # Only if any needed job failed
  "if" = "failure()";
  
  # Always run (notifications, cleanup)
  "if" = "always()";
  
  # Only if workflow cancelled
  "if" = "cancelled()";
}
```

Example:

```nix
jobs = {
  test = { ... };
  
  # Only runs if test succeeded
  deploy = {
    needs = [ "test" ];
    "if" = "success()";
    ...
  };
  
  # Only runs if test failed
  rollback = {
    needs = [ "test" ];
    "if" = "failure()";
    ...
  };
  
  # Always runs (cleanup, notifications)
  notify = {
    needs = [ "test" ];
    "if" = "always()";
    ...
  };
}
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
│   ├── mk-executor.nix    # Executor constructor
│   ├── mk-workflow.nix    # Workflow compiler
│   ├── executors/         # Built-in executors
│   │   ├── local.nix
│   │   ├── ssh.nix
│   │   ├── oci.nix
│   │   ├── nixos-container.nix
│   │   ├── k8s.nix
│   │   └── nomad.nix
│   └── actions/           # Standard actions
│       ├── setup.nix      # Setup actions
│       ├── npm.nix        # NPM actions
│       ├── sops.nix       # SOPS secrets
│       ├── vault.nix      # Vault secrets
│       ├── 1password.nix  # 1Password
│       ├── age.nix        # Age encryption
│       ├── bitwarden.nix  # Bitwarden
│       └── require-env.nix # Env validation
└── examples/              # Working examples
    ├── simple.nix
    ├── parallel.nix
    ├── complete.nix
    └── secrets.nix
```

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
    # Setup actions
    checkout     :: Action,
    setupNode    :: { version :: String } -> Action,
    setupPython  :: { version :: String } -> Action,
    setupRust    :: Action,
    
    # Package management
    nixShell     :: [String] -> Action,
    
    # NPM actions
    npmInstall   :: Action,
    npmTest      :: Action,
    npmBuild     :: Action,
    npmLint      :: Action,
    
    # Secrets management
    sopsLoad     :: { file :: Path, format :: "yaml" | "json" | "dotenv" } -> Action,
    vaultLoad    :: { path :: String, addr :: String } -> Action,
    opLoad       :: { vault :: String, item :: String } -> Action,
    ageDecrypt   :: { file :: Path, identity :: Path } -> Action,
    bwLoad       :: { itemId :: String } -> Action,
    requireEnv   :: [String] -> Action,
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
  "if"            :: "success()" | "failure()" | "always()" | "cancelled()" = "success()",
  continueOnError :: Bool = false,
  env             :: AttrSet String = {},
}
```

### Action Config

```nix
{
  name    :: String = "action",
  bash    :: String,
  deps    :: [Derivation] = [],
  env     :: AttrSet String = {},
  workdir :: Path | Null = null,
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

# Run examples
$ nix run .#example-simple
$ nix run .#example-parallel
$ nix run .#example-complete
$ nix run .#example-secrets

# Build all examples
$ nix build .#example-simple
$ nix build .#example-parallel
$ nix build .#example-complete
$ nix build .#example-secrets
```

## Roadmap

See [TODO.md](./TODO.md) for detailed implementation plan.

**Phase 1 (MVP)**: ✅ COMPLETED
- Core execution engine
- Local executor
- 6 executors (local, ssh, oci, nixos-container, k8s, nomad)
- Standard actions library
- Secrets management (6 integrations)
- GitHub Actions-style execution
- 4 working examples

**Phase 2 (Next)**: Testing & Documentation
- Comprehensive testing
- Advanced executor features
- Extended actions library
- Production hardening

## License

MIT

## Documentation

- **[DESIGN.md](./DESIGN.md)** - Detailed architecture and design decisions
- **[COMPILED_EXAMPLES.md](./COMPILED_EXAMPLES.md)** - Compiled example outputs
- **[TODO.md](./TODO.md)** - Implementation roadmap

## Contributing

Contributions are welcome! Please:
1. Read [DESIGN.md](./DESIGN.md) for architecture details
2. Check [TODO.md](./TODO.md) for planned features
3. Submit PRs with clear descriptions

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/nixactions/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/nixactions/discussions)
- **License**: MIT (see [LICENSE](./LICENSE))
