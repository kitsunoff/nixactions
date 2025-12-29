# User Guide

Get started with NixActions in minutes.

---

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- For OCI executor: Docker daemon running

---

## Quick Start

### 1. Add NixActions to Your Project

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixactions.url = "github:yourorg/nixactions";
  };

  outputs = { nixpkgs, nixactions, ... }:
    let
      system = "x86_64-linux";  # or "aarch64-darwin", etc.
      pkgs = nixpkgs.legacyPackages.${system};
      nixactionsLib = nixactions.lib.${system};
    in {
      packages.${system}.ci = import ./ci.nix { 
        inherit pkgs nixactions; 
      };
    };
}
```

### 2. Create a Workflow

```nix
# ci.nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "ci";
  
  jobs = {
    test = {
      executor = nixactions.executors.local;
      steps = [
        { bash = "echo 'Hello, NixActions!'"; }
      ];
    };
  };
}
```

### 3. Run It

```bash
# Build and run
$ nix run .#ci

# Or build first, then run
$ nix build .#ci
$ ./result/bin/ci
```

---

## Basic Concepts

### Jobs and Actions

```nix
jobs = {
  my-job = {
    executor = nixactions.executors.local;
    steps = [
      { bash = "echo 'Step 1'"; }
      { bash = "echo 'Step 2'"; }
    ];
  };
};
```

### Dependencies

```nix
jobs = {
  lint = { ... };
  test = { ... };
  
  build = {
    needs = [ "lint" "test" ];  # Waits for both
    ...
  };
};
```

### Parallel Execution

Jobs without dependencies run in parallel:

```nix
jobs = {
  lint = { ... };    # Level 0 - runs immediately
  test = { ... };    # Level 0 - runs in parallel with lint
  build = {
    needs = [ "lint" "test" ];  # Level 1 - waits for both
    ...
  };
};
```

---

## Common Patterns

### Node.js Project

```nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "nodejs-ci";
  
  jobs = {
    test = {
      executor = nixactions.executors.local;
      steps = [
        {
          name = "install";
          bash = "npm ci";
          deps = [ pkgs.nodejs ];
        }
        {
          name = "lint";
          bash = "npm run lint";
          deps = [ pkgs.nodejs ];
        }
        {
          name = "test";
          bash = "npm test";
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    build = {
      needs = [ "test" ];
      executor = nixactions.executors.local;
      
      outputs = {
        dist = "dist/";
      };
      
      steps = [
        {
          name = "build";
          bash = "npm run build";
          deps = [ pkgs.nodejs ];
        }
      ];
    };
  };
}
```

### Python Project

```nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "python-ci";
  
  jobs = {
    test = {
      executor = nixactions.executors.local;
      steps = [
        {
          name = "install";
          bash = "pip install -r requirements.txt";
          deps = [ pkgs.python311 ];
        }
        {
          name = "lint";
          bash = "flake8 src/";
          deps = [ pkgs.python311Packages.flake8 ];
        }
        {
          name = "test";
          bash = "pytest";
          deps = [ pkgs.python311Packages.pytest ];
        }
      ];
    };
  };
}
```

### Conditional Deployment

```nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "deploy";
  
  jobs = {
    test = {
      executor = nixactions.executors.local;
      steps = [
        { bash = "npm test"; deps = [ pkgs.nodejs ]; }
      ];
    };
    
    deploy-staging = {
      needs = [ "test" ];
      condition = ''[ "$BRANCH" = "develop" ]'';
      executor = nixactions.executors.local;
      steps = [
        { bash = "deploy.sh staging"; }
      ];
    };
    
    deploy-production = {
      needs = [ "test" ];
      condition = ''[ "$BRANCH" = "main" ]'';
      executor = nixactions.executors.local;
      steps = [
        { bash = "deploy.sh production"; }
      ];
    };
    
    notify = {
      needs = [ "test" ];
      condition = "always()";
      executor = nixactions.executors.local;
      steps = [
        {
          bash = ''curl -X POST $SLACK_WEBHOOK -d '{"text":"CI complete"}' '';
          deps = [ pkgs.curl ];
        }
      ];
    };
  };
}
```

---

## Using Executors

### Local Executor

Runs on the current machine:

```nix
executor = nixactions.executors.local
```

### OCI Executor

Runs in Docker containers:

```nix
executor = nixactions.executors.oci {
  extraPackages = [ nixactions.linuxPkgs.nodejs ];
}
```

**Note:** Use `nixactions.linuxPkgs` for packages in OCI executor (required for cross-platform builds on macOS).

### Multiple Executors

```nix
jobs = {
  local-task = {
    executor = nixactions.executors.local;
    ...
  };
  
  container-task = {
    executor = nixactions.executors.oci { ... };
    ...
  };
};
```

---

## Working with Artifacts

### Save Artifacts

```nix
jobs = {
  build = {
    outputs = {
      dist = "dist/";
      binary = "target/release/myapp";
    };
    steps = [
      { bash = "npm run build"; }
    ];
  };
};
```

### Restore Artifacts

```nix
jobs = {
  deploy = {
    needs = [ "build" ];
    inputs = [ "dist" "binary" ];
    steps = [
      { bash = "ls dist/"; }
    ];
  };
};
```

### Custom Restore Paths

```nix
inputs = [
  { name = "frontend"; path = "public/"; }
  { name = "backend"; path = "server/"; }
]
```

---

## Environment Variables

### Workflow Level

```nix
nixactions.mkWorkflow {
  name = "ci";
  
  env = {
    CI = "true";
    NODE_ENV = "test";
  };
  
  jobs = { ... };
}
```

### Job Level

```nix
jobs = {
  deploy = {
    env = {
      ENVIRONMENT = "production";
    };
    ...
  };
};
```

### Action Level

```nix
{
  name = "build";
  env = {
    NODE_OPTIONS = "--max-old-space-size=4096";
  };
  bash = "npm run build";
}
```

### Runtime Override

```bash
$ API_KEY=secret123 nix run .#ci
```

---

## Secrets Management

### Using SOPS

```nix
jobs = {
  deploy = {
    steps = [
      # Load secrets
      (nixactions.actions.sopsLoad {
        file = ./secrets.sops.yaml;
      })
      
      # Validate
      (nixactions.actions.requireEnv [ "API_KEY" "DB_PASSWORD" ])
      
      # Use secrets
      { bash = "deploy.sh"; }
    ];
  };
};
```

### Using Environment Providers

```nix
nixactions.mkWorkflow {
  name = "ci";
  
  envFrom = [
    (nixactions.envProviders.file { path = ".env"; })
    (nixactions.envProviders.sops { file = ./secrets.sops.yaml; })
    (nixactions.envProviders.required [ "API_KEY" ])
  ];
  
  jobs = { ... };
}
```

---

## Retry Failed Actions

```nix
{
  name = "flaky-test";
  bash = "npm test";
  retry = {
    max_attempts = 3;
    backoff = "exponential";
    min_time = 1;
    max_time = 60;
  };
}
```

---

## Running Examples

NixActions comes with 30+ examples:

```bash
# Basic examples
$ nix run .#example-simple
$ nix run .#example-parallel
$ nix run .#example-env-sharing

