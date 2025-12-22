# Feature Examples

Advanced features and specific capabilities.

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
- Secrets validation with `requireEnv`
- Integration patterns for 6 secret managers:
  - SOPS
  - HashiCorp Vault
  - 1Password
  - Age encryption
  - Bitwarden
  - Environment variables

**Note:** Examples show integration patterns, actual secret files not included.

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

## Feature Matrix

| Feature | Example |
|---------|---------|
| Action conditions | test-action-conditions.nix |
| Artifacts | artifacts-simple.nix, artifacts-paths.nix |
| Secrets | secrets.nix |
| Dynamic packages | nix-shell.nix |
| Multiple executors | multi-executor.nix |
| Environment variables | test-env.nix |
| Job isolation | test-isolation.nix |
