# Feature Examples

Advanced features and specific capabilities.

---

## Examples

### `test-action-conditions.nix`
**Action-level conditions** - control flow within jobs.

```bash
nix run ..#example-test-action-conditions
```

**What it demonstrates:**
- `success()` condition - run only if no failures
- `failure()` condition - run only after failures
- `always()` condition - always run (cleanup, notifications)
- Bash script conditions - custom logic
- `continue-on-error` for expected failures

**Test scenarios:**
- 5 jobs testing different condition types
- Sequential execution with dependencies
- Expected failures handled gracefully

---

### `retry.nix`
**Retry mechanism** - automatic retry on failures.

```bash
nix run ..#example-retry
```

**What it demonstrates:**
- Workflow/job/action-level retry configuration
- Three backoff strategies: exponential, linear, constant
- Configurable min/max delays
- Retry disabled (`retry = null`)
- Single attempt (`max_attempts = 1`)

**Example:**
```nix
retry = {
  max_attempts = 3;
  backoff = "exponential";  # "exponential" | "linear" | "constant"
  min_time = 1;             # seconds
  max_time = 60;            # seconds
};
```

---

### `artifacts-simple.nix`
**Basic artifact passing** between jobs.

```bash
nix run ..#example-artifacts-simple
```

**What it demonstrates:**
- `outputs` - declare artifacts to save
- `inputs` - declare artifacts to restore
- File transfer between jobs
- Artifact storage in `$NIXACTIONS_ARTIFACTS_DIR`

---

### `artifacts-paths.nix`
**Multiple artifacts** with different paths.

```bash
nix run ..#example-artifacts-paths
```

**What it demonstrates:**
- Multiple outputs per job
- Directory and file artifacts
- Path preservation
- Complex artifact graphs

---

### `secrets.nix`
**Secrets management** with multiple providers.

```bash
nix run ..#example-secrets
```

**What it demonstrates:**
- Workflow/job/action-level environment variables
- Runtime environment override
- Environment precedence
- Secrets validation with `envProviders.required`
- Integration with env-providers:
  - SOPS (encrypted files)
  - File (.env files)
  - Static (hardcoded values)
  - Required (validation)

**Note:** Uses env-providers for flexible secret management.

---

### `nix-shell.nix`
**Dynamic package loading** without modifying executors.

```bash
nix run ..#example-nix-shell
```

**What it demonstrates:**
- `platform.actions.nixShell` for on-demand packages
- Different tools per job
- Package scoping
- Tool composition

**Use case:** Add `curl`, `jq`, `ripgrep` only where needed.

---

### `multi-executor.nix`
**Multiple executors** in single workflow.

```bash
nix run ..#example-multi-executor
```

**What it demonstrates:**
- Different jobs using different executors
- Local executor for quick tasks
- Executor-specific configuration
- Mixed execution environments

---

### `test-env.nix`
**Environment variable propagation** testing.

```bash
nix run ..#example-test-env
```

**What it demonstrates:**
- Variables propagate between actions in same job
- Environment precedence (runtime > action > job > workflow)
- Validation that secrets work correctly

---

### `test-isolation.nix`
**Job isolation** testing.

```bash
nix run ..#example-test-isolation
```

**What it demonstrates:**
- Jobs run in isolated directories
- Environment variables don't leak between jobs
- Each job has clean state
- Workspace isolation

---

### `matrix-builds.nix`
**Compile-time matrix job generation** for testing across multiple configurations.

```bash
nix run ..#example-matrix-builds
```

**What it demonstrates:**
- `platform.mkMatrixJobs` - compile-time job generation
- Cartesian product of matrix dimensions
- Template functions with matrix variables
- `${{ matrix.var }}` syntax substitution
- Integration with artifacts, needs, executors
- Auto-generated job names

**Example:**
```nix
matrixJobs = platform.mkMatrixJobs {
  name = "test";
  matrix = {
    node = ["18" "20" "22"];
    os = ["ubuntu" "alpine"];
  };
  jobTemplate = { node, os }: {
    executor = platform.executors.oci { 
      image = "node:${node}-${os}"; 
    };
    actions = [{
      bash = "npm test";
    }];
  };
};
# Generates 6 jobs: test-node-18-os-ubuntu, test-node-18-os-alpine, etc.
```

**Use cases:**
- Cross-platform testing (multiple OSes, architectures)
- Multi-version testing (node, python, ruby versions)
- Build matrix (compilers, configurations)

---

### `structured-logging.nix`
**Structured logging formats** for better CI/CD observability.

```bash
nix run ..#example-structured-logging
```

**What it demonstrates:**
- Three log formats: structured (default), JSON, simple
- Timestamp with milliseconds
- Duration tracking per action
- Exit code reporting
- Runtime format override via `NIXACTIONS_LOG_FORMAT`

