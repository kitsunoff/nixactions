# Environment Management

Environment variables in NixActions are managed through executable provider derivations.

---

## Philosophy

**Core principles:**

1. **Secrets never in /nix/store** - Providers are executables, not values
2. **Executor-agnostic** - Works across local, OCI, SSH, K8s executors
3. **Multi-source** - Providers for files, secret managers, CLI, or config
4. **Immutable** - Loaded once at workflow start, shared across jobs
5. **Validated** - Provider derivations can fail if requirements not met
6. **Reusable** - Providers are derivations, can be shared and tested

**Key design:**
- **Build time**: Providers compiled to `/nix/store` as executables
- **Runtime**: Execute providers, capture output, apply to environment
- **Output format**: `export KEY="value"` (bash-compatible)

---

## Environment Providers

Providers are **executable derivations** that output `export` statements.

### Provider Type

```nix
Provider :: Derivation {
  type = "derivation";
  outputPath = "/nix/store/xxx-provider-name";
  
  # When executed:
  # $ /nix/store/xxx-provider-name
  # -> stdout: export API_KEY="secret123"
  #            export DB_URL="postgres://localhost/db"
}
```

### Built-in Providers

#### File Provider

Load from `.env` file:

```nix
nixactions.envProviders.file {
  path = ".env.production";
  required = false;  # Exit 1 if file not found
}
```

#### SOPS Provider

Decrypt SOPS encrypted file:

```nix
nixactions.envProviders.sops {
  file = ./secrets/prod.sops.yaml;
  format = "yaml";  # yaml | json | dotenv
  required = true;
}
```

#### Static Provider

Hardcoded values:

```nix
nixactions.envProviders.static {
  CI = "true";
  NODE_ENV = "production";
}
```

#### Required Validator

Validate that variables exist:

```nix
nixactions.envProviders.required [
  "API_KEY"
  "DATABASE_URL"
  "DEPLOY_TOKEN"
]
```

---

## Usage

### Workflow Level

```nix
nixactions.mkWorkflow {
  name = "ci";
  
  # Direct env vars (inline)
  env = {
    CI = "true";
    WORKFLOW_NAME = "ci";
  };
  
  # Provider derivations
  envFrom = [
    # Load common config
    (nixactions.envProviders.file {
      path = ".env.common";
      required = false;
    })
    
    # Load secrets from SOPS
    (nixactions.envProviders.sops {
      file = ./secrets/production.sops.yaml;
      required = true;
    })
    
    # Validate required variables
    (nixactions.envProviders.required [
      "API_KEY"
      "DATABASE_URL"
    ])
  ];
  
  jobs = { ... };
}
```

### Job Level

```nix
jobs = {
  deploy = {
    # Job-level env (overrides workflow)
    env = {
      SERVICE = "api";
      PORT = "3000";
    };
    
    # Job-level providers
    envFrom = [
      (nixactions.envProviders.file {
        path = ".env.deploy";
        required = false;
      })
    ];
    
    actions = [...];
  };
};
```

### Action Level

```nix
{
  name = "deploy";
  env = {
    DEPLOY_TIMEOUT = "300";
  };
  bash = "deploy.sh";
}
```

---

## Precedence Order

Highest to lowest priority:

```
Runtime:
  1. CLI env:          API_KEY=secret nix run .#ci
  2. CLI --env-file:   nix run .#ci -- --env-file .env.override

Build-time (evaluated in order):
  3. Action env
  4. Action envFrom
  5. Job env
  6. Job envFrom
  7. Workflow env
  8. Workflow envFrom (lowest)
```

**Key points:**
- Variables set by earlier sources skip later providers
- Providers executed in array order
- Providers can fail (exit 1) if required resources missing

---

## Provider Output Format

All providers must output valid bash `export` statements:

