# Secrets Masking Design

**Status:** Implementation in progress  
**Priority:** CRITICAL (security blocker)  
**Estimated time:** 1-2 days

---

## 🎯 Goal

Prevent secret values from appearing in logs, while preserving them in the runtime environment for actions to use.

**Current (DANGEROUS):**
```bash
[2025-12-25] [action:deploy] Deploying with API_KEY=sk_live_abc123def456
[2025-12-25] [action:deploy] Database: postgres://user:secret_password@host/db
```

**Target (SAFE):**
```bash
[2025-12-25] [action:deploy] Deploying with API_KEY=***
[2025-12-25] [action:deploy] Database: postgres://user:***@host/db
```

---

## 🏗️ Architecture

### 1. Provider-Controlled Masking (CHOSEN APPROACH)

**Key Principle:** Environment providers decide which variables are secrets.

```nix
# Provider returns derivation with metadata
provider = pkgs.writeScriptBin "env-provider-sops" ''
  # Output exports as usual
  export API_KEY="sk_live_123"
  export DB_PASSWORD="secret456"
'' // {
  passthru = {
    # Provider declares: all my variables are secrets
    allSecrets = true;
  };
};
```

**Why this approach?**
- ✅ Provider knows best - SOPS = always secrets, static = usually not
- ✅ Flexible - each provider controls its own security policy
- ✅ Extensible - new providers define their own rules
- ✅ Simple - no complex auto-detection needed

---

## 📐 Provider API

### Provider Metadata

Each environment provider derivation can have `passthru` metadata:

```nix
providerDerivation // {
  passthru = {
    # Option 1: All variables from this provider are secrets
    allSecrets = true;
    
    # Option 2: Specific list of secret variable names
    secrets = [ "API_KEY" "DB_PASSWORD" ];
    
    # Option 3: No secrets (default if passthru not present)
    allSecrets = false;
  };
}
```

### Provider Implementation Examples

#### SOPS Provider (all secrets)
```nix
pkgs.writeScriptBin "env-provider-sops" ''
  sops -d secrets.yaml | yq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
'' // {
  passthru.allSecrets = true;  # Everything from SOPS is secret
}
```

#### Static Provider (no secrets)
```nix
pkgs.writeScriptBin "env-provider-static" ''
  export CI="true"
  export NODE_ENV="production"
'' // {
  passthru.allSecrets = false;  # Static config, not secret
}
```

#### File Provider (configurable)
```nix
{ path, secrets ? false }:

pkgs.writeScriptBin "env-provider-file" ''
  # Load from file
  ...
'' // {
  passthru.allSecrets = secrets;  # User decides
}
```

**Usage:**
```nix
# .env file with secrets
platform.envProviders.file { 
  path = ".env.secrets"; 
  secrets = true;  # Mark as secrets
}

# .env file with public config
platform.envProviders.file { 
  path = ".env.public"; 
  secrets = false;  # Not secrets
}
```

---

## 🔧 Workflow API

### Secrets Declaration

```nix
platform.mkWorkflow {
  name = "deploy";
  
  # Workflow-level explicit secrets
  secrets = [ "CUSTOM_TOKEN" "SPECIAL_KEY" ];
  
  # Workflow-level non-secrets (override provider metadata)
  nonSecrets = [ "PUBLIC_API_KEY" ];
  
  # Environment providers (with metadata)
  envFrom = [
    # All variables = secrets (allSecrets = true)
    (platform.envProviders.sops { file = ./secrets.yaml; })
    
    # No secrets (allSecrets = false)
    (platform.envProviders.static { CI = "true"; })
    
    # User-controlled
    (platform.envProviders.file { 
      path = ".env"; 
      secrets = true;  # Mark as secrets
    })
  ];
  
  jobs = {
    deploy = {
      # Job-level secrets
      secrets = [ "DEPLOY_KEY" ];
      
      actions = [{
        # Action-level secrets
        secrets = [ "ACTION_SECRET" ];
        
        bash = ''
          echo "Deploying with $API_KEY"  # → "Deploying with ***"
        '';
      }];
    };
  };
}
```