**Use cases:**
- Parsing logs with jq
- Integration with log aggregation systems
- Human-readable output for development

---

## Comprehensive Test Suite

### `test-retry-comprehensive.nix`

Tests all aspects of the retry mechanism (10 test jobs):

```bash
nix run ..#test-retry-comprehensive
```

**Tests Included:**
1. ✅ Exponential backoff (3 attempts, 1s → 2s delays)
2. ✅ Linear backoff (2 attempts, 1s → 2s delays)
3. ✅ Constant backoff (2 attempts, 2s delays)
4. ✅ Retry exhausted (all attempts fail)
5. ✅ No retry (`max_attempts = 1`)
6. ✅ Retry disabled (`retry = null`)
7. ✅ Max delay cap (delays capped at max_time)
8. ✅ Job-level retry inheritance
9. ✅ Action overrides job retry
10. ✅ Timing verification

**Expected:** All 10 jobs succeed, demonstrating all retry scenarios.

---

### `test-conditions-comprehensive.nix`

Tests all action condition types and bash expressions (10 test jobs):

```bash
nix run ..#test-conditions-comprehensive
```

**Tests Included:**
1. ✅ `success()` condition
2. ✅ `failure()` condition
3. ✅ `always()` condition
4. ✅ Bash environment conditions (`[ "$VAR" = "value" ]`)
5. ✅ Complex bash (numeric, pattern matching, file checks)
6. ✅ Logical AND/OR conditions
7. ✅ Command substitution in conditions
8. ✅ Mixed condition sequences
9. ✅ Empty/unset variable checks
10. ✅ Condition evaluation order

**Expected:** All 10 jobs succeed, various actions skip/run based on conditions.

---

## Test Coverage Summary

### Retry Mechanism (11/11 features):

| Feature | Tested |
|---------|--------|
| Exponential backoff | ✅ |
| Linear backoff | ✅ |
| Constant backoff | ✅ |
| Max delay cap | ✅ |
| Retry exhausted | ✅ |
| `max_attempts = 1` | ✅ |
| `retry = null` | ✅ |
| Job-level retry | ✅ |
| Action-level retry | ✅ |
| Override hierarchy | ✅ |
| Timing verification | ✅ |

### Conditions (12/12 features):

| Feature | Tested |
|---------|--------|
| `success()` | ✅ |
| `failure()` | ✅ |
| `always()` | ✅ |
| Bash string comparison | ✅ |
| Bash numeric comparison | ✅ |
| Bash pattern matching | ✅ |
| Bash file checks | ✅ |
| AND logic | ✅ |
| OR logic | ✅ |
| Command substitution | ✅ |
| Empty/unset variables | ✅ |
| Evaluation order | ✅ |

---

## Running All Tests

```bash
# Feature examples
nix run ..#example-test-action-conditions
nix run ..#example-retry
nix run ..#example-artifacts
nix run ..#example-matrix-builds
nix run ..#example-structured-logging

# Comprehensive test suites
nix run ..#test-retry-comprehensive
nix run ..#test-conditions-comprehensive
```

---

## Adding New Tests

To add new test cases:

1. Add new job to appropriate test file
2. Ensure job has clear test description
3. Use descriptive action names
4. Add expected behavior comments
5. Test edge cases
6. Verify in isolation first
7. Run full test suite

Example:

```nix
test-new-feature = {
  executor = platform.executors.local;
  needs = ["previous-test"];
  
  actions = [
    {
      name = "test-new-behavior";
      bash = ''
        echo "Testing new feature..."
        # Test implementation
      '';
      retry = {
        max_attempts = 3;
        backoff = "exponential";
        min_time = 1;
        max_time = 10;
      };
    }
  ];
};
```

---

## Feature Matrix

| Feature | Example | Test Suite |
|---------|---------|------------|
| Action conditions | test-action-conditions.nix | test-conditions-comprehensive.nix |
| Retry mechanism | retry.nix | test-retry-comprehensive.nix |
| Artifacts | artifacts-simple.nix, artifacts-paths.nix | - |
| Secrets | secrets.nix | - |
| Dynamic packages | nix-shell.nix | - |
| Multiple executors | multi-executor.nix | - |
| Environment variables | test-env.nix | - |
| Job isolation | test-isolation.nix | - |
| Matrix builds | matrix-builds.nix | - |
| Structured logging | structured-logging.nix | - |

---

## Known Limitations

1. **Timing Tests**: May be flaky on slow systems
2. **State Files**: Use `$WORKFLOW_ID` for uniqueness across parallel runs
3. **Exit Codes**: Failed tests use `continueOnError = true`

---

## Continuous Integration

These tests should be run:
- ✅ Before commits
- ✅ In CI/CD pipeline
- ✅ After refactoring
- ✅ When adding new features
