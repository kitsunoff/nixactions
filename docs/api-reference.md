# API Reference

Complete API documentation for NixActions.

---

## Platform API

```nix
platform :: {
  # Core constructors
  mkWorkflow   :: WorkflowConfig -> Derivation,
  mkExecutor   :: ExecutorConfig -> Executor,
  mkMatrixJobs :: MatrixConfig -> AttrSet Job,
  
  # Built-in executors
  executors :: {
    local :: LocalConfig -> Executor,
    oci   :: OciConfig -> Executor,
  },
  
  # Standard actions
  actions :: { ... },
  
  # Environment providers
  envProviders :: { ... },
  
  # Pre-built jobs
  jobs :: { ... },
  
  # Cross-platform support
  linuxPkgs :: Packages,  # Linux packages (for Darwin hosts)
}
```

---

## mkWorkflow

```nix
mkWorkflow :: {
  name    :: String,
  jobs    :: AttrSet Job,
  env     :: AttrSet String = {},
  envFrom :: [Derivation] = [],
  retry   :: RetryConfig | Null = null,
  timeout :: Int | Null = null,
} -> Derivation
```

### Example

```nix
platform.mkWorkflow {
  name = "ci";
  
  env = {
    CI = "true";
  };
  
  envFrom = [
    (platform.envProviders.file { path = ".env"; })
  ];
  
  retry = {
    max_attempts = 2;
    backoff = "exponential";
  };
  
  jobs = {
    test = { ... };
    build = { ... };
  };
}
```

---

## Job Config

```nix
Job :: {
  # Required
  executor :: Executor,
  actions  :: [Action],
  
  # Dependencies
  needs :: [String] = [],
  
  # Conditional execution
  condition :: Condition = "success()",
  
  # Error handling
  continueOnError :: Bool = false,
  
  # Environment
  env     :: AttrSet String = {},
  envFrom :: [Derivation] = [],
  
  # Artifacts
  inputs  :: [String | { name :: String, path :: String }] = [],
  outputs :: AttrSet String = {},
  
  # Retry/timeout
  retry   :: RetryConfig | Null = null,
  timeout :: Int | Null = null,
}
```

### Example

```nix
{
  test = {
    executor = platform.executors.local;
    needs = ["lint"];
    condition = "success()";
    
    env = {
      NODE_ENV = "test";
    };
    
    inputs = ["deps"];
    outputs = {
      coverage = "coverage/";
    };
    
    retry = {
      max_attempts = 3;
      backoff = "exponential";
    };
    
    timeout = 300;
    
    actions = [
      { bash = "npm test"; }
    ];
  };
}
```

---

## Action Config

```nix
Action :: {
  name      :: String = "action",
  bash      :: String,
  deps      :: [Derivation] = [],
  env       :: AttrSet String = {},
  workdir   :: Path | Null = null,
  condition :: Condition | Null = null,
  retry     :: RetryConfig | Null = null,
  timeout   :: Int | Null = null,
}
```

### Example

```nix
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
  env = {
    CI = "true";
  };
  condition = ''[ "$BRANCH" = "main" ]'';
  retry = {
    max_attempts = 3;
  };
  timeout = 120;
}
```

---

## Condition

```nix
Condition ::
  | "success()"    # Run if all deps succeeded (default)
  | "failure()"    # Run if any dep failed
  | "always()"     # Always run
  | "cancelled()"  # Run if workflow cancelled
  | String         # Bash script (exit 0 = run, exit 1 = skip)
```

### Examples

```nix
condition = "success()";
condition = "failure()";
condition = "always()";
condition = ''[ "$BRANCH" = "main" ]'';
condition = ''test -f package.json'';
condition = ''git diff --quiet'';
```

---

## RetryConfig

```nix
RetryConfig :: {
  max_attempts :: Int = 1,
  backoff      :: "exponential" | "linear" | "constant" = "exponential",
  min_time     :: Int = 1,
  max_time     :: Int = 60,
}
```

### Examples

```nix
# Exponential backoff
retry = {
  max_attempts = 5;
  backoff = "exponential";
  min_time = 1;
  max_time = 60;
};

# Linear backoff
retry = {
  max_attempts = 3;
  backoff = "linear";
  min_time = 2;
  max_time = 30;
};

# Constant delay
retry = {
  max_attempts = 10;
  backoff = "constant";
  min_time = 5;
};

# Disable retry
retry = null;
```

---

## Executors

### platform.executors.local

```nix
local :: {
  copyRepo :: Bool = true,
  name     :: String | Null = null,
} -> Executor
```

**Examples:**

```nix
# Default
executor = platform.executors.local

# Without repo copy
executor = platform.executors.local { copyRepo = false; }

# Custom name (separate workspace)
executor = platform.executors.local { name = "isolated"; }
```

### platform.executors.oci

```nix
oci :: {
  name          :: String | Null = null,
  mode          :: "shared" | "isolated" = "shared",
  copyRepo      :: Bool = true,
  extraPackages :: [Derivation] = [],
  extraMounts   :: [String] = [],
  containerEnv  :: AttrSet String = {},
} -> Executor
```

