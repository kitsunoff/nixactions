# Jobs Library - Inputs/Outputs/Needs Design

This document describes how to design job templates with clear inputs, outputs, and dependencies.

## Current System (How it works now)

### Outputs (Artifacts)

Jobs can save artifacts (files/directories) for other jobs:

```nix
jobs.build = {
  executor = executors.local;
  actions = [ /* ... */ ];
  
  # Define what to save
  outputs = {
    dist = "dist/";        # Save dist/ directory as "dist" artifact
    binary = "app";        # Save app file as "binary" artifact
  };
};
```

### Inputs (Artifact Dependencies)

Jobs can restore artifacts from previous jobs:

```nix
jobs.deploy = {
  executor = executors.local;
  needs = [ "build" ];  # Run after build
  
  # Restore artifacts from any job
  inputs = [ "dist" "binary" ];
  
  actions = [
    # dist/ and app are now available in working directory
    (actions.runCommand "deploy dist/")
  ];
};
```

### Needs (Job Dependencies)

Jobs can depend on other jobs:

```nix
jobs.test = {
  executor = executors.local;
  needs = [ "build" ];  # Wait for build to complete
  inputs = [ "dist" ];  # Restore dist artifact
  actions = [ /* ... */ ];
};
```

**How it works:**
- Jobs are organized into **levels** based on `needs`
- Level 0: Jobs with no dependencies
- Level 1: Jobs that need level 0 jobs
- Level N: Jobs that need level N-1 jobs
- Jobs in same level run in **parallel**
- Jobs in different levels run **sequentially**

---

## Design Principles for Job Templates

### 1. Explicit Inputs/Outputs

Job templates should **clearly document**:
- What artifacts they produce (outputs)
- What artifacts they consume (inputs)
- What jobs they depend on (needs)

### 2. Composability

Job templates should be **easily composable**:
- Outputs from one job → Inputs to another
- Clear dependency chains
- Predictable behavior

### 3. Flexibility

Job templates should allow:
- Optional inputs/outputs
- Configurable dependencies
- Override mechanisms

---

## Pattern 1: Simple Job with Outputs

Job that produces artifacts but has no dependencies:

```nix
# lib/jobs/node-build.nix
{ pkgs, lib, actions }:

# Node.js Build Job
#
# Builds a Node.js application and outputs the build artifacts.
#
# Parameters:
#   - nodeVersion (optional): Node.js version [default: "18"]
#   - buildScript (optional): npm script to run [default: "build"]
#   - outputDir (optional): Build output directory [default: "dist"]
#
# Outputs:
#   - dist: Build artifacts from output directory
#
# Example:
#   jobs.build = (jobs.nodeBuild {
#     nodeVersion = "20";
#     outputDir = "build";
#   }) // {
#     executor = executors.local;
#   };

{
  nodeVersion ? "18",
  buildScript ? "build",
  outputDir ? "dist",
}:

{
  executor = null;
  
  actions = [
    actions.checkout
    (actions.setupNode { version = nodeVersion; })
    actions.npm.install
    (actions.runCommand "npm run ${buildScript}")
  ];
  
  # Outputs are fixed for this job template
  outputs = {
    dist = "${outputDir}/";  # Save entire output directory
  };
}
```

**Usage:**
```nix
jobs.build = (jobs.nodeBuild { 
  nodeVersion = "20"; 
}) // { 
  executor = executors.local; 
};

# Later jobs can use the "dist" artifact
jobs.deploy = {
  executor = executors.local;
  needs = [ "build" ];
  inputs = [ "dist" ];  # Restores dist/ directory
  actions = [
    (actions.runCommand "deploy-to-prod dist/")
  ];
};
```

---

## Pattern 2: Job with Inputs and Outputs

Job that consumes artifacts and produces new ones:

```nix
# lib/jobs/docker-build.nix
{ pkgs, lib, actions }:

# Docker Build Job
#
# Builds Docker images from build artifacts.
#
# Parameters:
#   - registry (required): Container registry
#   - images (required): List of images to build
#   - buildArtifact (optional): Artifact name to use for build context [default: "dist"]
#   - tag (optional): Image tag [default: "latest"]
#
# Inputs:
#   - {buildArtifact}: Build artifacts (default: "dist")
#
# Outputs:
#   - None (images are pushed to registry)
#
# Needs:
#   - Must be set by user to job that produces buildArtifact
#
# Example:
#   jobs.dockerBuild = (jobs.dockerBuild {
#     registry = "myregistry.io";
#     images = [ { name = "api"; } ];
#   }) // {
#     executor = executors.local;
#     needs = [ "build" ];  # Depends on build job
#   };

{
  registry,
  images,
  buildArtifact ? "dist",
  tag ? "latest",
}:

{
  executor = null;
  
  # Template requires this input artifact
  inputs = [ buildArtifact ];
  
  # Note: needs must be specified by user!
  # needs = [ "build" ];  // User sets this
  
  actions = [
    actions.checkout
  ] ++ (actions.buildImages {
    inherit registry images tag;
    operation = "build-and-push";
  });
  
  # This job doesn't save artifacts (pushes to registry instead)
  outputs = {};
}
```

**Usage:**
```nix
jobs = {
  build = (jobs.nodeBuild {}) // {
    executor = executors.local;
  };
  
  dockerize = (jobs.dockerBuild {
    registry = "myregistry.io";
    images = [ { name = "api"; } ];
  }) // {
    executor = executors.local;
    needs = [ "build" ];  # User specifies dependency
  };
};
```

---

## Pattern 3: Flexible Inputs/Outputs

Job template with configurable inputs and outputs:

```nix
# lib/jobs/test-runner.nix
{ pkgs, lib, actions }:

# Test Runner Job
#
# Runs tests on build artifacts.
#
# Parameters:
#   - testFramework (required): "jest" | "pytest" | "cargo"
#   - testScript (optional): Custom test command [default: framework default]
#   - requireBuild (optional): Whether to require build artifacts [default: true]
#   - buildArtifact (optional): Artifact name if requireBuild=true [default: "dist"]
#   - saveResults (optional): Save test results as artifact [default: false]
#   - resultsPath (optional): Path to test results [default: "test-results/"]
#
# Inputs:
#   - {buildArtifact} (conditional): Only if requireBuild=true
#
# Outputs:
#   - test-results (conditional): Only if saveResults=true
#
# Example:
#   # With build artifacts
#   jobs.test = (jobs.testRunner {
#     testFramework = "jest";
#     requireBuild = true;
#     saveResults = true;
#   }) // {
#     executor = executors.local;
#     needs = [ "build" ];
#   };
#   
#   # Without build artifacts (unit tests)
#   jobs.unitTest = (jobs.testRunner {
#     testFramework = "jest";
#     requireBuild = false;
#   }) // {
#     executor = executors.local;
#   };

{
  testFramework,
  testScript ? null,
  requireBuild ? true,
  buildArtifact ? "dist",
  saveResults ? false,
  resultsPath ? "test-results/",
}:

let
  defaultTestCommands = {
    jest = "npm test";
    pytest = "pytest";
    cargo = "cargo test";
  };
  
  actualTestCommand = 
    if testScript != null 
    then testScript 
    else defaultTestCommands.${testFramework};
in

{
  executor = null;
  
  # Conditional inputs
  inputs = lib.optional requireBuild buildArtifact;
  
  actions = [
    actions.checkout
    (actions.runCommand actualTestCommand)
  ];
  
  # Conditional outputs
  outputs = lib.optionalAttrs saveResults {
    test-results = resultsPath;
  };
}
```

**Usage:**
```nix
jobs = {
  build = (jobs.nodeBuild {}) // {
    executor = executors.local;
  };
  
  # Integration tests need build
  integrationTest = (jobs.testRunner {
    testFramework = "jest";
    testScript = "npm run test:integration";
    requireBuild = true;
    saveResults = true;
  }) // {
    executor = executors.local;
    needs = [ "build" ];
  };
  
  # Unit tests don't need build
  unitTest = (jobs.testRunner {
    testFramework = "jest";
    testScript = "npm run test:unit";
    requireBuild = false;
  }) // {
    executor = executors.local;
  };
};
```

---

## Pattern 4: Multi-Job Template with Internal Dependencies

Job template that returns multiple jobs with dependencies:

```nix
# lib/jobs/full-pipeline.nix
{ pkgs, lib, actions }:

# Full CI/CD Pipeline
#
# Complete pipeline: build → test → deploy
#
# Parameters:
#   - language (required): "node" | "python" | "rust"
#   - version (optional): Language version [default: language-specific]
#   - runTests (optional): Include test stage [default: true]
#   - deployTarget (optional): Deploy to this target [default: null (skip deploy)]
#
# Jobs returned:
#   - build: Builds the application
#     - Outputs: dist (build artifacts)
#   
#   - test: Runs tests (optional)
#     - Needs: build
#     - Inputs: dist
#     - Outputs: test-results
#   
#   - deploy: Deploys application (optional)
#     - Needs: test (if runTests) or build
#     - Inputs: dist
#
# Example:
#   jobs = (jobs.fullPipeline {
#     language = "node";
#     version = "20";
#     runTests = true;
#     deployTarget = "production";
#   }) // {
#     build.executor = executors.local;
#     test.executor = executors.local;
#     deploy.executor = executors.local;
#   };

{
  language,
  version ? null,
  runTests ? true,
  deployTarget ? null,
}:

let
  # Language-specific defaults...
  # (same as before)
in

{
  # Build job - outputs artifacts
  build = {
    executor = null;
    
    actions = [
      actions.checkout
      # ... build actions
    ];
    
    outputs = {
      dist = "dist/";
    };
  };
  
  # Test job - inputs from build, outputs results
  test = lib.optionalAttrs runTests {
    executor = null;
    needs = [ "build" ];      # Explicit internal dependency
    inputs = [ "dist" ];       # Uses build output
    
    actions = [
      actions.checkout
      # ... test actions
    ];
    
    outputs = {
      test-results = "test-results/";
    };
  };
  
  # Deploy job - inputs from build
  deploy = lib.optionalAttrs (deployTarget != null) {
    executor = null;
    needs = if runTests then [ "test" ] else [ "build" ];  # Conditional dependency
    inputs = [ "dist" ];      # Uses build output
    
    actions = [
      # ... deploy actions
    ];
    
    outputs = {};  # No outputs
  };
}
```

**Key points:**
- **Internal needs**: Template sets `needs = [ "build" ]` internally
- **Internal inputs**: Template sets `inputs = [ "dist" ]` to match outputs
- **User just sets executors**: No need to wire dependencies manually

---

## Pattern 5: Parameterized Inputs/Outputs

Allow users to customize artifact names:

```nix
# lib/jobs/custom-build.nix
{ pkgs, lib, actions }:

{
  buildCommand,
  outputArtifactName ? "build-output",
  outputPath ? "dist/",
  inputArtifacts ? [],
}:

{
  executor = null;
  
  # User-specified inputs
  inputs = inputArtifacts;
  
  actions = [
    actions.checkout
    (actions.runCommand buildCommand)
  ];
  
  # User-specified output name
  outputs = {
    ${outputArtifactName} = outputPath;
  };
}
```

**Usage:**
```nix
jobs = {
  buildAPI = (jobs.customBuild {
    buildCommand = "make api";
    outputArtifactName = "api-dist";
    outputPath = "build/api/";
  }) // {
    executor = executors.local;
  };
  
  buildWorker = (jobs.customBuild {
    buildCommand = "make worker";
    outputArtifactName = "worker-dist";
    outputPath = "build/worker/";
  }) // {
    executor = executors.local;
  };
  
  deploy = {
    executor = executors.local;
    needs = [ "buildAPI" "buildWorker" ];
    inputs = [ "api-dist" "worker-dist" ];  # Custom artifact names
    actions = [
      (actions.runCommand "deploy-all")
    ];
  };
};
```

---

## Best Practices

### 1. Document Inputs/Outputs in Header

Always document what your job template produces and consumes:

```nix
# Job Template Name
#
# Description...
#
# Parameters:
#   - param1: ...
#
# Inputs:
#   - artifact1: Description of what this should contain
#   - artifact2 (optional): Only if condition=true
#
# Outputs:
#   - result: Description of what this produces
#   - logs (optional): Only if saveResults=true
#
# Needs:
#   - Must be set by user to: job-that-produces-artifact1
#
# Example:
#   ...
```