### Priority Order

Secrets are collected from multiple sources:

1. **Workflow `secrets`** - explicit workflow-level
2. **Job `secrets`** - explicit job-level
3. **Action `secrets`** - explicit action-level
4. **Provider metadata** (`allSecrets = true` or `secrets = [...]`)

Override with `nonSecrets`:
```nix
{
  envFrom = [
    # Provider marks PUBLIC_API_KEY as secret
    (provider { allSecrets = true; })
  ];
  
  # Override: this is NOT a secret
  nonSecrets = [ "PUBLIC_API_KEY" ];
}
```

---

## 🔍 Masking Implementation

### Phase 1: Collect Secret Names (Build Time)

```nix
# In mk-workflow.nix
let
  # Collect secrets from all sources
  allSecretNames = lib.unique (lib.flatten [
    # Explicit workflow secrets
    (workflow.secrets or [])
    
    # Explicit job secrets
    (lib.concatMap (job: job.secrets or []) (lib.attrValues jobs))
    
    # Explicit action secrets
    (lib.concatMap (action: action.secrets or []) allActions)
    
    # Provider metadata secrets
    (lib.concatMap (provider:
      if provider.passthru.allSecrets or false
      then extractVariableNames provider  # Parse exports to get names
      else provider.passthru.secrets or []
    ) envFrom)
  ]);
  
  # Remove non-secrets
  secretNames = lib.filter (name: 
    ! lib.elem name (workflow.nonSecrets or [])
  ) allSecretNames;
in
```

### Phase 2: Collect Secret Values (Runtime)

```bash
# In generated workflow script
NIXACTIONS_SECRET_NAMES=(API_KEY DB_PASSWORD GITHUB_TOKEN)
NIXACTIONS_SECRET_VALUES=()

# After providers execute, collect actual values
for secret_name in "${NIXACTIONS_SECRET_NAMES[@]}"; do
  if [ -n "${!secret_name:-}" ]; then
    NIXACTIONS_SECRET_VALUES+=("${!secret_name}")
  fi
done
```

### Phase 3: Mask Output (Runtime)

```bash
# In runtime-helpers.nix
mask_secrets() {
  local line="$1"
  local min_length=8
  
  # Mask each secret value
  for secret_value in "${NIXACTIONS_SECRET_VALUES[@]}"; do
    if [ -n "$secret_value" ] && [ ${#secret_value} -ge $min_length ]; then
      # Escape special chars for sed
      local escaped=$(printf '%s\n' "$secret_value" | sed 's/[]\/$*.^[]/\\&/g')
      
      # Replace all occurrences (including partial matches)
      line=$(echo "$line" | sed "s/$escaped/***/g")
    fi
  done
  
  echo "$line"
}

# Wrap all logging
_log() {
  local message="$*"
  message=$(mask_secrets "$message")
  # ... output masked message
}

# Wrap action output
run_action() {
  # ...
  "$action_binary" 2>&1 | while IFS= read -r line; do
    masked=$(mask_secrets "$line")
    _log_line "$job_name" "$action_name" "$masked"
  done
}
```

---

## 🛡️ Security Considerations

### Minimum Secret Length

**Problem:** Short secrets create false positives
```bash
TOKEN="1"
echo "Build #1 completed"  # → "Build #*** completed" 😞
```

**Solution:** Minimum length = 8 characters
- Length < 8: Log warning, don't mask
- Length >= 8: Mask

```bash
if [ ${#secret_value} -lt 8 ]; then
  echo "WARNING: Secret '$secret_name' is too short (${#secret_value} chars). Minimum 8 chars recommended for masking." >&2
fi
```

### Partial Matching

**Behavior:** Mask partial occurrences
```bash
API_KEY="secret123"
echo "prefix_secret123_suffix"  # → "prefix_***_suffix"
```

**Why:** More secure - prevents secret leakage in:
- URLs: `https://api.example.com?token=secret123&foo=bar`
- Connection strings: `postgres://user:secret123@host/db`
- JSON: `{"token":"secret123","status":"ok"}`

