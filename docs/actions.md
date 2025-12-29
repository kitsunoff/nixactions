# Actions as Derivations

Actions are the fundamental building blocks of NixActions. Every action compiles to a Nix derivation.

---

## Why Actions = Derivations?

### Problem with String Concatenation

```nix
# Bad approach (hypothetical):
actionsScript = concatMapStrings (action: action.bash) job.actions;

# Problems:
# - No build-time validation
# - No caching
# - Runtime string manipulation
# - Executor can't provision dependencies
```

### Solution: Actions as Derivations

```nix
# NixActions approach:
actionDerivations = map mkAction job.actions;
# -> [ /nix/store/xxx-action1 /nix/store/yyy-action2 ]

# Benefits:
# + Build-time validation
# + Caching (Nix store)
# + Build-time compilation
# + Executor provisions once
```

---

## mkAction Implementation

```nix
mkAction :: {
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

### Generated Script

```bash
# /nix/store/xxx-test/bin/test
#!/usr/bin/env bash
set -euo pipefail

# Step-level condition (if specified)
if ! ( [ "$BRANCH" = "main" ] ); then
  echo "Skipping: test (condition not met)"
  exit 0
fi

# Working directory (if specified)
cd /some/path

# Environment variables
export NODE_ENV="test"
export CI="true"

# Dependencies in PATH
export PATH=/nix/store/nodejs/bin:$PATH

# Execute action
npm test
```

---

## Usage Examples

### Basic Action

```nix
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
}
```

### With Environment

```nix
{
  name = "build";
  bash = "npm run build";
  deps = [ pkgs.nodejs ];
  env = {
    NODE_ENV = "production";
    CI = "true";
  };
}
```

### With Condition

```nix
# Built-in condition
{
  name = "notify";
  bash = "curl -X POST $WEBHOOK";
  deps = [ pkgs.curl ];
  condition = "always()";
}

# Bash condition
{
  name = "deploy";
  bash = "kubectl apply -f k8s/";
  deps = [ pkgs.kubectl ];
  condition = ''[ "$BRANCH" = "main" ]'';
}
```

### With Retry

```nix
{
  name = "flaky-test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
  retry = {
    max_attempts = 3;
    backoff = "exponential";
    min_time = 1;
    max_time = 60;
  };
}
```

### With Timeout

```nix
{
  name = "long-test";
  bash = "npm run integration-test";
  deps = [ pkgs.nodejs ];
  timeout = 300;  # 5 minutes
}
```

### Direct Derivation

```nix
# You can also pass a derivation directly
let
  customAction = pkgs.writeScriptBin "custom" ''
    #!/usr/bin/env bash
    echo "Custom action"
  '';
in {
  actions = [ customAction ];
}
```

---

## Standard Actions Library

NixActions provides a library of pre-built actions:

### Setup Actions

```nix
# Checkout repository (usually automatic)
nixactions.actions.checkout

# Setup Node.js
nixactions.actions.setupNode { version = "20"; }

# Setup Python
nixactions.actions.setupPython { version = "3.11"; }

# Setup Rust
nixactions.actions.setupRust
```

### Dynamic Package Loading

```nix
# Add packages on-the-fly
nixactions.actions.nixShell [ "curl" "jq" "git" ]

# Usage in job
{
  actions = [
    (nixactions.actions.nixShell [ "curl" "jq" ])
    {
      bash = ''
        curl -s https://api.github.com/rate_limit | jq '.rate'
      '';
    }
  ];
}
```

### NPM Actions

```nix
nixactions.actions.npmInstall
nixactions.actions.npmTest
nixactions.actions.npmBuild
nixactions.actions.npmLint
```

### Secrets Actions

```nix
# Load from SOPS
nixactions.actions.sopsLoad {
  file = ./secrets.sops.yaml;
  format = "yaml";  # yaml | json | dotenv
}

# Load from Vault
nixactions.actions.vaultLoad {
  path = "secret/data/production";
}

# Validate required vars
nixactions.actions.requireEnv [ "API_KEY" "DB_PASSWORD" ]
```

---

## Build-Time Benefits

### 1. Validation

```bash
$ nix build .#ci
error: builder for '/nix/store/xxx-test.drv' failed
# Action fails -> workflow fails at build time
```

### 2. Caching

```bash
# Action unchanged -> reused from cache
$ nix build .#ci
# /nix/store/xxx-test already exists, skipping
```

### 3. Provision Once

```nix
# Old approach: provision on every job
job_test1() { provision nodejs; npm test; }
job_test2() { provision nodejs; npm test; }

# NixActions: provision once in setupWorkspace
setup_executor() { 
  setupWorkspace { 
    actionDerivations = [ /nix/store/xxx-test ]; 
  }
}
job_test1() { executeJob { ... } }
job_test2() { executeJob { ... } }  # Reuses same derivations
```

### 4. Composability

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

## Action Execution Flow

```
1. Workflow builds all action derivations
   /nix/store/xxx-checkout
   /nix/store/yyy-test
   /nix/store/zzz-build

2. Executor receives derivations in setupWorkspace
   actionDerivations = [ /nix/store/xxx /nix/store/yyy /nix/store/zzz ]

3. executeJob runs derivations in sequence
   /nix/store/xxx-checkout/bin/checkout
   /nix/store/yyy-test/bin/test
   /nix/store/zzz-build/bin/build

4. Each derivation is self-contained
   - Has all deps in PATH
   - Has env vars set
   - Has condition check
```

---

## Best Practices

### Keep Actions Small

```nix
# Good: focused actions
actions = [
  { name = "lint"; bash = "npm run lint"; }
  { name = "test"; bash = "npm test"; }
  { name = "build"; bash = "npm run build"; }
];

# Avoid: monolithic actions
actions = [
  { name = "ci"; bash = "npm run lint && npm test && npm run build"; }
];
```

### Use Deps for Dependencies

```nix
# Good: explicit dependencies
{
  name = "test";
  bash = "npm test";
  deps = [ pkgs.nodejs ];
}

# Avoid: assuming global tools
{
  name = "test";
  bash = "npm test";
  # Where does npm come from?
}
```

### Conditions at Right Level

```nix
# Job-level: affects all actions
jobs.deploy = {
  condition = ''[ "$BRANCH" = "main" ]'';
  actions = [ ... ];
};

# Action-level: affects single action
jobs.ci = {
  actions = [
    { bash = "npm test"; }
    {
      name = "deploy";
      condition = ''[ "$BRANCH" = "main" ]'';
      bash = "deploy.sh";
    }
  ];
};
```

---

## See Also

- [Conditions](./conditions.md) - Condition system details
- [Retry](./retry.md) - Retry mechanism
- [API Reference](./api-reference.md) - Full mkAction API