### 2. Use Descriptive Artifact Names

```nix
# Good
outputs = {
  frontend-bundle = "dist/frontend/";
  backend-binary = "bin/server";
  api-docs = "docs/api/";
};

# Bad
outputs = {
  out1 = "dist/";
  out2 = "bin/";
};
```

### 3. Make Inputs/Outputs Optional When Appropriate

```nix
{
  saveResults ? false,
  resultsPath ? "results/",
}:

{
  # ...
  outputs = lib.optionalAttrs saveResults {
    test-results = resultsPath;
  };
}
```

### 4. Set Internal Dependencies in Multi-Job Templates

```nix
# Good - template handles dependencies
{
  build = {
    outputs = { dist = "dist/"; };
  };
  
  test = {
    needs = [ "build" ];        # Template sets this
    inputs = [ "dist" ];        # Template sets this
  };
}

# User doesn't need to know internal wiring
jobs = (jobs.pipeline {}) // {
  build.executor = executors.local;
  test.executor = executors.local;
};
```

### 5. Allow Dependency Overrides When Needed

```nix
{
  buildJobName ? "build",  # Allow user to customize
}:

{
  test = {
    needs = [ buildJobName ];  # Use parameter
    inputs = [ "dist" ];
  };
}
```

---

## Anti-Patterns

### ❌ DON'T: Force needs in single-job templates

```nix
# BAD - User might want to use this job differently
{
  executor = null;
  needs = [ "build" ];  # Hardcoded!
  actions = [ ... ];
}
```

### ✅ DO: Let user specify needs

```nix
# GOOD - User controls dependencies
{
  executor = null;
  # needs is set by user
  inputs = [ "dist" ];  # Document what's needed
  actions = [ ... ];
}
```

### ❌ DON'T: Use ambiguous artifact names

```nix
# BAD
outputs = {
  output = "out/";
  result = "result/";
};
```

### ✅ DO: Use descriptive names

```nix
# GOOD
outputs = {
  compiled-app = "dist/";
  test-coverage = "coverage/";
};
```

### ❌ DON'T: Hardcode artifact names in actions

```nix
# BAD
actions = [
  (actions.runCommand "use-artifact dist/")  # Assumes "dist"
];
```

### ✅ DO: Use parameters or document assumptions

```nix
# GOOD
{ buildArtifact ? "dist" }:

{
  inputs = [ buildArtifact ];
  actions = [
    # Artifact is restored to working directory automatically
    (actions.runCommand "ls -la")  # Can see all restored artifacts
  ];
}
```

---

## Advanced: Dynamic Inputs/Outputs

For complex scenarios, compute inputs/outputs dynamically:

```nix
{
  services,  # [ "api" "worker" "frontend" ]
}:

let
  # Generate outputs for each service
  serviceOutputs = lib.listToAttrs (map (svc: {
    name = "${svc}-bundle";
    value = "dist/${svc}/";
  }) services);
  
  # Generate inputs for deploy
  deployInputs = map (svc: "${svc}-bundle") services;
in

{
  build = {
    executor = null;
    outputs = serviceOutputs;
    actions = [ ... ];
  };
  
  deploy = {
    executor = null;
    needs = [ "build" ];
    inputs = deployInputs;
    actions = [ ... ];
  };
}
```

---

## Summary

### For Single-Job Templates:
- **Document** required inputs/outputs clearly
- **Let user set** `needs` dependencies
- **Specify** `inputs` if artifacts are required
- **Define** `outputs` for artifacts produced

### For Multi-Job Templates:
- **Set internal** `needs` dependencies
- **Wire** inputs/outputs between jobs
- **Document** the overall flow
- **Allow** executor overrides for each job

### General Rules:
1. **Be explicit** about what you need and produce
2. **Document everything** in header comments
3. **Use descriptive** artifact names
4. **Make things optional** when it makes sense
5. **Test** with real workflows

---

## Next Steps

1. Review existing examples in `examples/` for inputs/outputs usage
2. Update `lib/jobs/STYLE_GUIDE.md` with these patterns
3. Create example job templates following these guidelines
4. Build real-world pipelines to validate the design
