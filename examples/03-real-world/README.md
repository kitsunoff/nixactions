# Real-World Examples

Production-ready CI/CD pipelines for real projects.

## Examples

### `complete.nix`
**Full-featured CI/CD pipeline** with all the bells and whistles.

```bash
nix run ..#example-complete
```

**What it demonstrates:**
- Complete workflow from validation to deployment
- Parallel linting and validation (Level 0)
- Testing and building (Level 1-2)
- Conditional deployment (Level 3)
- Notifications (always runs)
- Cleanup (always runs)
- Job-level conditions
- Error handling with `continueOnError`

**Pipeline stages:**
1. **Validation** - lint-yaml, lint-json, lint-bash (parallel)
2. **Testing** - unit tests, integration tests (parallel)
3. **Building** - build application
4. **Deployment** - deploy to staging (conditional)
5. **Notifications** - notify-success, notify-failure (conditional)
6. **Cleanup** - always runs

---

### `python-ci.nix`
**Production Python CI/CD** - comprehensive testing and deployment.

```bash
nix run ..#example-python-ci
```

**What it demonstrates:**
- Real Python project structure
- Multiple test types:
  - Unit tests (pytest)
  - Linting (flake8)
  - Type checking (mypy)
  - Coverage reporting
- Docker image building
- Security scanning
- Deployment pipeline
- Artifacts (test reports, Docker images)

**Pipeline stages:**
1. **Setup** - checkout code
2. **Quality** - lint, type-check (parallel)
3. **Testing** - unit tests with coverage
4. **Building** - Docker image
5. **Deployment** - push to registry (conditional)

---

### `python-ci-simple.nix`
**Simplified Python CI** - minimal but functional.

```bash
nix run ..#example-python-ci-simple
```

**What it demonstrates:**
- Streamlined Python testing
- Essential checks only:
  - Unit tests
  - Linting
- Quick feedback loop
- Good starting point for small projects

**Use when:**
- Starting new Python project
- Want simple CI without complexity
- Don't need deployment yet

---

## Templates

Use these as templates for your projects:

### Python Project
Start with `python-ci-simple.nix`, add features as needed:
- Security → use `python-ci.nix` as reference
- Docker → add build + push stages
- Deployment → add deployment job with conditions

### Node.js Project
Adapt `complete.nix` structure:
- Replace Python tools with npm commands
- Keep parallel linting
- Keep test → build → deploy flow

### Generic CI/CD
Use `complete.nix` pattern:
- Parallel validation phase
- Sequential test → build → deploy
- Always-run notifications and cleanup
- Conditional deployment

---

## Best Practices

These examples follow production best practices:

1. **Parallel by default** - Run independent jobs simultaneously
2. **Fail fast** - Validation before expensive operations
3. **Conditional deployment** - Only deploy on success
4. **Always cleanup** - Use `always()` condition
5. **Always notify** - Stakeholders informed regardless of outcome
6. **Artifact everything** - Test reports, build outputs, logs
7. **Security first** - Secrets management, scanning
8. **Type safety** - Mypy, linters catch errors early

---

## Customization Guide

### Add Your Language

1. Copy `python-ci-simple.nix`
2. Replace Python tools with your language:
   ```nix
   # Python
   deps = [ pkgs.python311 pkgs.python311Packages.pytest ];
   
   # Node.js
   deps = [ pkgs.nodejs ];
   
   # Rust
   deps = [ pkgs.rustc pkgs.cargo ];
   
   # Go
   deps = [ pkgs.go ];
   ```
3. Update commands:
   ```nix
   # Python
   bash = "pytest";
   
   # Node.js
   bash = "npm test";
   
   # Rust
   bash = "cargo test";
   
   # Go
   bash = "go test ./...";
   ```

### Add Deployment

Use `complete.nix` pattern:

```nix
deploy = {
  needs = ["build"];
  condition = "success()";  # Only on success
  executor = platform.executors.ssh { host = "prod"; };
  actions = [
    { bash = "kubectl apply -f k8s/"; }
  ];
};
```

### Add Notifications

```nix
notify = {
  needs = ["deploy"];
  condition = "always()";  # Always notify
  actions = [{
    bash = ''
      curl -X POST $WEBHOOK_URL \
        -d '{"status": "completed"}'
    '';
  }];
};
```
