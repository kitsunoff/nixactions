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
10. [Configurable Inputs/Outputs](#configurable-inputsoutputs)
11. [Configurable Environment Variables](#configurable-environment-variables)

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
  executor,  # Required
  name ? "my-job",
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
  executor,  # Required
  name ? "node-ci",
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

{
  executor,  # Required - used for all jobs
  jobPrefix ? "",  # Optional prefix to avoid job name conflicts
  registry,
  images,
}:

let
  # Internal job names - scoped to this template
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  deployJob = "${jobPrefix}deploy";
in
{
  ${buildJob} = {
    inherit executor;
    actions = [ ... ];
  };
  
  ${testJob} = {
    inherit executor;
    needs = [ buildJob ];  # Reference internal job name
    actions = [ ... ];
  };
  
  ${deployJob} = {
    inherit executor;
    needs = [ testJob ];  # Reference internal job name
    actions = [ ... ];
  };
}
```

**Use when:**
- Complete CI/CD pipeline
- Multiple stages with dependencies
- End-to-end workflow

**Important:** Multi-job templates MUST use scoped job names (via `jobPrefix`) to avoid conflicts with other jobs in the workflow. Internal `needs` should reference these scoped names.

---

## API Patterns

### Pattern 1: Simple Job (No Parameters)

```nix
# lib/jobs/hello-world.nix
{ pkgs, lib, actions }:

{
  executor,  # User MUST provide executor
}:

# Returns a job configuration
{
  inherit executor;
  actions = [
    (actions.runCommand ''
      echo "Hello, World!"
    '')
  ];
}
```

**Usage:**
```nix
jobs.hello = jobs.helloWorld {
  executor = executors.local;
};
```

### Pattern 2: Parameterized Job

```nix
# lib/jobs/node-ci.nix
{ pkgs, lib, actions }:

{
  executor,  # Required
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
  inherit executor;
  
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
jobs.ci = jobs.nodeCI {
  executor = executors.local;
  nodeVersion = "20";
  packageManager = "pnpm";
  runLint = false;
};
```

### Pattern 3: Multi-Stage Job

```nix
# lib/jobs/docker-pipeline.nix
{ pkgs, lib, actions }:

{
  executor,  # Required - will be used for all jobs
  jobPrefix ? "",  # Prefix to avoid job name conflicts
  registry,
  images,
  runTests ? true,
  pushToRegistry ? false,
}:

let
  # Scoped job names
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  pushJob = "${jobPrefix}push";
in
{
  # Build stage
  ${buildJob} = {
    inherit executor;
    actions = [
      actions.checkout
    ] ++ (actions.buildImages {
      inherit registry images;
      operation = "build";
    });
  };
  
  # Test stage
  ${testJob} = lib.optionalAttrs runTests {
    inherit executor;
    needs = [ buildJob ];  # Reference scoped name
    actions = [
      (actions.runCommand "docker run --rm ${registry}/${(builtins.head images).name} npm test")
    ];
  };
  
  # Push stage
  ${pushJob} = lib.optionalAttrs pushToRegistry {
    inherit executor;
    needs = if runTests then [ testJob ] else [ buildJob ];  # Reference scoped names
    actions = map (image: 
      (actions.runCommand "docker push ${registry}/${image.name}")
    ) images;
  };
}
```

**Usage:**
```nix
jobs = jobs.dockerPipeline {
  executor = executors.local;
  jobPrefix = "docker-";  # Creates: docker-build, docker-test, docker-push
  registry = "myregistry.io";
  images = [ { name = "myapp"; } ];
  pushToRegistry = true;
};
```

### Pattern 4: Job Factory (Advanced)

Returns a function that creates jobs:

```nix
# lib/jobs/matrix-ci.nix
{ pkgs, lib, actions }:

# Returns a FUNCTION that generates jobs
{ 
  executor,  # Required
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
          inherit executor;
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
  executor = executors.local;
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

## Multi-Job Dependencies

**CRITICAL:** When creating templates that return multiple jobs, you MUST scope job names to avoid conflicts.

### Problem: Name Collisions

```nix
# BAD - Hardcoded job names will conflict
{ executor }:

{
  build = { 
    inherit executor;
    actions = [ /* ... */ ];
  };
  
  test = {
    inherit executor;
    needs = [ "build" ];  # Which "build"? Could conflict!
    actions = [ /* ... */ ];
  };
}

# Usage causes conflicts:
jobs = jobs.dockerPipeline { executor = executors.local; }
  // jobs.nodePipeline { executor = executors.local; };
# Error: Both define "build" and "test"!
```

### ✅ Solution: Job Prefix Parameter

```nix
# GOOD - Scoped job names
{ 
  executor,
  jobPrefix ? "",  # Allow user to scope job names
}:

let
  # Internal scoped names
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  deployJob = "${jobPrefix}deploy";
in
{
  ${buildJob} = {
    inherit executor;
    actions = [ /* ... */ ];
  };
  
  ${testJob} = {
    inherit executor;
    needs = [ buildJob ];  # Reference scoped name
    actions = [ /* ... */ ];
  };
  
  ${deployJob} = {
    inherit executor;
    needs = [ testJob ];  # Reference scoped name
    actions = [ /* ... */ ];
  };
}
```

**Usage:**
```nix
jobs = jobs.dockerPipeline { 
  executor = executors.local;
  jobPrefix = "docker-";  # Creates: docker-build, docker-test, docker-deploy
} // jobs.nodePipeline {
  executor = executors.local;
  jobPrefix = "node-";  # Creates: node-build, node-test, node-deploy
};
# No conflicts!
```

### Pattern: Overridable Needs

Allow users to override internal dependencies:

```nix
{
  executor,
  jobPrefix ? "",
  
  # Allow overriding internal dependencies
  buildJobDeps ? [],  # Additional deps for build
  testJobDeps ? [],   # Additional deps for test
}:

let
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
in
{
  ${buildJob} = {
    inherit executor;
    needs = buildJobDeps;  # User can add external dependencies
    actions = [ /* ... */ ];
  };
  
  ${testJob} = {
    inherit executor;
    needs = [ buildJob ] ++ testJobDeps;  # Internal + external deps
    actions = [ /* ... */ ];
  };
}
```

**Usage with external dependencies:**
```nix
jobs = {
  # External job
  setupInfra = {
    executor = executors.local;
    actions = [ /* setup */ ];
  };
  
  # Pipeline that depends on external job
} // jobs.dockerPipeline {
  executor = executors.local;
  jobPrefix = "docker-";
  buildJobDeps = [ "setupInfra" ];  # docker-build now depends on setupInfra
};
```

### Requirements for Multi-Job Templates

1. **MUST** use `jobPrefix` parameter (default: `""`)
2. **MUST** scope all internal job names with prefix
3. **MUST** use scoped names in internal `needs` references
4. **MAY** allow users to add external dependencies via override parameters

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
  executor,  # Required
  param1,
  param2 ? "default",
}:

# Returns job configuration
{
  inherit executor;
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
#   - executor (required): Executor to run the job
#   - param1 (required): Description
#   - param2 (optional): Description [default: value]
#
# Returns:
#   Single job configuration OR attribute set of multiple jobs
#
# Usage:
#   jobs.myJob = jobs.templateName { 
#     executor = executors.local;
#     param1 = "value"; 
#   };

{
  # Required parameters
  executor,
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
  inherit executor;
  
  # Optional: job-level environment
  env = {
    PARAM1 = param1;
  };
  
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
#   - executor (required): Executor to run the job
#   - nodeVersion (optional): Node.js version [default: "18"]
#
# Usage:
#   jobs.ci = jobs.nodeCI {
#     executor = executors.local;
#     nodeVersion = "20";
#   };

{
  executor,
  nodeVersion ? "18",
}:

{
  inherit executor;
  
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
#   - executor (required): Executor to run the job
#   - pythonVersion (optional): Python version [default: "3.11"]
#   - usePytest (optional): Run pytest [default: true]
#   - useMypy (optional): Run mypy type checking [default: true]
#   - useBlack (optional): Run black formatter check [default: true]
#   - useFlake8 (optional): Run flake8 linter [default: true]
#   - installCommand (optional): Pip install command [default: "pip install -r requirements.txt"]
#   - testCommand (optional): Test command [default: "pytest"]
#
# Usage:
#   jobs.test = jobs.pythonCI {
#     executor = executors.local;
#     pythonVersion = "3.12";
#     useMypy = false;
#   };

{
  executor,
  pythonVersion ? "3.11",
  usePytest ? true,
  useMypy ? true,
  useBlack ? true,
  useFlake8 ? true,
  installCommand ? "pip install -r requirements.txt",
  testCommand ? "pytest",
}:

{
  inherit executor;
  
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
#   - executor (required): Executor to run all jobs
#   - jobPrefix (optional): Prefix for job names [default: "docker-"]
#   - registry (required): Container registry URL
#   - images (required): List of image configurations (see actions.buildImages)
#   - runTests (optional): Run tests before pushing [default: true]
#   - testCommand (optional): Test command to run [default: null]
#   - pushOnSuccess (optional): Push images after successful tests [default: true]
#   - tag (optional): Image tag [default: "latest"]
#
# Returns:
#   Attribute set with scoped jobs: { {jobPrefix}build, {jobPrefix}test?, {jobPrefix}push? }
#
# Usage:
#   jobs = jobs.dockerBuildPush {
#     executor = executors.local;
#     jobPrefix = "docker-";  # Creates: docker-build, docker-test, docker-push
#     registry = "myregistry.io";
#     images = [
#       { name = "api"; }
#       { name = "worker"; }
#     ];
#   };

{
  executor,
  jobPrefix ? "docker-",  # Default prefix to avoid conflicts
  registry,
  images,
  runTests ? true,
  testCommand ? null,
  pushOnSuccess ? true,
  tag ? "latest",
}:

let
  # Scoped job names
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  pushJob = "${jobPrefix}push";
in
{
  # Build stage
  ${buildJob} = {
    inherit executor;
    actions = [
      actions.checkout
    ] ++ (actions.buildImages {
      inherit registry images tag;
      operation = "build";  # Only build, don't push yet
    });
  };
  
  # Test stage
  ${testJob} = lib.optionalAttrs runTests {
    inherit executor;
    needs = [ buildJob ];  # Reference scoped name
    actions = if testCommand != null then [
      (actions.runCommand testCommand)
    ] else [
      # Default: run tests in first image
      (actions.runCommand ''
        docker run --rm ${registry}/${(builtins.head images).name}:${tag} npm test
      '')
    ];
  };
  
  # Push stage
  ${pushJob} = lib.optionalAttrs pushOnSuccess {
    inherit executor;
    needs = if runTests then [ testJob ] else [ buildJob ];  # Reference scoped names
    
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
#   - executor (required): Executor to run all jobs
#   - jobPrefix (optional): Prefix for job names [default: ""]
#   - language (required): "node" | "python" | "rust"
#   - version (optional): Language version [default: depends on language]
#   - deployTarget (optional): Deployment target [default: null (no deploy)]
#   - deployCommand (optional): Custom deploy command [default: null]
#
# Returns:
#   Attribute set: { {jobPrefix}build, {jobPrefix}test, {jobPrefix}deploy? }
#
# Usage:
#   jobs = jobs.fullCICD {
#     executor = executors.local;
#     jobPrefix = "app-";  # Creates: app-build, app-test, app-deploy
#     language = "node";
#     version = "20";
#     deployTarget = "production";
#   };

{
  executor,
  jobPrefix ? "",  # Allow scoping to avoid conflicts
  language,
  version ? null,
  deployTarget ? null,
  deployCommand ? null,
}:

let
  # Scoped job names
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  deployJob = "${jobPrefix}deploy";
  
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
  ${buildJob} = {
    inherit executor;
    actions = [
      actions.checkout
      languageActions.setup
      languageActions.install
      languageActions.build
    ];
  };
  
  # Test job
  ${testJob} = {
    inherit executor;
    needs = [ buildJob ];  # Reference scoped name
    actions = [
      actions.checkout
      languageActions.setup
      languageActions.install
      languageActions.test
    ];
  };
  
  # Deploy job (conditional)
  ${deployJob} = lib.optionalAttrs (deployTarget != null) {
    inherit executor;
    needs = [ testJob ];  # Reference scoped name
    
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
  
  jobs.test = nixactions.jobs.myJob {
    executor = nixactions.executors.local;
    param1 = "value";
  };
}
```

### Test Multi-Job Template

```nix
# examples/test-multi-job.nix
{ nixactions, pkgs }:

nixactions.mkWorkflow {
  name = "test-pipeline";
  
  jobs = nixactions.jobs.dockerPipeline {
    executor = nixactions.executors.local;
    registry = "test.io";
    images = [ { name = "testapp"; } ];
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
{ executor, runTests ? true }:

{
  build = {
    inherit executor;
    actions = [ /* ... */ ];
  };
  
  test = lib.optionalAttrs runTests {
    inherit executor;
    needs = [ "build" ];
    actions = [ /* ... */ ];
  };
}
```

### 2. Conditional Actions

```nix
{ executor, enableLint ? true, enableTest ? true }:

{
  inherit executor;
  actions = [
    actions.checkout
  ]
  ++ lib.optional enableLint actions.npm.lint
  ++ lib.optional enableTest actions.npm.test;
}
```

### 3. Dynamic Job Names

```nix
{ executor, platforms ? [ "linux" "macos" "windows" ] }:

lib.listToAttrs (map (platform: {
  name = "build-${platform}";
  value = {
    inherit executor;
    env.PLATFORM = platform;
    actions = [ /* ... */ ];
  };
}) platforms)
```

### 4. Shared Configuration

```nix
{ executor, nodeVersion ? "18" }:

let
  commonActions = [
    actions.checkout
    (actions.setupNode { version = nodeVersion; })
  ];
in
{
  lint = {
    inherit executor;
    actions = commonActions ++ [ actions.npm.lint ];
  };
  
  test = {
    inherit executor;
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

### ❌ DON'T: Use executor = null (forces merge syntax)

```nix
# BAD - Requires merge syntax
{ param1 ? "value" }:

{
  executor = null;  # Forces user to use //
  actions = [ /* ... */ ];
}

# Usage requires merge:
jobs.test = (jobs.myJob { param1 = "foo"; }) // {
  executor = executors.local;  # Awkward!
};
```

### ✅ DO: Require executor as parameter

```nix
# GOOD - Executor is explicit parameter
{
  executor,  # Required parameter
  param1 ? "value",
}:

{
  inherit executor;
  actions = [ /* ... */ ];
}

# Usage is clean:
jobs.test = jobs.myJob {
  executor = executors.local;
  param1 = "foo";
};
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

### ❌ DON'T: Use continueOnError

```nix
# BAD - continueOnError is an anti-pattern
{
  executor = null;
  continueOnError = true;  # NEVER DO THIS
  actions = [ /* ... */ ];
}
```

**Why it's bad:**
- Hides real failures
- Makes debugging harder
- Creates unreliable workflows
- Leads to cascading failures

### ✅ DO: Handle errors explicitly

```nix
# GOOD - Handle errors with conditions
{
  executor = null;
  actions = [
    {
      name = "risky-operation";
      bash = ''
        if ! some-command; then
          echo "Command failed, but continuing with fallback"
          fallback-command
        fi
      '';
    }
    
    {
      name = "cleanup";
      "if" = "always()";  # Always run cleanup
      bash = "cleanup-resources";
    }
  ];
}
```

---

## Checklist

Before submitting a new job template:

- [ ] File name is kebab-case and descriptive
- [ ] Comprehensive documentation header
- [ ] All parameters documented with types, defaults, and descriptions
- [ ] Returns proper job structure (not just action list)
- [ ] **`executor` is a required parameter** - NOT `executor = null`
- [ ] **Inputs/outputs are configurable** - no hardcoded artifact names
- [ ] **Environment variables are configurable** - no hardcoded env var names
- [ ] **envProviders are user-configurable** - not hardcoded in template
- [ ] **Multi-job templates use `jobPrefix` parameter** - to avoid name conflicts
- [ ] **Internal `needs` use scoped job names** - reference variables, not strings
- [ ] Includes usage example in documentation (without merge syntax `//`)
- [ ] Tested with example workflow
- [ ] Added to `lib/jobs/default.nix` exports
- [ ] Handles edge cases gracefully
- [ ] Uses lib.optional/optionalAttrs for conditional logic
- [ ] **Does NOT use continueOnError** - this is an anti-pattern

---

## Integration with Actions

Jobs should use actions from `lib/actions/`:

```nix
# Good - reuse existing actions
{ pkgs, lib, actions }:

{
  executor,
  nodeVersion ? "18",
}:

{
  inherit executor;
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

## Configurable Inputs/Outputs

**Job templates MUST allow users to configure artifact names and paths.**

### ✅ DO: Make inputs/outputs configurable

```nix
# lib/jobs/node-build.nix
{ pkgs, lib, actions }:

{
  executor,  # Required
  
  # Allow user to customize output artifact name and path
  outputArtifactName ? "dist",
  outputPath ? "dist/",
  
  # Allow user to specify required input artifacts
  inputArtifacts ? [],
}:

{
  inherit executor;
  
  # User-configurable inputs
  inputs = inputArtifacts;
  
  actions = [
    actions.checkout
    (actions.setupNode { version = "18"; })
    actions.npm.install
    actions.npm.build
  ];
  
  # User-configurable outputs
  outputs = {
    ${outputArtifactName} = outputPath;
  };
}
```

**Usage:**
```nix
# User can customize artifact names to avoid conflicts
jobs = {
  buildFrontend = jobs.nodeBuild {
    executor = executors.local;
    outputArtifactName = "frontend-dist";
    outputPath = "packages/frontend/dist/";
  };
  
  buildBackend = jobs.nodeBuild {
    executor = executors.local;
    outputArtifactName = "backend-dist";
    outputPath = "packages/backend/dist/";
  };
  
  deploy = {
    executor = executors.local;
    needs = [ "buildFrontend" "buildBackend" ];
    inputs = [ "frontend-dist" "backend-dist" ];  # Custom names
    actions = [ /* deploy */ ];
  };
};
```

### ❌ DON'T: Hardcode artifact names

```nix
# BAD - Forces users to use specific artifact name
{
  executor,
  outputs = {
    dist = "dist/";  # Hardcoded name!
  };
}
```

### Pattern: Optional Outputs

```nix
{
  executor,
  saveArtifacts ? true,
  artifactName ? "build-output",
  artifactPath ? "dist/",
}:

{
  inherit executor;
  actions = [ /* ... */ ];
  
  # Conditionally save outputs
  outputs = lib.optionalAttrs saveArtifacts {
    ${artifactName} = artifactPath;
  };
}
```

### Pattern: Multiple Configurable Outputs

```nix
{
  executor,
  saveDist ? true,
  distName ? "dist",
  distPath ? "dist/",
  
  saveBinary ? false,
  binaryName ? "binary",
  binaryPath ? "bin/app",
}:

{
  inherit executor;
  actions = [ /* ... */ ];
  
  outputs = 
    (lib.optionalAttrs saveDist { ${distName} = distPath; })
    // (lib.optionalAttrs saveBinary { ${binaryName} = binaryPath; });
}
```

### Documentation Requirements

Always document configurable inputs/outputs:

```nix
# Node.js Build Job
#
# Parameters:
#   - outputArtifactName (optional): Name of output artifact [default: "dist"]
#   - outputPath (optional): Path to build output [default: "dist/"]
#   - inputArtifacts (optional): List of required input artifacts [default: []]
#
# Outputs:
#   - {outputArtifactName}: Build artifacts (configurable name)
#
# Inputs:
#   - {inputArtifacts}: Required artifacts from previous jobs (configurable)
```

---

## Configurable Environment Variables

**Job templates MUST allow users to configure environment variable sources.**

### ✅ DO: Make environment variable sources configurable

```nix
# lib/jobs/deploy.nix
{ pkgs, lib, actions }:

{
  # Allow user to specify which env vars to use
  databaseUrlVar ? "DATABASE_URL",
  apiKeyVar ? "API_KEY",
  deployTargetVar ? "DEPLOY_TARGET",
  
  # Allow custom env providers
  envProviders ? [],
}:

{
  executor = null;
  
  # Use provided env providers
  inherit envProviders;
  
  actions = [
    {
      name = "deploy-application";
      bash = ''
        # Use configurable env var names
        echo "Deploying to ''${${deployTargetVar}}"
        echo "Database: ''${${databaseUrlVar}}"
        
        # API key is available via configured var name
        if [ -n "''${${apiKeyVar}:-}" ]; then
          echo "API key configured"
        fi
      '';
    }
  ];
}
```

**Usage:**
```nix
jobs.deploy = (jobs.deploy {
  # User specifies which env vars to use
  databaseUrlVar = "PROD_DATABASE_URL";
  apiKeyVar = "PROD_API_KEY";
  deployTargetVar = "PROD_TARGET";
  
  # User controls env providers
  envProviders = [
    (platform.envProviders.sops { 
      file = ./secrets.sops.yaml; 
    })
    (platform.envProviders.required [ 
      "PROD_DATABASE_URL" 
      "PROD_API_KEY"
      "PROD_TARGET"
    ])
  ];
}) // {
  executor = executors.local;
};
```

### Pattern: Environment Variable Mapping

```nix
{
  # Let user map external env vars to internal names
  envMapping ? {
    databaseUrl = "DATABASE_URL";
    apiKey = "API_KEY";
    region = "AWS_REGION";
  },
}:

{
  executor = null;
  
  actions = [{
    name = "use-mapped-vars";
    bash = ''
      # Use mapped variable names
      DB_URL=''${${envMapping.databaseUrl}}
      KEY=''${${envMapping.apiKey}}
      REGION=''${${envMapping.region}}
      
      echo "Connecting to $DB_URL in $REGION"
    '';
  }];
}
```

### Pattern: Optional Environment Requirements

```nix
{
  requiredEnvVars ? [],
  optionalEnvVars ? [],
  envProviders ? [],
}:

{
  executor = null;
  
  # Add required env validation if specified
  envProviders = envProviders 
    ++ lib.optional (requiredEnvVars != []) 
      (platform.envProviders.required requiredEnvVars);
  
  actions = [{
    bash = ''
      # Check optional vars
      ${lib.concatMapStringsSep "\n" (var: ''
        if [ -n "''${${var}:-}" ]; then
          echo "✓ ${var} configured"
        else
          echo "ℹ ${var} not set (optional)"
        fi
      '') optionalEnvVars}
    '';
  }];
}
```

### ❌ DON'T: Hardcode environment variable names

```nix
# BAD - Forces specific env var names
{
  executor = null;
  actions = [{
    bash = ''
      echo "Database: $DATABASE_URL"  # Hardcoded!
      echo "API Key: $API_KEY"        # Hardcoded!
    '';
  }];
}
```

### ❌ DON'T: Hardcode env providers

```nix
# BAD - Forces specific secret management
{
  executor = null;
  envProviders = [
    (platform.envProviders.sops { file = ./secrets.yaml; })  # Hardcoded!
  ];
}
```

### Documentation Requirements

Always document configurable environment variables:

```nix
# Deployment Job
#
# Parameters:
#   - databaseUrlVar (optional): Env var name for database URL [default: "DATABASE_URL"]
#   - apiKeyVar (optional): Env var name for API key [default: "API_KEY"]
#   - envProviders (optional): List of env providers [default: []]
#
# Environment Variables (configurable names):
#   The job expects these environment variables (names can be customized):
#   - {databaseUrlVar}: Database connection URL (required)
#   - {apiKeyVar}: API authentication key (required)
#
# Example:
#   jobs.deploy = (jobs.deploy {
#     databaseUrlVar = "PROD_DB_URL";
#     apiKeyVar = "PROD_KEY";
#     envProviders = [
#       (platform.envProviders.sops { file = ./prod-secrets.yaml; })
#     ];
#   }) // { executor = executors.local; };

---

## Questions?

When designing a job template, ask:
1. **Is this a common workflow pattern?** → Create a job template
2. **Is this too specific?** → Maybe it's just an example, not a library job
3. **Can users customize it easily?** → Add parameters
4. **Does it compose well?** → Returns standard job structure
5. **Are inputs/outputs clear?** → Document them explicitly

Remember: **Jobs orchestrate actions into reusable workflow patterns.**
