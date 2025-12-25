# NixActions - Environment Providers Style Guide

This document defines the coding standards and patterns for creating environment providers in NixActions.

## Table of Contents

1. [Philosophy](#philosophy)
2. [Provider Anatomy](#provider-anatomy)
3. [API Patterns](#api-patterns)
4. [Naming Conventions](#naming-conventions)
5. [Output Contract](#output-contract)
6. [Security & Secrets](#security--secrets)
7. [Error Handling](#error-handling)
8. [Examples](#examples)
9. [Testing](#testing)

---

## Philosophy

**Environment providers are composable data sources for environment variables.**

Core principles:
- **Single responsibility** - Each provider does ONE thing well
- **Composable** - Providers can be chained and combined
- **Fail-safe** - Clear error handling with `required` parameter
- **Secure by default** - Explicit secrets handling
- **Pure output** - Providers output `export KEY=VALUE` statements
- **Metadata aware** - Use `passthru.allSecrets` for secrets tracking

---

## Provider Anatomy

Every environment provider MUST:
1. Return a derivation (using `pkgs.writeScriptBin`)
2. Output bash `export` statements to stdout
3. Use proper shell escaping for values
4. Include metadata about secrets via `passthru.allSecrets`

### Minimal Provider Structure

```nix
{ pkgs, lib }:

params:

pkgs.writeScriptBin "env-provider-name" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # Provider logic here
  # Output: export KEY=VALUE
'' // {
  # Metadata: Are all variables from this provider secrets?
  passthru.allSecrets = false;  # or true
}
```

---

## API Patterns

### Pattern 1: Static Provider (No Runtime Input)

Provider that outputs hardcoded values known at build time.

```nix
{ pkgs, lib }:

env:  # Attribute set of key-value pairs

pkgs.writeScriptBin "env-provider-static" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (key: value:
      "printf 'export %s=%s\\n' ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.escapeShellArg (toString value))}"
    ) env
  )}
'' // {
  passthru.allSecrets = false;
}
```

**Characteristics:**
- Takes attribute set as input
- No file I/O at runtime
- All values known at build time
- Not secrets by default

**Usage:**
```nix
envFrom = [
  (envProviders.static {
    NODE_ENV = "production";
    API_VERSION = "v1";
  })
];
```

---

### Pattern 2: File-Based Provider (Runtime Input)

Provider that reads from files at runtime.

```nix
{ pkgs, lib }:

{ path
, required ? false
}:

pkgs.writeScriptBin "env-provider-file" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${path}"
  
  # Check if file exists
  if [ ! -f "$FILE" ]; then
    ${if required then ''
      echo "Error: Required env file not found: $FILE" >&2
      exit 1
    '' else ''
      exit 0
    ''}
  fi
  
  # Process file and output exports
  # ... parsing logic ...
'' 
```

**Characteristics:**
- Takes configuration (path, flags) as input
- Reads from filesystem at runtime

**Usage:**
```nix
envFrom = [
  (envProviders.file {
    path = ".env";
    required = false;
    secrets = false;
  })
];
```

---

### Pattern 3: Transform Provider (Decryption/Processing)

Provider that transforms input data (e.g., SOPS decryption).

```nix
{ pkgs, lib }:

{ file
, format ? "yaml"
, required ? true
}:

pkgs.writeScriptBin "env-provider-sops" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${file}"
  FORMAT="${format}"
  
  # Validate prerequisites
  if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
    echo "Error: SOPS CLI not available" >&2
    exit 1
  fi
  
  # Decrypt and transform to exports
  case "$FORMAT" in
    yaml)
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | \
        ${pkgs.yq}/bin/yq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
      ;;
    # ... other formats ...
  esac
'' 
```

**Characteristics:**
- Decrypts or transforms data at runtime
- Uses external tools (sops, yq, jq)
- Always required by default (secrets are critical)

**Usage:**
```nix
envProviders = [
  (envProviders.sops {
    file = "secrets.enc.yaml";
    format = "yaml";
  })
];
```

---

### Pattern 4: Validation Provider (No Output)

Provider that validates environment but doesn't set variables.

```nix
{ pkgs, lib }:

requiredVars:  # List of variable names

pkgs.writeScriptBin "env-provider-required" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  REQUIRED_VARS=(${lib.concatMapStringsSep " " lib.escapeShellArg requiredVars})
  MISSING=()
  
  # Check each required variable
  for var in "''${REQUIRED_VARS[@]}"; do
    if [ -z "''${!var+x}" ]; then
      MISSING+=("$var")
    fi
  done
  
  # Report missing variables
  if [ ''${#MISSING[@]} -gt 0 ]; then
    echo "Error: Required environment variables not set:" >&2
    printf '  - %s\n' "''${MISSING[@]}" >&2
    exit 1
  fi
  
  # Success - no output
  exit 0
''
```

**Characteristics:**
- Takes list of variable names
- No `passthru.allSecrets` (doesn't provide variables)
- Exits with error if validation fails
- Outputs nothing on success

**Usage:**
```nix
envProviders = [
  (envProviders.required [ "API_KEY" "DATABASE_URL" ])
];
```

---

## Naming Conventions

### File Names

- **Lowercase with hyphens**: `file.nix`, `sops.nix`, `static.nix`
- **Descriptive**: Name should indicate data source or purpose
- **Short**: Single word when possible

Examples:
- ✅ `file.nix` - loads from file
- ✅ `sops.nix` - SOPS decryption
- ✅ `vault.nix` - HashiCorp Vault
- ❌ `file-env-provider.nix` - too verbose

### Script Names

The derivation name should match the pattern: `env-provider-{name}`

```nix
pkgs.writeScriptBin "env-provider-file" ''
  # ... implementation
''
```

**Rules:**
- Prefix: `env-provider-`
- Suffix: lowercase name matching file (without `.nix`)
- Examples: `env-provider-static`, `env-provider-sops`, `env-provider-vault`

### Export Names (in default.nix)

```nix
{
  file = import ./file.nix { inherit pkgs lib; };
  sops = import ./sops.nix { inherit pkgs lib; };
  static = import ./static.nix { inherit pkgs lib; };
}
```

**Rules:**
- camelCase for multi-word names
- Match the file name (without `.nix`)
- Descriptive of data source

---

## Output Contract

### Required Format

Every provider MUST output bash `export` statements:

```bash
export KEY1=value1
export KEY2=value2
export KEY3='value with spaces'
```

### Shell Escaping

**CRITICAL**: All values MUST be properly escaped to prevent injection and handle special characters.

#### Method 1: Double Escaping (Nix + Bash)

Used when value is known at Nix build time:

```nix
# Double escape: once for Nix string, once for bash value
"printf 'export %s=%s\\n' ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.escapeShellArg (toString value))}"
```

**Example:**
```nix
# Input: { API_KEY = "secret'with\"quotes"; }
# Output: export API_KEY='secret'\''with"quotes'
```

#### Method 2: Runtime Escaping (Bash only)

Used when value is read at runtime:

```bash
# Bash printf with %q for automatic escaping
printf 'export %s=%s\n' "$key" "$(printf '%q' "$value")"
```

**Example:**
```bash
# Input: value="with spaces and $vars"
# Output: export KEY=with\ spaces\ and\ \$vars
```

#### Method 3: Tool-Based Escaping (jq/yq)

Used when transforming structured data:

```bash
# jq with @sh filter for shell escaping
jq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'

# yq with @sh filter
yq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
```

### Output Validation

Providers should validate:
1. **Key format**: Must match `[A-Za-z_][A-Za-z0-9_]*`
2. **No empty keys**: Skip or error on empty variable names
3. **No conflicts**: Each key should appear only once

```nix
# Validate key name in Nix
assert lib.assertMsg 
  (builtins.match "[A-Za-z_][A-Za-z0-9_]*" key != null)
  "Invalid environment variable name: ${key}";
```

```bash
# Validate key name in Bash
if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
  key="''${BASH_REMATCH[1]}"
  # ... process value
fi
```

---

## Security & Secrets

### The `passthru.allSecrets` Metadata

Every provider that OUTPUTS variables MUST include secrets metadata:

```nix
pkgs.writeScriptBin "..." ''
  # ... script
'' // {
  passthru.allSecrets = true;  # or false
}
```

**Rules:**
1. **`true`** - ALL variables from this provider are secrets (e.g., SOPS, Vault)
2. **`false`** - NO variables are secrets (e.g., static config)
3. **Omit** - Only for validation providers that don't output variables

### When to Mark as Secrets

```nix
# ✅ Secrets = true
envProviders.sops { ... }           # Encrypted data
envProviders.vault { ... }          # Vault secrets
envProviders.onePassword { ... }    # Password manager

# ✅ Secrets = false  
envProviders.static { ... }         # Hardcoded config
envProviders.file {                 # Public config file
  path = "config.env";
  secrets = false;
}

# ⚠️ Configurable
envProviders.file {                 # Could be secrets
  path = ".env.local";
  secrets = true;  # User decides
}
```

### Secrets Best Practices

1. **Never log secret values**
   ```bash
   # ❌ BAD
   echo "API_KEY=$API_KEY"
   
   # ✅ GOOD
   echo "API_KEY is set"
   ```

2. **Fail fast on missing secrets**
   ```bash
   # Secrets are usually required=true by default
   if [ ! -f "$SECRETS_FILE" ]; then
     echo "Error: Secrets file not found" >&2
     exit 1
   fi
   ```

3. **Use secure tools**
   ```bash
   # Suppress stderr from decryption tools to avoid leaks
   ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null
   ```

---

## Error Handling

### The `required` Parameter

File-based providers should support optional loading:

```nix
{ path, required ? false, ... }:
```

**Implementation:**
```bash
if [ ! -f "$FILE" ]; then
  ${if required then ''
    echo "Error: Required env file not found: $FILE" >&2
    exit 1
  '' else ''
    # Silent success - file optional
    exit 0
  ''}
fi
```

**Defaults:**
- `required = false` - For general config files (`.env`)
- `required = true` - For secrets providers (SOPS, Vault)

### Error Messages

All errors should:
1. Write to stderr (`>&2`)
2. Include provider name or file path
3. Explain what went wrong
4. Exit with non-zero status

```bash
# ✅ GOOD - Descriptive error
echo "Error: Required SOPS file not found: $FILE" >&2
exit 1

# ✅ GOOD - Tool not available
echo "Error: SOPS CLI not available" >&2
exit 1

# ❌ BAD - Generic error
echo "Error" >&2
exit 1
```

### Prerequisite Validation

Validate external dependencies early:

```bash
# Check if required tool is available
if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
  echo "Error: SOPS CLI not available" >&2
  exit 1
fi
```

### Bash Safety

Always use bash safety flags:

```bash
#!/usr/bin/env bash
set -euo pipefail
#   │││ └─ Fail on pipe errors
#   ││└─── Fail on undefined variables
#   │└──── Fail on command errors
#   └───── Exit on error
```

---

## Examples

### Example 1: Static Config Provider

```nix
# lib/env-providers/static.nix
{ pkgs, lib }:

# Static Environment Provider
#
# Provides hardcoded environment variables known at build time.
# Values are embedded in the generated script.
#
# Parameters:
#   - env (attrset): Key-value pairs of environment variables
#
# Usage:
#   envProviders.static { NODE_ENV = "production"; API_VERSION = "v1"; }
#
# Example:
#   envProviders = [
#     (envProviders.static {
#       NODE_ENV = "production";
#       LOG_LEVEL = "info";
#       FEATURE_FLAGS = "feature1,feature2";
#     })
#   ];

env:

assert lib.assertMsg (builtins.isAttrs env)
  "static env must be an attribute set";

pkgs.writeScriptBin "env-provider-static" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # Output all static environment variables as exports
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (key: value:
      # Validate key name (must be valid bash variable name)
      assert lib.assertMsg 
        (builtins.match "[A-Za-z_][A-Za-z0-9_]*" key != null)
        "Invalid environment variable name: ${key} (must match [A-Za-z_][A-Za-z0-9_]*)";
      
      "printf 'export %s=%s\\n' ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.escapeShellArg (toString value))}"
    ) env
  )}
'' // {
  # Metadata: Static values are NOT secrets by default
  passthru.allSecrets = false;
}
```

---

### Example 2: File Provider with Options

```nix
# lib/env-providers/file.nix
{ pkgs, lib }:

# File Environment Provider
#
# Loads environment variables from a .env file at runtime.
# Supports standard .env format: KEY=VALUE
#
# Parameters:
#   - path (string): Path to .env file
#   - required (bool): Fail if file not found [default: false]
#   - secrets (bool): Mark all values as secrets [default: false]
#
# File format:
#   - KEY=VALUE (one per line)
#   - Comments start with #
#   - Empty lines ignored
#   - Supports quoted values: KEY="value" or KEY='value'
#
# Usage:
#   envProviders.file { path = ".env"; }
#
# Example:
#   envProviders = [
#     # Optional config file
#     (envProviders.file {
#       path = ".env";
#       required = false;
#       secrets = false;
#     })
#     
#     # Required secrets file
#     (envProviders.file {
#       path = ".env.secrets";
#       required = true;
#       secrets = true;
#     })
#   ];

{ path
, required ? false
, secrets ? false
}:

pkgs.writeScriptBin "env-provider-file" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${path}"
  
  # Check if file exists
  if [ ! -f "$FILE" ]; then
    ${if required then ''
      echo "Error: Required env file not found: $FILE" >&2
      exit 1
    '' else ''
      # File not found but not required - silent success
      exit 0
    ''}
  fi
  
  # Read file and output exports
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    [[ -z "$line" ]] && continue
    
    # Skip comments (lines starting with # after optional whitespace)
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Parse KEY=VALUE format
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="''${BASH_REMATCH[1]}"
      value="''${BASH_REMATCH[2]}"
      
      # Remove surrounding quotes if present (both single and double)
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        # Double quotes
        value="''${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        # Single quotes
        value="''${BASH_REMATCH[1]}"
      fi
      
      # Output export statement with proper escaping
      printf 'export %s=%s\n' "$key" "$(printf '%q' "$value")"
    fi
  done < "$FILE"
'' // {
  passthru.allSecrets = secrets;
}
```

---

### Example 3: SOPS Decryption Provider

```nix
# lib/env-providers/sops.nix
{ pkgs, lib }:

# SOPS Environment Provider
#
# Decrypts SOPS-encrypted files and provides environment variables.
# Supports YAML, JSON, and dotenv formats.
#
# Parameters:
#   - file (string): Path to encrypted SOPS file
#   - format (string): File format - "yaml", "json", or "dotenv" [default: "yaml"]
#   - required (bool): Fail if file not found [default: true]
#
# Dependencies:
#   - sops CLI
#   - yq (for YAML format)
#   - jq (for JSON format)
#
# Usage:
#   envProviders.sops { file = "secrets.enc.yaml"; }
#
# Example:
#   envProviders = [
#     # YAML secrets
#     (envProviders.sops {
#       file = "secrets.yaml";
#       format = "yaml";
#     })
#     
#     # JSON secrets
#     (envProviders.sops {
#       file = "secrets.json";
#       format = "json";
#     })
#     
#     # Dotenv secrets (optional)
#     (envProviders.sops {
#       file = ".env.encrypted";
#       format = "dotenv";
#       required = false;
#     })
#   ];

{ file
, format ? "yaml"
, required ? true
}:

assert lib.assertMsg (builtins.elem format ["yaml" "json" "dotenv"])
  "SOPS format must be one of: yaml, json, dotenv (got: ${format})";

pkgs.writeScriptBin "env-provider-sops" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${file}"
  FORMAT="${format}"
  
  # Check if file exists
  if [ ! -f "$FILE" ]; then
    ${if required then ''
      echo "Error: Required SOPS file not found: $FILE" >&2
      exit 1
    '' else ''
      exit 0
    ''}
  fi
  
  # Check if sops is available
  if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
    echo "Error: SOPS CLI not available" >&2
    exit 1
  fi
  
  # Decrypt and convert to exports based on format
  case "$FORMAT" in
    yaml)
      # Decrypt YAML and convert to exports
      if ! command -v ${pkgs.yq}/bin/yq >/dev/null 2>&1; then
        echo "Error: yq not available (required for YAML format)" >&2
        exit 1
      fi
      
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | \
        ${pkgs.yq}/bin/yq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
      ;;
      
    json)
      # Decrypt JSON and convert to exports
      if ! command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
        echo "Error: jq not available (required for JSON format)" >&2
        exit 1
      fi
      
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | \
        ${pkgs.jq}/bin/jq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
      ;;
      
    dotenv)
      # Decrypt dotenv format and output exports
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse KEY=VALUE
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
          key="''${BASH_REMATCH[1]}"
          value="''${BASH_REMATCH[2]}"
          
          # Remove quotes if present
          if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
            value="''${BASH_REMATCH[1]}"
          fi
          
          # Output export with proper escaping
          printf 'export %s=%s\n' "$key" "$(printf '%q' "$value")"
        fi
      done
      ;;
      
    *)
      echo "Error: Unknown SOPS format: $FORMAT" >&2
      exit 1
      ;;
  esac
'' // {
  # Metadata: All variables from SOPS are secrets
  passthru.allSecrets = true;
}
```

---

### Example 4: Validation Provider

```nix
# lib/env-providers/required.nix
{ pkgs, lib }:

# Required Variables Validator
#
# Validates that required environment variables are set.
# Does NOT set any variables - only validates.
#
# Parameters:
#   - requiredVars (list of strings): Variable names that must be set
#
# Usage:
#   envProviders.required [ "API_KEY" "DATABASE_URL" ]
#
# Example:
#   envProviders = [
#     # Load from file first
#     (envProviders.file { path = ".env"; })
#     
#     # Then validate required vars are present
#     (envProviders.required [
#       "DATABASE_URL"
#       "API_KEY"
#       "SECRET_KEY"
#     ])
#   ];
#
# Note:
#   Place AFTER other providers in the list, as it validates
#   variables set by previous providers.

requiredVars:

assert lib.assertMsg (builtins.isList requiredVars)
  "required must be a list of variable names";
assert lib.assertMsg (builtins.all builtins.isString requiredVars)
  "All required variable names must be strings";

pkgs.writeScriptBin "env-provider-required" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # List of required variables
  REQUIRED_VARS=(${lib.concatMapStringsSep " " lib.escapeShellArg requiredVars})
  MISSING=()
  
  # Check each required variable
  for var in "''${REQUIRED_VARS[@]}"; do
    if [ -z "''${!var+x}" ]; then
      MISSING+=("$var")
    fi
  done
  
  # Report missing variables
  if [ ''${#MISSING[@]} -gt 0 ]; then
    echo "Error: Required environment variables not set:" >&2
    printf '  - %s\n' "''${MISSING[@]}" >&2
    exit 1
  fi
  
  # All required variables present - output nothing (success)
  # This provider only validates, doesn't set variables
  exit 0
''
# Note: No passthru.allSecrets - this provider doesn't output variables
```

---

## Testing

### Manual Testing

Create a test script to verify provider output:

```bash
#!/usr/bin/env bash

# Build the provider
PROVIDER=$(nix-build -E '
  let
    pkgs = import <nixpkgs> {};
    lib = pkgs.lib;
    provider = import ./lib/env-providers/static.nix { inherit pkgs lib; };
  in
    provider { API_KEY = "test123"; NODE_ENV = "production"; }
')

# Run and check output
echo "=== Provider Output ==="
$PROVIDER/bin/env-provider-static

# Test in a shell
echo -e "\n=== Testing in Shell ==="
eval "$($PROVIDER/bin/env-provider-static)"
echo "API_KEY=$API_KEY"
echo "NODE_ENV=$NODE_ENV"
```

### Integration Testing

Create a workflow that uses the provider:

```nix
# examples/test-env-provider.nix
{ nixactions, pkgs }:

nixactions.mkWorkflow {
  name = "test-env-provider";
  
  jobs.test = {
    executor = nixactions.executors.local;
    
    envProviders = [
      (nixactions.envProviders.static {
        TEST_VAR = "hello";
      })
    ];
    
    actions = [
      {
        name = "check-env";
        bash = ''
          echo "TEST_VAR is: $TEST_VAR"
          [ "$TEST_VAR" = "hello" ] || exit 1
        '';
      }
    ];
  };
}
```

Build and run:
```bash
nix build .#example-test-env-provider
./result/bin/test-env-provider
```

### Escaping Tests

Test that your provider handles special characters:

```nix
# Test special characters
envProviders.static {
  SIMPLE = "hello";
  WITH_SPACES = "hello world";
  WITH_QUOTES = "it's a \"test\"";
  WITH_DOLLARS = "$HOME and $USER";
  WITH_NEWLINES = "line1\nline2";
  WITH_BACKSLASH = "path\\to\\file";
}
```

Expected output should properly escape all values.

---

## Common Patterns

### 1. Optional File Loading

```nix
{ path, required ? false, ... }:

pkgs.writeScriptBin "..." ''
  if [ ! -f "${path}" ]; then
    ${if required then ''
      echo "Error: Required file not found: ${path}" >&2
      exit 1
    '' else ''
      exit 0  # Silent success
    ''}
  fi
  
  # Process file...
''
```

### 2. Format-Based Processing

```nix
{ file, format ? "yaml", ... }:

pkgs.writeScriptBin "..." ''
  case "${format}" in
    yaml)
      # YAML processing
      ;;
    json)
      # JSON processing
      ;;
    *)
      echo "Error: Unknown format: ${format}" >&2
      exit 1
      ;;
  esac
''
```

### 3. Tool Availability Checking

```nix
pkgs.writeScriptBin "..." ''
  # Check if required tool is available
  if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
    echo "Error: SOPS not available" >&2
    exit 1
  fi
  
  # Use the tool...
''
```

### 4. Secrets Metadata

```nix
# Always secrets
'' // {
  passthru.allSecrets = true;
}

# Never secrets
'' // {
  passthru.allSecrets = false;
}

# Configurable
{ secrets ? false, ... }:
'' // {
  passthru.allSecrets = secrets;
}
```

---

## Anti-Patterns

### ❌ DON'T: Forget shell escaping

```nix
# BAD - Vulnerable to injection
"echo 'export KEY=${value}'"
```

### ✅ DO: Use proper escaping

```nix
# GOOD - Properly escaped
"printf 'export %s=%s\\n' ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.escapeShellArg (toString value))}"
```

---

### ❌ DON'T: Log secret values

```bash
# BAD - Leaks secrets to logs
echo "API_KEY=$API_KEY"
sops -d secrets.yaml  # Stderr goes to logs
```

### ✅ DO: Suppress sensitive output

```bash
# GOOD - No secret leaks
echo "API_KEY is set"
sops -d secrets.yaml 2>/dev/null
```

---

### ❌ DON'T: Hardcode paths

```nix
# BAD - Hardcoded path
pkgs.writeScriptBin "..." ''
  if ! command -v sops >/dev/null 2>&1; then
    exit 1
  fi
''
```

### ✅ DO: Use Nix package paths

```nix
# GOOD - Nix-managed path
pkgs.writeScriptBin "..." ''
  if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
    exit 1
  fi
''
```

---

### ❌ DON'T: Forget to validate input

```nix
# BAD - No validation
env:
pkgs.writeScriptBin "..." ''
  # Process env...
''
```

### ✅ DO: Validate early

```nix
# GOOD - Validate at Nix evaluation time
env:

assert lib.assertMsg (builtins.isAttrs env)
  "env must be an attribute set";

pkgs.writeScriptBin "..." ''
  # Process env...
''
```

---

### ❌ DON'T: Mix provider responsibilities

```nix
# BAD - Provider both loads AND validates
pkgs.writeScriptBin "..." ''
  # Load from file
  source .env
  
  # Validate required vars
  if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY not set"
    exit 1
  fi
''
```

### ✅ DO: Separate concerns

```nix
# GOOD - Use two providers
envProviders = [
  (envProviders.file { path = ".env"; })
  (envProviders.required [ "API_KEY" ])
]
```

---

## Checklist

Before submitting a new provider, ensure:

- [ ] File name is lowercase and descriptive
- [ ] Script name follows `env-provider-{name}` pattern
- [ ] Documentation header with usage examples
- [ ] Parameters documented with types and defaults
- [ ] Uses `pkgs.writeScriptBin` to create derivation
- [ ] Bash shebang and `set -euo pipefail`
- [ ] Outputs `export KEY=VALUE` statements
- [ ] Proper shell escaping for all values
- [ ] Includes `passthru.allSecrets` if outputs variables
- [ ] Error messages write to stderr
- [ ] `required` parameter for optional files
- [ ] Tool availability checked before use
- [ ] Validates input at Nix evaluation time
- [ ] Tested manually with example workflow
- [ ] Added to `lib/env-providers/default.nix`

---

## Questions?

When in doubt:
1. Look at existing providers in `lib/env-providers/`
2. Follow the pattern most similar to your use case
3. Start simple - Pattern 1 or 2
4. Add complexity only when needed

**Key principles:**
- Single responsibility
- Secure by default  
- Composable
- Fail-safe

Remember: **Providers should do ONE thing well and be composable with others.**