# Feature examples
$ nix run .#example-artifacts
$ nix run .#example-retry
$ nix run .#example-secrets

# Real-world examples
$ nix run .#example-complete
$ nix run .#example-python-ci
$ nix run .#example-nodejs-full-pipeline
```

---

## Debugging

### View Generated Script

```bash
$ nix build .#ci
$ cat result/bin/ci
```

### Keep Workspace After Run

```bash
$ NIXACTIONS_KEEP_WORKSPACE=1 nix run .#ci
```

### Verbose Logging

```bash
$ NIXACTIONS_LOG_FORMAT=structured nix run .#ci
$ NIXACTIONS_LOG_FORMAT=json nix run .#ci
```

---

## Complete Example

```nix
{ pkgs, nixactions }:

nixactions.mkWorkflow {
  name = "production-ci";
  
  env = {
    CI = "true";
  };
  
  envFrom = [
    (nixactions.envProviders.file { path = ".env"; required = false; })
  ];
  
  jobs = {
    # Level 0: Parallel checks
    lint = {
      executor = nixactions.executors.local;
      steps = [
        {
          name = "eslint";
          bash = "npm run lint";
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    security = {
      executor = nixactions.executors.local;
      continueOnError = true;
      steps = [
        {
          name = "audit";
          bash = "npm audit";
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    # Level 1: Tests
    test = {
      needs = [ "lint" ];
      executor = nixactions.executors.local;
      
      outputs = {
        coverage = "coverage/";
      };
      
      steps = [
        {
          name = "test";
          bash = "npm test -- --coverage";
          deps = [ pkgs.nodejs ];
          retry = {
            max_attempts = 2;
            backoff = "exponential";
          };
        }
      ];
    };
    
    # Level 2: Build
    build = {
      needs = [ "test" ];
      executor = nixactions.executors.local;
      
      outputs = {
        dist = "dist/";
      };
      
      steps = [
        {
          name = "build";
          bash = "npm run build";
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    # Level 3: Deploy (only on main)
    deploy = {
      needs = [ "build" ];
      condition = ''[ "$BRANCH" = "main" ]'';
      executor = nixactions.executors.local;
      
      inputs = [ "dist" ];
      
      steps = [
        (nixactions.actions.requireEnv [ "DEPLOY_KEY" ])
        {
          name = "deploy";
          bash = "deploy.sh";
          deps = [ pkgs.kubectl ];
        }
      ];
    };
    
    # Level 3: Notify (always)
    notify = {
      needs = [ "build" ];
      condition = "always()";
      executor = nixactions.executors.local;
      
      steps = [
        {
          name = "slack";
          condition = "always()";
          bash = ''
            STATUS="success"
            [ ${#FAILED_JOBS[@]} -gt 0 ] && STATUS="failure"
            curl -X POST $SLACK_WEBHOOK -d "{\"status\":\"$STATUS\"}"
          '';
          deps = [ pkgs.curl ];
        }
      ];
    };
  };
}
```

---

## Next Steps

- [Architecture](./architecture.md) - Understand how NixActions works
- [Actions](./actions.md) - Deep dive into actions
- [Executors](./executors.md) - Learn about execution environments
- [API Reference](./api-reference.md) - Full API documentation