### Special Characters

**Problem:** Secrets with regex special chars: `$`, `*`, `.`, `[`, `]`

**Solution:** Escape before using in sed:
```bash
escaped=$(printf '%s\n' "$secret_value" | sed 's/[]\/$*.^[]/\\&/g')
```

---

## 📋 Implementation Checklist

### Phase 1: Provider Metadata (1-2 hours)
- [x] Add `passthru.allSecrets` to sops.nix
- [x] Add `passthru.allSecrets` to static.nix
- [ ] Add `secrets` parameter to file.nix
- [ ] Add `passthru.allSecrets` to required.nix (false)
- [ ] Add to vault.nix, 1password.nix, age.nix, bitwarden.nix (when implemented)

### Phase 2: Workflow API (1 hour)
- [ ] Add `secrets` parameter to mkWorkflow
- [ ] Add `nonSecrets` parameter to mkWorkflow
- [ ] Add `secrets` to job config
- [ ] Add `secrets` to action config
- [ ] Collect all secret names at build time

### Phase 3: Runtime Masking (2-3 hours)
- [ ] Create `lib/secrets.nix` helper library
- [ ] Add `mask_secrets()` to runtime-helpers.nix
- [ ] Wrap `_log()` with masking
- [ ] Wrap `_log_line()` with masking
- [ ] Wrap `_log_workflow()` with masking
- [ ] Wrap `_log_job()` with masking
- [ ] Pass `NIXACTIONS_SECRET_NAMES` to executors
- [ ] Collect `NIXACTIONS_SECRET_VALUES` at runtime

### Phase 4: Testing (1-2 hours)
- [ ] Create `examples/02-features/test-secrets-masking.nix`
- [ ] Test workflow-level secrets
- [ ] Test job-level secrets
- [ ] Test action-level secrets
- [ ] Test provider metadata (sops allSecrets=true)
- [ ] Test provider metadata (static allSecrets=false)
- [ ] Test file provider with secrets=true
- [ ] Test nonSecrets override
- [ ] Test minimum length warning
- [ ] Test partial matching
- [ ] Test special characters in secrets

### Phase 5: Documentation (1 hour)
- [ ] Update DESIGN.md with secrets section
- [ ] Update README.md with secrets usage
- [ ] Add security best practices guide
- [ ] Document all provider metadata options

---

## 🎨 Examples

### Example 1: SOPS Secrets (Auto-masked)

```nix
platform.mkWorkflow {
  name = "deploy";
  
  envFrom = [
    # All variables from SOPS = secrets (allSecrets = true)
    (platform.envProviders.sops { 
      file = ./secrets.yaml; 
      format = "yaml";
    })
  ];
  
  jobs.deploy.actions = [{
    bash = ''
      echo "API Key: $API_KEY"
      echo "DB Password: $DB_PASSWORD"
    '';
  }];
}
```

**Output:**
```
[2025-12-25] [action:deploy] API Key: ***
[2025-12-25] [action:deploy] DB Password: ***
```

### Example 2: Mixed Public + Secret Config

```nix
platform.mkWorkflow {
  name = "build";
  
  envFrom = [
    # Public config (allSecrets = false)
    (platform.envProviders.static {
      CI = "true";
      NODE_ENV = "production";
      BUILD_NUMBER = "123";
    })
    
    # Secret config (allSecrets = true)
    (platform.envProviders.sops { 
      file = ./secrets.yaml; 
    })
  ];
  
  jobs.build.actions = [{
    bash = ''
      echo "Environment: $NODE_ENV"
      echo "Build: $BUILD_NUMBER"
      echo "API Key: $API_KEY"
    '';
  }];
}
```

**Output:**
```
[2025-12-25] [action:build] Environment: production
[2025-12-25] [action:build] Build: 123
[2025-12-25] [action:build] API Key: ***
```

### Example 3: Explicit Secrets