```bash
# Valid provider output
export API_KEY="secret123"
export DATABASE_URL="postgres://localhost:5432/mydb"
export NODE_ENV="production"

# Invalid - will be ignored
API_KEY=secret  # Missing 'export'
export invalid syntax  # Invalid format
echo "Setting vars"  # Not an export
```

**Rules:**
- One `export` per line
- Use proper quoting for values with spaces/special chars
- Exit code 0 = success, non-zero = failure
- Empty output is valid (provider has nothing to contribute)

---

## Executor Integration

Executors receive a fully-populated environment and inject it into the execution context.

### Local Executor

```bash
# Environment already in current shell
job_deploy() {
  cd $JOB_DIR
  ./action
}
```

### OCI Executor

```bash
# Pass environment to container
job_deploy() {
  env > "$TEMP_ENV"
  docker cp "$TEMP_ENV" "$CONTAINER_ID:/tmp/job-env.env"
  docker exec "$CONTAINER_ID" bash -c '
    source /tmp/job-env.env
    ./action
  '
}
```

### SSH Executor

```bash
# Transfer environment to remote
job_deploy() {
  env > "$TEMP_ENV"
  scp "$TEMP_ENV" "user@remote:/tmp/job-env.env"
  ssh "user@remote" bash -c '
    source /tmp/job-env.env
    ./action
  '
}
```

---

## Security Considerations

1. **Providers are executables, not values**
   - Provider code stored in /nix/store (safe - just bash scripts)
   - Secret values loaded only when provider executed
   - Secrets never cached in /nix/store

2. **Temporary files**
   - Env transfer files created with `mktemp`
   - Permissions set to `0600` (owner-only)
   - Cleaned up after job execution

3. **Logging**
   - Provider stdout parsed, not logged
   - Secret values never in workflow logs
   - Use `***` for sensitive values in output

4. **Validation**
   - Required providers fail fast (exit 1)
   - Clear error messages for missing secrets
   - No partial execution with missing secrets

---

## Complete Example

```nix
nixactions.mkWorkflow {
  name = "production-deployment";
  
  env = {
    CI = "true";
    ENVIRONMENT = "production";
  };
  
  envFrom = [
    (nixactions.envProviders.file {
      path = ".env.common";
      required = false;
    })
    
    (nixactions.envProviders.sops {
      file = ./secrets/common.sops.yaml;
      required = true;
    })
    
    (nixactions.envProviders.required [
      "VAULT_ADDR"
      "VAULT_TOKEN"
    ])
  ];
  
  jobs = {
    deploy-api = {
      executor = nixactions.executors.oci { ... };
      
      env = {
        SERVICE = "api";
        PORT = "3000";
      };
      
      envFrom = [
        (nixactions.envProviders.file {
          path = ".env.api";
          required = false;
        })
        
        (nixactions.envProviders.required [
          "API_KEY"
          "DATABASE_URL"
        ])
      ];
      
      actions = [
        {
          name = "validate-env";
          bash = ''
            echo "CI=$CI"
            echo "ENVIRONMENT=$ENVIRONMENT"
            echo "SERVICE=$SERVICE"
            echo "API_KEY=***"
          '';
        }
        
        {
          name = "deploy";
          env = {
            DEPLOY_TIMEOUT = "300";
          };
          bash = "deploy.sh";
        }
      ];
    };
  };
}
```

---

## Testing Providers

Since providers are derivations, they can be tested independently:

```bash
# Test file provider
$ nix build .#envProviders.file-production
$ ./result
export API_KEY="test"
export DB_URL="postgres://localhost/test"

# Test SOPS provider
$ SOPS_AGE_KEY_FILE=~/.sops/key.txt nix run .#envProviders.sops-secrets
export API_KEY="secret123"

# Test required validator
$ API_KEY=test DATABASE_URL=x nix run .#envProviders.validate
# (exits 0 if all present, 1 if missing)
```

---

## See Also

- [Actions](./actions.md) - Action-level environment
- [Executors](./executors.md) - Environment transfer to executors
- [API Reference](./api-reference.md) - Full envProviders API
