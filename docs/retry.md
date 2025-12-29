# Retry Mechanism

Automatic retry for failed jobs and actions with configurable backoff strategies.

---

## Overview

**Key features:**
- Three-level configuration hierarchy: workflow -> job -> action
- Three backoff strategies: exponential (default), linear, constant
- Configurable min_time/max_time delays
- Actions = Derivations (retry logic injected at runtime)

---

## Configuration

```nix
retry = {
  max_attempts = 3;           # Total attempts (1 = no retry)
  backoff = "exponential";    # "exponential" | "linear" | "constant"
  min_time = 1;               # Minimum delay between retries (seconds)
  max_time = 60;              # Maximum delay between retries (seconds)
}
```

### Defaults

```nix
{
  max_attempts = 1;        # No retry by default
  backoff = "exponential"; # Exponential if retry enabled
  min_time = 1;            # 1 second minimum
  max_time = 60;           # 60 seconds maximum
}
```

---

## Configuration Levels

Priority: action > job > workflow

```nix
nixactions.mkWorkflow {
  name = "ci";
  
  # Level 1: Workflow-level (applies to ALL jobs)
  retry = {
    max_attempts = 2;
    backoff = "exponential";
  };
  
  jobs = {
    test = {
      # Level 2: Job-level (overrides workflow)
      retry = {
        max_attempts = 3;
        backoff = "linear";
      };
      
      actions = [
        {
          name = "flaky-test";
          bash = "npm test";
          
          # Level 3: Action-level (highest priority)
          retry = {
            max_attempts = 5;
            backoff = "exponential";
          };
        }
        
        {
          name = "unit-tests";
          bash = "npm run unit";
          # No action-level retry -> inherits from job
        }
      ];
    };
    
    deploy = {
      # Disable retry for this job
      retry = null;
      
      actions = [{
        bash = "kubectl apply -f prod/";
        # No retry even if workflow-level is set
      }];
    };
  };
}
```

---

## Backoff Strategies

### Exponential (Default)

**Formula:** `delay = min(max_time, min_time * 2^(attempt-1))`

**Example** (min_time=1, max_time=60):
```
Attempt 1 -> delay 1s   (1 * 2^0 = 1)
Attempt 2 -> delay 2s   (1 * 2^1 = 2)
Attempt 3 -> delay 4s   (1 * 2^2 = 4)
Attempt 4 -> delay 8s   (1 * 2^3 = 8)
Attempt 5 -> delay 16s  (1 * 2^4 = 16)
Attempt 6 -> delay 32s  (1 * 2^5 = 32)
Attempt 7 -> delay 60s  (capped at max_time)
```

**Use case:** Network calls, API requests (prevents thundering herd)

### Linear

**Formula:** `delay = min(max_time, min_time * attempt)`

**Example** (min_time=2, max_time=60):
```
Attempt 1 -> delay 2s   (2 * 1 = 2)
Attempt 2 -> delay 4s   (2 * 2 = 4)
Attempt 3 -> delay 6s   (2 * 3 = 6)
Attempt 4 -> delay 8s   (2 * 4 = 8)
Attempt 5 -> delay 10s  (2 * 5 = 10)
```

**Use case:** Predictable retry intervals

### Constant

**Formula:** `delay = min_time`

**Example** (min_time=5):
```
Attempt 1 -> delay 5s
Attempt 2 -> delay 5s
Attempt 3 -> delay 5s
```

**Use case:** Simple polling, fixed retry intervals

---

## Usage Examples

### Basic Retry

```nix
{
  actions = [{
    name = "flaky-test";
    bash = "npm test";
    retry = {
      max_attempts = 3;
      backoff = "exponential";
      min_time = 1;
      max_time = 60;
    };
  }];
}
```

### Workflow-wide Retry

```nix
nixactions.mkWorkflow {
  name = "ci";
  
  retry = {
    max_attempts = 2;
    backoff = "exponential";
  };
  
  jobs = {
    test.actions = [{ bash = "npm test"; }];
    lint.actions = [{ bash = "npm run lint"; }];
    # Both inherit workflow-level retry
  };
}
```

### Selective Retry