**Examples:**

```nix
# Default (shared mode)
executor = platform.executors.oci {}

# With extra packages
executor = platform.executors.oci {
  extraPackages = [ platform.linuxPkgs.git platform.linuxPkgs.curl ];
}

# Isolated mode (container per job)
executor = platform.executors.oci {
  mode = "isolated";
}

# Custom mounts
executor = platform.executors.oci {
  extraMounts = [ "/data:/data:ro" ];
}
```

---

## mkExecutor

```nix
mkExecutor :: {
  name     :: String,
  copyRepo :: Bool = true,
  
  # Workspace level
  setupWorkspace   :: { actionDerivations :: [Derivation] } -> String,
  cleanupWorkspace :: { actionDerivations :: [Derivation] } -> String,
  
  # Job level
  setupJob   :: { jobName :: String, actionDerivations :: [Derivation] } -> String,
  executeJob :: { jobName :: String, actionDerivations :: [Derivation], env :: AttrSet } -> String,
  cleanupJob :: { jobName :: String } -> String,
  
  # Artifacts
  saveArtifact    :: { name :: String, path :: String, jobName :: String } -> String,
  restoreArtifact :: { name :: String, path :: String, jobName :: String } -> String,
} -> Executor
```

---

## Standard Actions

### Setup Actions

```nix
platform.actions.checkout :: Action

platform.actions.setupNode :: {
  version :: String,
} -> Action

platform.actions.setupPython :: {
  version :: String,
} -> Action

platform.actions.setupRust :: Action
```

### Package Management

```nix
platform.actions.nixShell :: [String] -> Action
```

**Example:**

```nix
(platform.actions.nixShell [ "curl" "jq" "git" ])
```

### NPM Actions

```nix
platform.actions.npmInstall :: Action
platform.actions.npmTest :: Action
platform.actions.npmBuild :: Action
platform.actions.npmLint :: Action
```

### Secrets Actions

```nix
platform.actions.sopsLoad :: {
  file   :: Path,
  format :: "yaml" | "json" | "dotenv" = "yaml",
} -> Action

platform.actions.vaultLoad :: {
  path :: String,
  addr :: String | Null = null,
} -> Action

platform.actions.opLoad :: {
  vault :: String,
  item  :: String,
} -> Action

platform.actions.ageDecrypt :: {
  file     :: Path,
  identity :: Path,
} -> Action

platform.actions.bwLoad :: {
  itemId :: String,
} -> Action

platform.actions.requireEnv :: [String] -> Action
```

---

## Environment Providers

```nix
platform.envProviders.file :: {
  path     :: String,
  required :: Bool = false,
} -> Derivation

platform.envProviders.sops :: {
  file     :: Path,
  format   :: "yaml" | "json" | "dotenv" = "yaml",
  required :: Bool = true,
} -> Derivation

platform.envProviders.static :: AttrSet String -> Derivation

platform.envProviders.required :: [String] -> Derivation
```

### Examples

```nix
envFrom = [
  (platform.envProviders.file {
    path = ".env";
    required = false;
  })
  
  (platform.envProviders.sops {
    file = ./secrets.sops.yaml;
    format = "yaml";
  })
  
  (platform.envProviders.static {
    CI = "true";
    NODE_ENV = "production";
  })
  
  (platform.envProviders.required [
    "API_KEY"
    "DATABASE_URL"
  ])
];
```

---

## mkMatrixJobs

```nix
mkMatrixJobs :: {
  name     :: String,
  matrix   :: AttrSet [Any],
  executor :: Executor | (MatrixEntry -> Executor),
  actions  :: [Action] | (MatrixEntry -> [Action]),
  # ... other Job fields
} -> AttrSet Job
```

### Example

```nix
platform.mkMatrixJobs {
  name = "test";
  matrix = {
    node = [ "18" "20" "22" ];
    os = [ "ubuntu" "macos" ];
  };
  executor = platform.executors.local;
  actions = entry: [
    {
      bash = "echo Testing Node ${entry.node} on ${entry.os}";
    }
  ];
}

# Generates:
# {
#   test-node-18-os-ubuntu = { ... };
#   test-node-18-os-macos = { ... };
#   test-node-20-os-ubuntu = { ... };
#   ...
# }
```

---

## Pre-built Jobs

```nix
platform.jobs.buildahBuildPush :: {
  name       :: String,
  context    :: String = ".",
  dockerfile :: String = "Dockerfile",
  image      :: String,
  tags       :: [String] = ["latest"],
  push       :: Bool = true,
  registry   :: String | Null = null,
} -> Job
```

### Example

```nix
jobs = {
  build-image = platform.jobs.buildahBuildPush {
    name = "myapp";
    image = "registry.example.com/myapp";
    tags = [ "latest" "v1.0.0" ];
  };
};
```

---

## See Also

- [Core Contracts](./core-contracts.md) - Type definitions
- [Actions](./actions.md) - Actions deep dive
- [Executors](./executors.md) - Executor implementations
- [Environment](./environment.md) - Environment providers