```nix
platform.mkWorkflow {
  name = "test";
  
  # Explicit secrets (not from provider)
  secrets = [ "CUSTOM_TOKEN" ];
  
  env = {
    CUSTOM_TOKEN = "my_secret_token_12345";
    PUBLIC_VAR = "public_value";
  };
  
  jobs.test.actions = [{
    bash = ''
      echo "Token: $CUSTOM_TOKEN"
      echo "Public: $PUBLIC_VAR"
    '';
  }];
}
```

**Output:**
```
[2025-12-25] [action:test] Token: ***
[2025-12-25] [action:test] Public: public_value
```

### Example 4: Override with nonSecrets

```nix
platform.mkWorkflow {
  name = "deploy";
  
  envFrom = [
    # File that marks everything as secret
    (platform.envProviders.file { 
      path = ".env"; 
      secrets = true;  # All vars = secrets
    })
  ];
  
  # But this one is actually public
  nonSecrets = [ "PUBLIC_API_ENDPOINT" ];
  
  jobs.deploy.actions = [{
    bash = ''
      echo "Endpoint: $PUBLIC_API_ENDPOINT"  # Not masked
      echo "Key: $API_KEY"                   # Masked
    '';
  }];
}
```

**Output:**
```
[2025-12-25] [action:deploy] Endpoint: https://api.example.com
[2025-12-25] [action:deploy] Key: ***
```

---

## 🚨 Security Warnings

### Secrets in Code (NOT Recommended)

```nix
# ❌ DON'T DO THIS - secret in Nix code
{
  env = {
    API_KEY = "sk_live_123abc";  # Visible in /nix/store!
  };
}
```

**Problem:** Secret stored in /nix/store (world-readable)

**Solution:** Use environment providers that load at runtime:
```nix
# ✅ DO THIS - secret loaded at runtime
{
  envFrom = [
    (platform.envProviders.sops { file = ./secrets.yaml; })
  ];
}
```

### Minimum Length Warning

If secret is < 8 characters, workflow logs warning:
```
WARNING: Secret 'API_KEY' is too short (5 chars). Minimum 8 chars recommended for masking.
```

**Recommendation:** Use longer secrets (>= 8 chars) for reliable masking.

---

## 📊 Performance Considerations

### Masking Overhead

**Per line of output:**
- Iterate through N secret values
- Perform sed replacement for each

**Optimization:**
- Skip empty secrets
- Skip secrets < 8 chars
- Cache escaped regex patterns

**Expected Impact:** Negligible (< 1ms per log line)

### Memory Usage

**Secret storage:**
```bash
NIXACTIONS_SECRET_NAMES=(key1 key2 key3)        # ~10 bytes per name
NIXACTIONS_SECRET_VALUES=(val1 val2 val3)       # ~50 bytes per value
```

**Expected:** < 1KB for typical workflow (10-20 secrets)

---

## 🔄 Future Enhancements

### 1. Regex Secret Patterns

```nix
{
  secretPatterns = [
    "sk_live_[a-zA-Z0-9]+"      # Stripe keys
    "ghp_[a-zA-Z0-9]{36}"       # GitHub tokens
    "AKIA[A-Z0-9]{16}"          # AWS keys
  ];
}
```

### 2. Secret Scanning (Pre-commit Hook)

Detect secrets before commit:
```bash
$ git commit
ERROR: Potential secret detected in env.nix:
  Line 5: API_KEY = "sk_live_..."
```

### 3. Audit Logging

Track which actions accessed which secrets:
```
[2025-12-25] [audit] action:deploy accessed secrets: API_KEY, DB_PASSWORD
```

### 4. Temporary Secrets

Auto-expire secrets after workflow completes:
```nix
{
  secrets = [ "TEMP_TOKEN" ];
  secretExpiry = "1h";  # Revoke after 1 hour
}
```

---

## ✅ Success Criteria

- [ ] No secret values visible in any logs (stdout/stderr/structured)
- [ ] Secrets still work in runtime (actions can use them)
- [ ] All provider types supported (sops/vault/file/static)
- [ ] Performance impact < 5% (negligible)
- [ ] Comprehensive test coverage
- [ ] Documentation complete
- [ ] Security audit passed

---

**Last Updated:** 2025-12-25  
**Next Review:** After implementation complete