```nix
{
  jobs = {
    test = {
      retry = {
        max_attempts = 3;
        backoff = "exponential";
      };
      
      actions = [
        { bash = "npm install"; }  # Retries enabled
        { bash = "npm test"; }     # Retries enabled
        {
          bash = "npm run deploy";
          retry = null;            # NO retry for deploy
        }
      ];
    };
  };
}
```

### Network Operations

```nix
{
  name = "fetch-data";
  bash = "curl -f https://api.example.com/data > data.json";
  retry = {
    max_attempts = 5;
    backoff = "exponential";
    min_time = 1;
    max_time = 30;
  };
}
```

### Database Connections

```nix
{
  name = "wait-for-db";
  bash = "pg_isready -h localhost -p 5432";
  retry = {
    max_attempts = 30;
    backoff = "constant";
    min_time = 2;
  };
}
```

---

## Structured Logging

### Retry Events

```
[2025-12-24T12:00:00Z] [workflow:ci] [job:test] [action:npm-install] [attempt:1/3] Starting
[2025-12-24T12:00:05Z] [workflow:ci] [job:test] [action:npm-install] [attempt:1/3] Failed (exit: 1)
[2025-12-24T12:00:05Z] [workflow:ci] [job:test] [action:npm-install] [retry] Waiting 1s (exponential)
[2025-12-24T12:00:06Z] [workflow:ci] [job:test] [action:npm-install] [attempt:2/3] Starting
[2025-12-24T12:00:08Z] [workflow:ci] [job:test] [action:npm-install] [attempt:2/3] Failed (exit: 1)
[2025-12-24T12:00:08Z] [workflow:ci] [job:test] [action:npm-install] [retry] Waiting 2s (exponential)
[2025-12-24T12:00:10Z] [workflow:ci] [job:test] [action:npm-install] [attempt:3/3] Starting
[2025-12-24T12:00:12Z] [workflow:ci] [job:test] [action:npm-install] [attempt:3/3] Success
```

### JSON Format

```json
{"timestamp":"2025-12-24T12:00:00Z","workflow":"ci","job":"test","action":"npm-install","event":"start","attempt":1,"max_attempts":3}
{"timestamp":"2025-12-24T12:00:05Z","workflow":"ci","job":"test","action":"npm-install","event":"failed","attempt":1,"exit_code":1}
{"timestamp":"2025-12-24T12:00:05Z","workflow":"ci","job":"test","action":"npm-install","event":"retry","next_attempt":2,"delay_seconds":1,"backoff":"exponential"}
{"timestamp":"2025-12-24T12:00:12Z","workflow":"ci","job":"test","action":"npm-install","event":"success","attempt":3,"duration_ms":1333}
```

---

## Edge Cases

### max_attempts = 1

```nix
retry = {
  max_attempts = 1;  # Single attempt, no retries
}
# Equivalent to: retry = null
```

### retry = null

```nix
retry = null;  # Explicitly disable retry
```

### Empty retry block

```nix
retry = {};  # Uses all defaults (max_attempts = 1 -> no retry)
```

---

## Implementation

Retry logic is implemented via bash functions:

```bash
retry_with_backoff() {
  local max_attempts=$1
  local backoff=$2
  local min_time=$3
  local max_time=$4
  shift 4
  
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      local delay=$(calculate_delay $attempt "$backoff" $min_time $max_time)
      sleep $delay
    fi
    
    attempt=$((attempt + 1))
  done
  
  return 1
}
```

---

## Testing

Comprehensive test suite in `examples/02-features/test-retry-comprehensive.nix`:

```bash
# Run tests
nix run .#test-retry-comprehensive
```

**Coverage:** 23/23 retry features (100%)
- Exponential backoff success
- Linear backoff success
- Constant backoff success
- Retry exhausted scenarios
- Max attempts = 1 (no retry)
- Retry = null (disabled)
- Workflow-level inheritance
- Job-level override
- Action-level override
- Timing verification

---

## See Also

- [Actions](./actions.md) - Action configuration
- [API Reference](./api-reference.md) - Full retry API
- [Conditions](./conditions.md) - Combine with conditional execution
