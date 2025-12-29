# Philosophy

## Core Principles

1. **Local-first** - CI should work locally first, remote is optional. No more "fix CI" commits.

2. **Agentless** - No persistent agents, no polling, no registration. Compile workflow, run anywhere.

3. **Deterministic** - Nix guarantees reproducible build environments. Same inputs = same derivations.

4. **Composable** - Everything is a function, everything composes. Reuse without copy-paste.

5. **Simple** - Minimal abstractions, maximum power. No YAML magic, just Nix.

6. **Parallel** - Jobs without dependencies run in parallel (like GitHub Actions).

7. **Build-time compilation** - Actions are derivations, provisioned once at build time.

---

## Design Philosophy

```
GitHub Actions execution model:
  + Parallel by default
  + Explicit dependencies (needs)
  + Conditional execution (condition)
  + DAG-based ordering

+ Nix reproducibility:
  + Deterministic builds
  + Self-contained
  + Composable DSL
  + Actions = Derivations

+ Agentless:
  + No infrastructure
  + Run anywhere
  + SSH/containers/local

= NixActions
```

---

## What NixActions Guarantees

### Reproducible

- **Workflow script compilation** - Same inputs produce the same `/nix/store` output
- **Build environments** - Exact dependency versions via Nix
- **Action derivations** - Cached, content-addressed

### Not Guaranteed (same as any CI)

- **Network call results** - `curl`, API responses
- **External service state** - Databases, deployments
- **Time-dependent operations** - Timestamps, random values

---

## Real Advantages

NixActions wins on its **actual merits**, not exaggerated claims:

1. **Local-first development** - Test CI locally before pushing, no more "fix CI" commits

2. **Evaluation-time composition** - Nix validates DSL structure and derivation graph

3. **Everything is a derivation** - Cacheable, reproducible build artifacts

4. **Agentless execution** - No infrastructure to maintain, runs anywhere with Nix

5. **Functional composition** - Reuse actions as Nix functions, not copy-paste YAML

---

## Anti-Patterns We Avoid

### YAML Configuration Hell

```yaml
# GitHub Actions - implicit, string-typed, error-prone
steps:
  - uses: actions/setup-node@v3
    with:
      node-version: '18'
  - run: npm test
```

```nix
# NixActions - explicit, typed, composable
steps = [
  (nixactions.actions.setupNode { version = "18"; })
  { bash = "npm test"; deps = [ pkgs.nodejs ]; }
];
```

### Agent Infrastructure

```
GitHub Actions:
  GitHub.com -> Runner Agent -> Execute

NixActions:
  nix run .#ci -> Execute (anywhere)
```

### "Works on my machine"

```
Traditional CI:
  Developer machine != CI environment

NixActions:
  Same Nix derivation = Same environment everywhere
```

---

## Trade-offs

### What You Give Up

- **Ecosystem** - GitHub Actions marketplace (1000s of actions)
- **Integration** - Native GitHub/GitLab integration
- **Familiarity** - YAML is everywhere, Nix has a learning curve

### What You Get

- **Control** - Full control over execution environment
- **Reproducibility** - Nix guarantees exact builds
- **Portability** - Run anywhere with Nix
- **Composability** - First-class functions, not string interpolation
- **Local testing** - Test CI without pushing

---

## When to Use NixActions

### Good Fit

- Already using Nix/NixOS
- Need reproducible builds
- Want local CI testing
- Complex build pipelines
- Self-hosted infrastructure

### Not Ideal

- Quick prototype projects
- Teams unfamiliar with Nix
- Heavy reliance on marketplace actions
- Simple single-step builds
