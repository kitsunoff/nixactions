# Comparison

How NixActions compares to other CI/CD solutions.

---

## vs GitHub Actions

| Feature | GitHub Actions | NixActions |
|---------|---------------|------------|
| **Execution model** | Parallel + needs | Same |
| **Dependencies** | `needs: [...]` | Same |
| **Conditions** | `if: success()` etc | Same (`condition`) |
| **Step conditions** | `steps[].if` | Same (`actions[].condition`) |
| **Continue on error** | `continue-on-error` | Same (`continueOnError`) |
| **Actions** | JavaScript/Docker | Nix derivations |
| **Configuration** | YAML | Nix DSL (composable) |
| **Environment** | Container images | Nix derivations (hermetic) |
| **Dependencies mgmt** | Cached layers | Nix store (content-addressed) |
| **Composition** | Reusable workflows | Nix functions |
| **Infrastructure** | GitHub.com | None (agentless) |
| **Local execution** | `act` (partial compat) | Native `nix run` |
| **Test without push** | Must push to repo | `nix run .#ci` locally |
| **Build environments** | Variable (network, time) | Reproducible (Nix store) |
| **Cost** | $21/month+ | $0 |

### Example Comparison

**GitHub Actions:**
```yaml
name: CI
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm test
  
  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: deploy.sh
```

**NixActions:**
```nix
platform.mkWorkflow {
  name = "ci";
  
  jobs = {
    test = {
      executor = platform.executors.local;
      actions = [
        { bash = "npm test"; deps = [ pkgs.nodejs ]; }
      ];
    };
    
    deploy = {
      needs = [ "test" ];
      condition = ''[ "$GITHUB_REF" = "refs/heads/main" ]'';
      executor = platform.executors.local;
      actions = [
        { bash = "deploy.sh"; }
      ];
    };
  };
}
```

---

## vs GitLab CI

| Feature | GitLab CI | NixActions |
|---------|----------|------------|
| **Execution** | Sequential by default | Parallel by default |
| **Configuration** | YAML | Nix DSL |
| **Infrastructure** | GitLab instance | None |
| **Local testing** | Limited | Native |
| **Test without push** | Must push | Local `nix run` |
| **Runners** | Requires registration | Agentless |

### Example Comparison

**GitLab CI:**
```yaml
stages:
  - test
  - deploy

test:
  stage: test
  script:
    - npm test

deploy:
  stage: deploy
  script:
    - deploy.sh
  only:
    - main
```

**NixActions:**
```nix
platform.mkWorkflow {
  name = "ci";
  
  jobs = {
    test = {
      executor = platform.executors.local;
      actions = [{ bash = "npm test"; }];
    };
    
    deploy = {
      needs = [ "test" ];
      condition = ''[ "$BRANCH" = "main" ]'';
      executor = platform.executors.local;
      actions = [{ bash = "deploy.sh"; }];
    };
  };
}
```

---

## vs Jenkins

| Feature | Jenkins | NixActions |
|---------|---------|------------|
| **Configuration** | Groovy/GUI | Nix |
| **Infrastructure** | Jenkins server | None |
| **Plugins** | 1800+ plugins | Nix packages |
| **Maintenance** | High | None |
| **Local testing** | Difficult | Native |
| **Reproducibility** | Variable | Guaranteed |

---

## vs CircleCI

| Feature | CircleCI | NixActions |
|---------|----------|------------|
| **Configuration** | YAML | Nix |
| **Orbs** | Marketplace | Nix functions |
| **Local testing** | CLI tool | Native `nix run` |
| **Infrastructure** | circleci.com | None |
| **Cost** | Usage-based | $0 |

---

## What NixActions Does Better

### 1. Local-First Development

```bash
# Test your CI locally before pushing
$ nix run .#ci

# No more "fix CI" commits
```

### 2. Reproducible Environments

```nix
# Same derivation = same environment everywhere
deps = [ pkgs.nodejs_20 pkgs.git pkgs.curl ]
```

### 3. Composability

```nix
# Reuse as functions, not copy-paste
let
  commonTest = {
    bash = "npm test";
    deps = [ pkgs.nodejs ];
    retry = { max_attempts = 3; };
  };
in {
  jobs = {
    test-unit = { actions = [ (commonTest // { bash = "npm run test:unit"; }) ]; };
    test-e2e = { actions = [ (commonTest // { bash = "npm run test:e2e"; }) ]; };
  };
}
```

### 4. No Infrastructure

```bash
# Run anywhere with Nix
$ nix run .#ci                    # Local
$ ssh server < result             # Remote
$ kubectl exec pod -- /workflow   # K8s
```

### 5. Build-Time Validation

```bash
$ nix build .#ci
error: builder for '/nix/store/xxx-test.drv' failed
# Catch errors before runtime
```

---

## What NixActions Doesn't Do

### No Marketplace

GitHub Actions has 1000s of marketplace actions. NixActions relies on:
- Nix packages (80,000+)
- Custom actions (Nix derivations)
- Standard library

### No Native Integration

No built-in integration with GitHub/GitLab. You need to:
- Run workflows manually or via cron
- Set up your own triggering mechanism
- Handle notifications yourself

### Learning Curve

Nix has a steeper learning curve than YAML:
```nix
# Nix syntax
{ pkgs, ... }: { bash = "npm test"; deps = [ pkgs.nodejs ]; }

# vs YAML
run: npm test
```

---

## When to Choose NixActions

### Good Fit

- Already using Nix/NixOS
- Need reproducible builds
- Want local CI testing
- Complex build pipelines
- Self-hosted infrastructure
- Cost-sensitive

### Stick with GitHub Actions

- Quick prototype projects
- Team unfamiliar with Nix
- Heavy reliance on marketplace actions
- Simple single-step builds
- Need native GitHub integration

---

## Migration Path

### From GitHub Actions

1. Map `jobs` -> `jobs`
2. Map `steps` -> `actions`
3. Map `needs` -> `needs`
4. Map `if` -> `condition`
5. Replace `uses` with Nix derivations

### From GitLab CI

1. Map `stages` to dependency graph via `needs`
2. Map `script` -> `actions`
3. Map `only/except` -> `condition`

---

## See Also

- [Philosophy](./philosophy.md) - Why NixActions
- [User Guide](./user-guide.md) - Getting started
- [Architecture](./architecture.md) - How it works
