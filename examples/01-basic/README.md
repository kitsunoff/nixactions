# Basic Examples

Core workflow patterns and fundamental concepts.

## Examples

### `simple.nix`
**Most basic workflow** - single job with simple actions.

```bash
nix run ..#example-simple
```

**What it demonstrates:**
- Basic workflow structure
- Single job execution
- Simple actions (checkout, greet, system-info)

---

### `parallel.nix`
**Parallel job execution** with dependency graph.

```bash
nix run ..#example-parallel
```

**What it demonstrates:**
- Jobs running in parallel (Level 0)
- Sequential dependencies via `needs`
- Multi-level execution (3 levels)
- DAG-based job ordering

---

### `env-sharing.nix`
**Environment variable sharing** between actions using JOB_ENV.

```bash
nix run ..#example-env-sharing
```

**What it demonstrates:**
- Actions writing to `$JOB_ENV`
- Actions reading from `$JOB_ENV`
- Variable persistence across actions
- Multi-step calculations with shared state
- Artifacts usage with build metadata

**Key pattern:**
```nix
{
  bash = ''
    echo "VERSION=1.2.3" >> "$JOB_ENV"
  '';
}
# Next action can use $VERSION
```

---

## Start Here

If you're new to NixActions, start with these examples in order:

1. **simple.nix** - Understand basic structure
2. **env-sharing.nix** - Learn action communication
3. **parallel.nix** - Understand parallelism and dependencies
