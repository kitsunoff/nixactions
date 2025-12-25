# NixActions Library Structure

This document provides an overview of the NixActions library organization.

## Directory Structure

```
lib/
├── actions/           # Reusable action library
│   ├── STYLE_GUIDE.md # Actions development guidelines
│   ├── default.nix    # Actions exports
│   ├── checkout.nix
│   ├── npm.nix
│   ├── nix-shell.nix
│   └── ...            # More actions
│
├── jobs/              # Reusable job templates
│   ├── STYLE_GUIDE.md # Jobs development guidelines
│   └── default.nix    # Jobs exports (TODO: add templates)
│
├── executors/         # Execution environments
│   ├── default.nix
│   ├── local.nix
│   ├── oci.nix
│   ├── action-runner.nix
│   ├── local-helpers.nix
│   ├── oci-helpers.nix
│   └── ...
│
├── default.nix        # Main library entry point
├── mk-executor.nix    # Executor constructor
├── mk-workflow.nix    # Workflow compiler
├── mk-matrix-jobs.nix # Matrix builds support
├── logging.nix        # Logging utilities
├── retry.nix          # Retry logic
└── runtime-helpers.nix # Runtime workflow functions
```

## Component Hierarchy

```
User Workflow Definition
         ↓
    mkWorkflow
         ↓
    ┌────┴────┐
    │  Jobs   │ ← Job Templates (lib/jobs/)
    └────┬────┘
         ↓
    ┌─────────┐
    │ Actions │ ← Action Library (lib/actions/)
    └────┬────┘
         ↓
    ┌──────────┐
    │ Executor │ ← Executors (lib/executors/)
    └──────────┘
         ↓
    Bash Script
```

## Development Flow

### 1. Creating New Actions

See: `lib/actions/STYLE_GUIDE.md`

**Quick checklist:**
- [ ] Create `lib/actions/my-action.nix`
- [ ] Follow one of the 5 API patterns
- [ ] Add documentation header
- [ ] Export from `lib/actions/default.nix`
- [ ] Test with example workflow
- [ ] Run `./scripts/compile-examples.sh`

### 2. Creating New Job Templates

See: `lib/jobs/STYLE_GUIDE.md`

**Quick checklist:**
- [ ] Create `lib/jobs/my-job.nix`
- [ ] Follow job template patterns
- [ ] Add comprehensive documentation
- [ ] Export from `lib/jobs/default.nix`
- [ ] Test with example workflow
- [ ] Run `./scripts/compile-examples.sh`

### 3. Creating New Executors

**Quick checklist:**
- [ ] Create `lib/executors/my-executor.nix`
- [ ] Use `mkExecutor` constructor
- [ ] Implement required functions (see existing executors)
- [ ] Export from `lib/executors/default.nix`
- [ ] Test with simple workflow

## API Overview

### Actions API

```nix
# Pattern 1: Zero-config action
actions.checkout

# Pattern 2: Simple parameter
(actions.nixShell [ "curl" "jq" ])

# Pattern 3: Named parameters
(actions.dockerBuild {
  registry = "myregistry.io/app";
  tag = "v1.0";
})

# Pattern 4: Composable (returns list)
actions = [
  actions.checkout
] ++ (actions.buildImages {
  registry = "myregistry.io";
  images = [ { name = "api"; } ];
});
```

### Jobs API

```nix
# Simple job template
jobs.myJob = (jobs.nodeCI {
  nodeVersion = "20";
}) // {
  executor = executors.local;
};

# Multi-job pipeline
jobs = (jobs.dockerPipeline {
  registry = "myregistry.io";
  images = [ { name = "app"; } ];
}) // {
  build.executor = executors.local;
  test.executor = executors.local;
  push.executor = executors.local;
};
```

### Executors API

```nix
# Local executor
executor = executors.local;

# OCI executor (mount mode)
executor = executors.oci { 
  image = "nixos/nix"; 
  mode = "mount"; 
};

# OCI executor (build mode)
executor = executors.oci { 
  image = "alpine:latest"; 
  mode = "build"; 
};
```

## Key Concepts

### Actions
- **Atomic units** of work
- **Reusable** across jobs and workflows
- **Self-contained** with dependencies
- Examples: checkout, npm-install, docker-build

### Jobs
- **Collections of actions** that run together
- **Reusable templates** for common workflows
- **Executor-agnostic** (user specifies executor)
- Examples: Node.js CI, Docker pipeline, Deploy workflow

### Executors
- **Where** jobs run
- **Isolated environments** (local, container, remote)
- **Abstract runtime** details from jobs/actions

### Workflows
- **Top-level** orchestration
- **Defines jobs** and their dependencies
- **Compiled to bash** scripts

## Next Steps

1. **Implement your first action** following `lib/actions/STYLE_GUIDE.md`
2. **Create job templates** following `lib/jobs/STYLE_GUIDE.md`
3. **Test with examples** in `examples/`
4. **Compile and verify** with `./scripts/compile-examples.sh`

## Questions?

- Actions: See `lib/actions/STYLE_GUIDE.md`
- Jobs: See `lib/jobs/STYLE_GUIDE.md`
- Executors: Look at existing implementations
- Workflows: Check examples in `examples/`
