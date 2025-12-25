# NixActions - Jobs Library Style Guide

This document defines the coding standards and patterns for creating reusable job templates in NixActions.

## Table of Contents

1. [Philosophy](#philosophy)
2. [Job vs Action](#job-vs-action)
3. [Job Types](#job-types)
4. [API Patterns](#api-patterns)
5. [Naming Conventions](#naming-conventions)
6. [Structure](#structure)
7. [Documentation](#documentation)
8. [Examples](#examples)
9. [Testing](#testing)

---

## Philosophy

**Jobs are reusable, configurable workflow templates.**

Core principles:
- **Higher-level than actions** - Jobs orchestrate multiple actions
- **Executor-agnostic** - Should work with any executor (with sensible defaults)
- **Configurable** - Accept parameters for customization
- **Complete workflows** - Include all necessary setup, execution, and cleanup
- **Production-ready** - Include error handling, retry, conditions
- **Well-documented** - Clear usage examples and parameters

---

## Job vs Action

| Aspect | Action | Job |
|--------|--------|-----|
| **Scope** | Single task | Complete workflow stage |
| **Composition** | Atomic unit | Composed of multiple actions |
| **Reusability** | Building block | Template |
| **Examples** | `npm install`, `docker build` | `Node.js CI`, `Docker build pipeline` |
| **Configuration** | Simple parameters | Complex configuration with defaults |

**When to create an Action:**
- Single, focused task
- Reusable across different jobs
- Simple input/output

**When to create a Job:**
- Complete workflow pattern
- Multiple related actions
- Common use case (e.g., "Python CI", "Docker build and push")

---

## Job Types

### 1. Simple Job Template

A function that returns a complete job configuration:

```nix
{ pkgs, lib, actions }:

{
  name ? "my-job",
  executor ? null,  # Let user specify
}:

{
  inherit executor;
  actions = [
    actions.checkout
    (actions.runCommand "echo 'Hello'")
  ];
}
```

**Use when:**
- Fixed sequence of actions
- Minimal customization needed
- Simple workflow

### 2. Configurable Job Template

A function with extensive parameters for customization:

```nix
{ pkgs, lib, actions }:

{
  name ? "node-ci",
  executor ? null,
  nodeVersion ? "18",
  runTests ? true,
  runLint ? true,
  buildCommand ? "npm run build",
}:

{
  inherit executor;
  actions = [
    actions.checkout
    (actions.setupNode { version = nodeVersion; })
    actions.npm.install
  ]
  ++ lib.optional runLint actions.npm.lint
  ++ lib.optional runTests actions.npm.test
  ++ [
    (actions.runCommand buildCommand)
  ];
}
```

**Use when:**
- Common pattern with variations
- Multiple optional steps
- User needs control over behavior

### 3. Multi-Job Workflow

A function that returns multiple related jobs:

```nix
{ pkgs, lib, actions }:

{ registry, images, ... }:

{
  build = {
    executor = ...;
    actions = [ ... ];
  };
  
  test = {
    executor = ...;
    needs = [ "build" ];
    actions = [ ... ];
  };
  
  deploy = {
    executor = ...;
    needs = [ "test" ];
    actions = [ ... ];
  };
}
```

**Use when:**
- Complete CI/CD pipeline
- Multiple stages with dependencies
- End-to-end workflow

---

## API Patterns

### Pattern 1: Simple Job (No Parameters)

```nix
# lib/jobs/hello-world.nix
{ pkgs, lib, actions }:

# Returns a job configuration
{
  executor = null;  # User must specify
  actions = [
    (actions.runCommand ''
      echo "Hello, World!"
    '')
  ];
}
```

**Usage:**
```nix
jobs.hello = jobs.helloWorld // {
  executor = executors.local;
};
```

### Pattern 2: Parameterized Job

```nix
# lib/jobs/node-ci.nix
{ pkgs, lib, actions }:

{
  nodeVersion ? "18",
  packageManager ? "npm",  # or "yarn", "pnpm"
  runTests ? true,
  runLint ? true,
  runBuild ? true,
  buildScript ? "build",
  testScript ? "test",
  lintScript ? "lint",
}:

{
  executor = null;
  
  actions = [
    actions.checkout
    (actions.setupNode { version = nodeVersion; })
  ]
  # Install dependencies based on package manager
  ++ (if packageManager == "npm" then [
    actions.npm.install
  ] else if packageManager == "yarn" then [
    (actions.runCommand "yarn install")
  ] else [
    (actions.runCommand "pnpm install")
  ])
  # Optional steps
  ++ lib.optional runLint (actions.runCommand "${packageManager} run ${lintScript}")
  ++ lib.optional runTests (actions.runCommand "${packageManager} run ${testScript}")
  ++ lib.optional runBuild (actions.runCommand "${packageManager} run ${buildScript}");
}
```

**Usage:**
```nix
jobs.ci = (jobs.nodeCI {
  nodeVersion = "20";
  packageManager = "pnpm";
  runLint = false;
}) // {
  executor = executors.local;
};
```

### Pattern 3: Multi-Stage Job

```nix
# lib/jobs/docker-pipeline.nix
{ pkgs, lib, actions }:

{
  registry,
  images,
  runTests ? true,
  pushToRegistry ? false,
}:

{
  # Build stage
  build = {
    executor = null;
    actions = [
      actions.checkout
    ] ++ (actions.buildImages {
      inherit registry images;
      operation = "build";
    });
  };
  
  # Test stage
  test = lib.optionalAttrs runTests {
    executor = null;
    needs = [ "build" ];
    actions = [
      (actions.runCommand "docker run --rm ${registry}/${(builtins.head images).name} npm test")
    ];
  };
  
  # Push stage
  push = lib.optionalAttrs pushToRegistry {
    executor = null;
    needs = if runTests then [ "test" ] else [ "build" ];
    actions = map (image: 
      (actions.runCommand "docker push ${registry}/${image.name}")
    ) images;
  };
}
```

**Usage:**
```nix
jobs = (jobs.dockerPipeline {
  registry = "myregistry.io";
  images = [ { name = "myapp"; } ];
  pushToRegistry = true;
}) // {
  # Override executor for all jobs
  build.executor = executors.local;
  test.executor = executors.local;
  push.executor = executors.local;
};
```

### Pattern 4: Job Factory (Advanced)

Returns a function that creates jobs:

```nix
# lib/jobs/matrix-ci.nix
{ pkgs, lib, actions }:

# Returns a FUNCTION that generates jobs
{ 
  name,
  matrix,  # { node = ["18" "20"]; os = ["ubuntu" "macos"]; }
  actions,
}:

lib.listToAttrs (
  lib.flatten (
    lib.mapCartesianProduct
      ({ node, os }: {
        name = "${name}-node${node}-${os}";
        value = {
          executor = null;
          env = {
            NODE_VERSION = node;
            OS = os;
          };
          actions = actions;
        };
      })
      matrix
  )
)
```

**Usage:**
```nix
jobs = jobs.matrixCI {
  name = "test";
  matrix = {
    node = [ "18" "20" "22" ];
    os = [ "ubuntu" "macos" ];
  };
  actions = [
    actions.checkout
    (actions.setupNode { version = "\${NODE_VERSION}"; })
    actions.npm.test
  ];
};
# Generates: test-node18-ubuntu, test-node18-macos, test-node20-ubuntu, ...
```

---

## Naming Conventions

### File Names

- **Lowercase with hyphens**: `node-ci.nix`, `docker-pipeline.nix`, `python-test.nix`
- **Descriptive**: Should indicate the workflow purpose
- **Technology-specific**: Prefix with technology when applicable

Examples:
- `node-ci.nix` - Node.js CI workflow
- `python-lint-test.nix` - Python linting and testing
- `docker-build-push.nix` - Docker build and push pipeline
- `deploy-kubernetes.nix` - Kubernetes deployment job

### Job Function Names

When exporting from `default.nix`:

```nix
{
  nodeCI = import ./node-ci.nix { inherit pkgs lib actions; };
  pythonCI = import ./python-ci.nix { inherit pkgs lib actions; };
  dockerPipeline = import ./docker-pipeline.nix { inherit pkgs lib actions; };
}
```

**Rules:**
- camelCase
- Technology prefix when applicable: `nodeCI`, `pythonTest`, `dockerBuild`
- Descriptive suffix: `CI`, `Test`, `Deploy`, `Pipeline`

---

## Structure

### Minimal Job Template

```nix
{ pkgs, lib, actions }:

# Parameters
{
  param1,
  param2 ? "default",
}:

# Returns job configuration
{
  executor = null;
  actions = [
    actions.checkout
    (actions.runCommand "echo ${param1}")
  ];
}
```

### Complete Job Template

```nix
{ pkgs, lib, actions }:

# Job Template Name
#
# Description of what this job does.
#
# Parameters:
#   - param1 (required): Description
#   - param2 (optional): Description [default: value]
#
# Returns:
#   Single job configuration OR attribute set of multiple jobs
#
# Usage:
#   jobs.myJob = (jobs.templateName { 
#     param1 = "value"; 
#   }) // { 
#     executor = executors.local; 
#   };

{
  # Required parameters
  param1,
  
  # Optional parameters with defaults
  param2 ? "default",
  param3 ? true,
}:

# Validate parameters (optional but recommended)
assert lib.assertMsg (param1 != "") "param1 cannot be empty";

let
  # Helper functions if needed
  buildAction = name: {
    inherit name;
    bash = "echo 'Building ${name}'";
  };
in

# Return job configuration
{
  # Executor (null = user must specify)
  executor = null;
  
  # Optional: job-level environment
  env = {
    PARAM1 = param1;
  };
  
  # Optional: job-level settings
  continueOnError = false;
  
  # Actions list
  actions = [
    actions.checkout
    (buildAction param1)
  ]
  ++ lib.optional param3 (actions.runCommand "optional step");
}
```

---

## Documentation

### File Header Template

```nix
{ pkgs, lib, actions }:

# [Job Name] Job Template
#
# [Detailed description of what this job does and when to use it]
#
# This job template provides [key features]:
#   - Feature 1
#   - Feature 2
#   - Feature 3
#
# Parameters:
#   - param1 (required): [Description]
#   - param2 (optional): [Description] [default: value]
#   - param3 (optional): [Description] [default: value]
#
# Environment Variables:
#   The following environment variables can be used:
#   - ENV_VAR1: [Description]
#   - ENV_VAR2: [Description]
#
# Returns:
#   [Single job configuration | Attribute set of jobs]
#
# Usage Example:
#   ```nix
#   jobs.myJob = (jobs.templateName {
#     param1 = "value";
#     param2 = "custom";
#   }) // {
#     executor = executors.local;
#   };
#   ```
#
# Complete Example:
#   ```nix
#   { nixactions }:
#   
#   nixactions.mkWorkflow {
#     name = "example";
#     
#     jobs.build = (nixactions.jobs.templateName {
#       param1 = "production";
#     }) // {
#       executor = nixactions.executors.local;
#     };
#   }
#   ```
#
# Notes:
#   - [Any important notes or caveats]
#   - [Common pitfalls to avoid]

{ param1, param2 ? "default" }:

# Implementation...
```

---

## Examples

### Example 1: Simple CI Job

```nix
# lib/jobs/node-ci-simple.nix
{ pkgs, lib, actions }:

# Node.js CI - Simple
#
# A basic Node.js CI job that runs install, lint, test, and build.
#
# Parameters:
#   - nodeVersion (optional): Node.js version [default: "18"]
#
# Usage:
#   jobs.ci = (jobs.nodeCI { nodeVersion = "20"; }) // {
#     executor = executors.local;
#   };

{
  nodeVersion ? "18",
}:

{
  executor = null;
  
  actions = [
    actions.checkout
    (actions.setupNode { version = nodeVersion; })
    actions.npm.install
    actions.npm.lint
    actions.npm.test
    actions.npm.build
  ];
}
```

### Example 2: Configurable Python CI

```nix
# lib/jobs/python-ci.nix
{ pkgs, lib, actions }:

# Python CI Job Template
#
# Comprehensive Python CI workflow with optional steps.
#
# Parameters:
#   - pythonVersion (optional): Python version [default: "3.11"]
#   - usePytest (optional): Run pytest [default: true]
#   - useMypy (optional): Run mypy type checking [default: true]
#   - useBlack (optional): Run black formatter check [default: true]
#   - useFlake8 (optional): Run flake8 linter [default: true]
#   - installCommand (optional): Pip install command [default: "pip install -r requirements.txt"]
#   - testCommand (optional): Test command [default: "pytest"]
#
# Usage:
#   jobs.test = (jobs.pythonCI {
#     pythonVersion = "3.12";
#     useMypy = false;
#   }) // {
#     executor = executors.local;
#   };

{
  pythonVersion ? "3.11",
  usePytest ? true,
  useMypy ? true,
  useBlack ? true,
  useFlake8 ? true,
  installCommand ? "pip install -r requirements.txt",
  testCommand ? "pytest",
}:

{
  executor = null;
  
  actions = [
    # Setup
    actions.checkout
    (actions.setupPython { version = pythonVersion; })
    
    # Install dependencies
    (actions.runCommand installCommand)
  ]
  # Linting and formatting checks
  ++ lib.optional useBlack (actions.runCommand "black --check .")
  ++ lib.optional useFlake8 (actions.runCommand "flake8 .")
  ++ lib.optional useMypy (actions.runCommand "mypy .")
  # Tests
  ++ lib.optional usePytest (actions.runCommand testCommand);
}
```

### Example 3: Docker Build and Push Pipeline

```nix
# lib/jobs/docker-build-push.nix
{ pkgs, lib, actions }:

# Docker Build and Push Pipeline
#
# Multi-stage pipeline for building, testing, and pushing Docker images.
#
# Parameters:
#   - registry (required): Container registry URL
#   - images (required): List of image configurations (see actions.buildImages)
#   - runTests (optional): Run tests before pushing [default: true]
#   - testCommand (optional): Test command to run [default: null]
#   - pushOnSuccess (optional): Push images after successful tests [default: true]
#   - tag (optional): Image tag [default: "latest"]
#
# Returns:
#   Attribute set with jobs: { build, test?, push? }
#
# Usage:
#   jobs = (jobs.dockerBuildPush {
#     registry = "myregistry.io";
#     images = [
#       { name = "api"; }
#       { name = "worker"; }
#     ];
#   }) // {
#     build.executor = executors.local;
#     test.executor = executors.local;
#     push.executor = executors.local;
#   };

{
  registry,
  images,
  runTests ? true,
  testCommand ? null,
  pushOnSuccess ? true,
  tag ? "latest",
}:

{
  # Build stage
  build = {
    executor = null;
    actions = [
      actions.checkout
    ] ++ (actions.buildImages {
      inherit registry images tag;
      operation = "build";  # Only build, don't push yet
    });
  };
  
  # Test stage (conditional)
  test = lib.optionalAttrs runTests {
    executor = null;
    needs = [ "build" ];
    actions = if testCommand != null then [
      (actions.runCommand testCommand)
    ] else [
      # Default: run tests in first image
      (actions.runCommand ''
        docker run --rm ${registry}/${(builtins.head images).name}:${tag} npm test
      '')
    ];
  };
  
  # Push stage (conditional)
  push = lib.optionalAttrs pushOnSuccess {
    executor = null;
    needs = if runTests then [ "test" ] else [ "build" ];
    
    actions = lib.flatten (map (image:
      (actions.runCommand "docker push ${registry}/${image.name}:${tag}")
    ) images);
  };
}
```

### Example 4: Full CI/CD Pipeline

```nix
# lib/jobs/full-cicd.nix
{ pkgs, lib, actions }:

# Full CI/CD Pipeline
#
# Complete pipeline: build → test → deploy
#
# Parameters:
#   - language (required): "node" | "python" | "rust"
#   - version (optional): Language version [default: depends on language]
#   - deployTarget (optional): Deployment target [default: null (no deploy)]
#   - deployCommand (optional): Custom deploy command [default: null]
#
# Returns:
#   Attribute set: { build, test, deploy? }
#
# Usage:
#   jobs = (jobs.fullCICD {
#     language = "node";
#     version = "20";
#     deployTarget = "production";
#   }) // {
#     build.executor = executors.local;
#     test.executor = executors.local;
#     deploy.executor = executors.local;
#   };

{
  language,
  version ? null,
  deployTarget ? null,
  deployCommand ? null,
}:

let
  defaultVersion = {
    node = "18";
    python = "3.11";
    rust = "1.75";
  }.${language} or "unknown";
  
  actualVersion = if version != null then version else defaultVersion;
  
  # Language-specific setup and test actions
  languageActions = {
    node = {
      setup = (actions.setupNode { version = actualVersion; });
      install = actions.npm.install;
      test = actions.npm.test;
      build = actions.npm.build;
    };
    
    python = {
      setup = (actions.setupPython { version = actualVersion; });
      install = (actions.runCommand "pip install -r requirements.txt");
      test = (actions.runCommand "pytest");
      build = (actions.runCommand "python setup.py build");
    };
    
    rust = {
      setup = (actions.setupRust { version = actualVersion; });
      install = (actions.runCommand "cargo fetch");
      test = (actions.runCommand "cargo test");
      build = (actions.runCommand "cargo build --release");
    };
  }.${language};
in

{
  # Build job
  build = {
    executor = null;
    actions = [
      actions.checkout
      languageActions.setup
      languageActions.install
      languageActions.build
    ];
  };
  
  # Test job
  test = {
    executor = null;
    needs = [ "build" ];
    actions = [
      actions.checkout
      languageActions.setup
      languageActions.install
      languageActions.test
    ];
  };
  
  # Deploy job (conditional)
  deploy = lib.optionalAttrs (deployTarget != null) {
    executor = null;
    needs = [ "test" ];
    
    env = {
      DEPLOY_TARGET = deployTarget;
    };
    
    actions = [
      actions.checkout
    ] ++ (if deployCommand != null then [
      (actions.runCommand deployCommand)
    ] else [
      # Default deployment
      (actions.runCommand ''
        echo "Deploying to ${deployTarget}"
        # Add your deployment logic here
      '')
    ]);
  };
}
```

---

## Testing

### Create Example Workflow

```nix
# examples/test-my-job.nix
{ nixactions, pkgs }:

nixactions.mkWorkflow {
  name = "test-my-job";
  
  jobs = (nixactions.jobs.myJob {
    param1 = "value";
  }) // {
    executor = nixactions.executors.local;
  };
}
```

### Test Multi-Job Template

```nix
# examples/test-multi-job.nix
{ nixactions, pkgs }:

let
  pipeline = nixactions.jobs.dockerPipeline {
    registry = "test.io";
    images = [ { name = "testapp"; } ];
  };
in

nixactions.mkWorkflow {
  name = "test-pipeline";
  
  jobs = {
    build = pipeline.build // {
      executor = nixactions.executors.local;
    };
    
    test = pipeline.test // {
      executor = nixactions.executors.local;
    };
    
    push = pipeline.push // {
      executor = nixactions.executors.local;
    };
  };
}
```

### Verify Generated Code

```bash
nix build .#example-test-my-job
cat result/bin/test-my-job
./result/bin/test-my-job
```

---

## Common Patterns

### 1. Optional Jobs

```nix
{
  build = { /* ... */ };
  
  test = lib.optionalAttrs runTests {
    executor = null;
    needs = [ "build" ];
    actions = [ /* ... */ ];
  };
}
```

### 2. Conditional Actions

```nix
{
  executor = null;
  actions = [
    actions.checkout
  ]
  ++ lib.optional enableLint actions.npm.lint
  ++ lib.optional enableTest actions.npm.test;
}
```

### 3. Dynamic Job Names

```nix
lib.listToAttrs (map (platform: {
  name = "build-${platform}";
  value = {
    executor = null;
    env.PLATFORM = platform;
    actions = [ /* ... */ ];
  };
}) [ "linux" "macos" "windows" ])
```

### 4. Shared Configuration

```nix
let
  commonActions = [
    actions.checkout
    (actions.setupNode { version = "18"; })
  ];
in
{
  lint = {
    executor = null;
    actions = commonActions ++ [ actions.npm.lint ];
  };
  
  test = {
    executor = null;
    actions = commonActions ++ [ actions.npm.test ];
  };
}
```

---

## Anti-Patterns

### ❌ DON'T: Hardcode executor

```nix
# BAD - Forces specific executor
{
  executor = executors.local;  # User can't override
  actions = [ /* ... */ ];
}
```

### ✅ DO: Let user specify executor

```nix
# GOOD - User can choose executor
{
  executor = null;  # User MUST specify
  actions = [ /* ... */ ];
}
```

### ❌ DON'T: Return raw action list

```nix
# BAD - Not a job, just actions
[
  actions.checkout
  actions.npm.test
]
```

### ✅ DO: Return proper job configuration

```nix
# GOOD - Complete job object
{
  executor = null;
  actions = [
    actions.checkout
    actions.npm.test
  ];
}
```

### ❌ DON'T: Mix too many concerns

```nix
# BAD - Does everything in one job
{
  name = "do-everything";
  actions = [
    # Build
    # Test  
    # Deploy
    # Notify
    # Cleanup
    # ...50 more actions
  ];
}
```

### ✅ DO: Split into logical jobs

```nix
# GOOD - Separate concerns
{
  build = { /* ... */ };
  test = { needs = ["build"]; /* ... */ };
  deploy = { needs = ["test"]; /* ... */ };
}
```

---

## Checklist

Before submitting a new job template:

- [ ] File name is kebab-case and descriptive
- [ ] Comprehensive documentation header
- [ ] All parameters documented with types, defaults, and descriptions
- [ ] Returns proper job structure (not just action list)
- [ ] `executor = null` to let user specify
- [ ] Includes usage example in documentation
- [ ] Tested with example workflow
- [ ] Added to `lib/jobs/default.nix` exports
- [ ] Handles edge cases gracefully
- [ ] Uses lib.optional/optionalAttrs for conditional logic

---

## Integration with Actions

Jobs should use actions from `lib/actions/`:

```nix
# Good - reuse existing actions
{ pkgs, lib, actions }:

{ nodeVersion ? "18" }:

{
  executor = null;
  actions = [
    actions.checkout              # From lib/actions/
    (actions.setupNode { 
      version = nodeVersion; 
    })
    actions.npm.install
    actions.npm.test
  ];
}
```

If an action doesn't exist yet, consider:
1. Is it reusable? → Create in `lib/actions/`
2. Job-specific? → Inline with `actions.runCommand`

---

## Questions?

When designing a job template, ask:
1. **Is this a common workflow pattern?** → Create a job template
2. **Is this too specific?** → Maybe it's just an example, not a library job
3. **Can users customize it easily?** → Add parameters
4. **Does it compose well?** → Returns standard job structure

Remember: **Jobs orchestrate actions into reusable workflow patterns.**
