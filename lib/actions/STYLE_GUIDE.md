# NixActions - Actions Library Style Guide

This document defines the coding standards and patterns for creating actions in NixActions.

## Table of Contents

1. [Philosophy](#philosophy)
2. [Action Types](#action-types)
3. [API Patterns](#api-patterns)
4. [Naming Conventions](#naming-conventions)
5. [Structure](#structure)
6. [Documentation](#documentation)
7. [Examples](#examples)
8. [Testing](#testing)

---

## Philosophy

**Actions are reusable, composable units of work.**

Core principles:
- **Simple by default** - Most actions should be simple attribute sets
- **Functional** - Actions are pure functions that return action definitions
- **Composable** - Actions can be combined and nested
- **Type-safe** - Use Nix's type system to catch errors early
- **Self-contained** - Include all dependencies in `deps` attribute
- **Documented** - Every action should have clear documentation

---

## Action Types

### 1. Simple Action

A simple action is just an attribute set with `name` and `bash`:

```nix
{ pkgs, lib }:

{
  name = "hello";
  bash = ''
    echo "Hello, World!"
  '';
}
```

**Use when:**
- No parameters needed
- Single purpose
- No dependencies

### 2. Parameterized Action

A function that takes arguments and returns an action:

```nix
{ pkgs, lib }:

message:

{
  name = "greet";
  bash = ''
    echo "${message}"
  '';
}
```

**Use when:**
- Needs configuration
- Reusable with different values
- Dynamic behavior

### 3. Action Collection

An attribute set of related actions:

```nix
{ pkgs, lib }:

{
  npmInstall = {
    name = "npm-install";
    deps = [ pkgs.nodejs ];
    bash = ''
      npm install
    '';
  };
  
  npmTest = {
    name = "npm-test";
    deps = [ pkgs.nodejs ];
    bash = ''
      npm test
    '';
  };
}
```

**Use when:**
- Multiple related actions
- Common dependencies
- Logical grouping (e.g., npm, docker, git)

### 4. Complex/Composable Action

A function that returns multiple actions or generates actions dynamically:

```nix
{ pkgs, lib }:

{ images, registry, ... }:

# Returns a LIST of actions
map (image: {
  name = "build-${image.name}";
  deps = [ pkgs.docker ];
  bash = ''
    docker build -t ${registry}/${image.name} .
    docker push ${registry}/${image.name}
  '';
}) images
```

**Use when:**
- Needs to generate multiple actions
- Complex workflows (like build-images example)
- Advanced use cases

---

## API Patterns

### Pattern 1: Zero-Config Action

```nix
{ pkgs, lib }:

{
  name = "checkout";
  bash = ''
    git clone $REPO_URL .
  '';
}
```

**Characteristics:**
- No function wrapper
- Direct attribute set
- Import and use directly

**Usage:**
```nix
actions = [
  actions.checkout
];
```

### Pattern 2: Simple Parameters

```nix
{ pkgs, lib }:

packages:  # Single parameter, no destructuring

{
  name = "nix-shell";
  bash = ''
    nix-shell -p ${lib.concatStringsSep " " packages}
  '';
}
```

**Characteristics:**
- Single parameter (can be a list, string, etc.)
- No default values needed
- Positional argument

**Usage:**
```nix
actions = [
  (actions.nixShell [ "curl" "jq" "git" ])
];
```

### Pattern 3: Named Parameters (Attribute Set)

```nix
{ pkgs, lib }:

{ 
  registry,
  tag,
  dockerfile ? "Dockerfile",  # Optional with default
  buildArgs ? {},
}:

{
  name = "docker-build";
  deps = [ pkgs.docker ];
  bash = ''
    docker build \
      -f ${dockerfile} \
      -t ${registry}:${tag} \
      ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--build-arg ${k}=${v}") buildArgs)} \
      .
  '';
}
```

**Characteristics:**
- Named parameters with destructuring
- Optional parameters with defaults
- Self-documenting

**Usage:**
```nix
actions = [
  (actions.dockerBuild {
    registry = "myregistry.io/myapp";
    tag = "v1.0.0";
    buildArgs = { PLATFORM = "linux/amd64"; };
  })
];
```

### Pattern 4: Composable Action (Returns List)

```nix
{ pkgs, lib }:

{ images, registry, operation ? "build-and-push" }:

# Returns a LIST of actions, not a single action
map (image: {
  name = "build-${image.name}";
  deps = [ pkgs.docker ];
  bash = ''
    docker build -t ${registry}/${image.name} .
    ${lib.optionalString (operation == "build-and-push") "docker push ${registry}/${image.name}"}
  '';
}) images
```

**Characteristics:**
- Returns `[ action1 action2 ... ]` instead of single action
- Generates multiple actions from input
- Spread into actions list with `++`

**Usage:**
```nix
actions = [
  actions.checkout
] ++ (actions.buildImages {
  registry = "myregistry.io";
  images = [
    { name = "image1"; }
    { name = "image2"; }
  ];
});
```

---

## Naming Conventions

### File Names

- **Lowercase with hyphens**: `docker-build.nix`, `setup-node.nix`
- **Descriptive**: Name should indicate purpose
- **Group related actions**: `npm.nix` contains multiple npm actions

### Action Names

Use `name` attribute for runtime identification:

```nix
{
  name = "npm-install";  # Kebab-case, descriptive
  bash = "npm install";
}
```

**Rules:**
- Kebab-case (lowercase with hyphens)
- Verb-noun format when possible: `build-image`, `run-tests`, `deploy-app`
- Prefix with category for grouped actions: `npm-install`, `docker-build`

### Function Names (for attribute sets)

When exporting multiple actions from one file:

```nix
{
  npmInstall = { ... };   # camelCase for Nix attributes
  npmTest = { ... };
  npmBuild = { ... };
}
```

**Rules:**
- camelCase for Nix attribute names
- Verb-first: `installDeps`, `runTests`, `buildImage`

---

## Structure

### Minimal Action

```nix
{ pkgs, lib }:

{
  name = "action-name";
  bash = ''
    echo "Action code here"
  '';
}
```

### Complete Action (All Fields)

```nix
{ pkgs, lib }:

{
  # Required: unique identifier
  name = "action-name";
  
  # Required: bash script to execute
  bash = ''
    echo "Action implementation"
  '';
  
  # Optional: runtime dependencies (added to PATH)
  deps = [ pkgs.curl pkgs.jq ];
  
  # Optional: retry configuration
  retry = {
    maxAttempts = 3;
    backoff = "exponential";  # or "linear" or "constant"
    initialDelay = 1;
  };
  
  # Optional: execution condition
  condition = "success()";  # or "failure()" or "always()" or bash expression
  
  # Optional: continue on error
  continueOnError = false;
}
```

### File Template

```nix
{ pkgs, lib }:

# Brief description of what this action does
#
# Usage:
#   actionName { param1 = "value"; }
#
# Parameters:
#   - param1 (required): Description
#   - param2 (optional): Description [default: value]
#
# Example:
#   actions = [
#     (actions.actionName { param1 = "example"; })
#   ];

{ 
  param1,
  param2 ? "default-value",
}:

{
  name = "action-name";
  deps = [ pkgs.dependency ];
  bash = ''
    echo "Implementation using ${param1}"
  '';
}
```

---

## Documentation

### File Header Comment

Every action file MUST have a header comment:

```nix
{ pkgs, lib }:

# Docker Build Action
#
# Builds a Docker image with the specified configuration.
#
# Usage:
#   dockerBuild { 
#     registry = "myregistry.io/myapp"; 
#     tag = "v1.0.0"; 
#   }
#
# Parameters:
#   - registry (required): Full registry path (e.g., "docker.io/username/image")
#   - tag (required): Image tag
#   - dockerfile (optional): Path to Dockerfile [default: "Dockerfile"]
#   - buildArgs (optional): Build arguments as attribute set [default: {}]
#   - context (optional): Build context directory [default: "."]
#
# Dependencies:
#   - docker
#
# Example:
#   actions = [
#     (actions.dockerBuild {
#       registry = "myregistry.io/myapp";
#       tag = "latest";
#       buildArgs = { PLATFORM = "linux/amd64"; };
#     })
#   ];
#
# Returns:
#   Single action that builds and tags a Docker image

{ registry, tag, dockerfile ? "Dockerfile", ... }:
# ... implementation
```

### Inline Comments

Add comments for:
- **Complex logic**: Explain WHY, not WHAT
- **Workarounds**: Document known issues
- **Side effects**: Environment modifications, file creation, etc.

```nix
{
  name = "nix-shell";
  bash = ''
    # Build environment with all packages
    ENV_PATH=$(nix-build --no-out-link -E '${buildEnvExpr}')
    
    # Persist to JOB_ENV so subsequent actions inherit PATH
    # This is critical for multi-action jobs
    if [ -n "''${JOB_ENV:-}" ]; then
      echo "export PATH=\"$ENV_PATH/bin:\$PATH\"" >> "$JOB_ENV"
    fi
  '';
}
```

---

## Examples

### Example 1: Simple Static Action

```nix
# lib/actions/checkout.nix
{ pkgs, lib }:

# Checkout Action
#
# Simulates checking out code from a repository.
# In production, this would perform: git clone $REPO_URL .
#
# Usage:
#   actions.checkout
#
# Example:
#   actions = [ actions.checkout ];

{
  name = "checkout";
  bash = ''
    echo "→ Checking out code"
    echo "  Working directory: $PWD"
    ls -la
  '';
}
```

### Example 2: Parameterized Action

```nix
# lib/actions/run-command.nix
{ pkgs, lib }:

# Run Command Action
#
# Executes an arbitrary shell command.
#
# Parameters:
#   - command (string): The command to run
#
# Example:
#   (actions.runCommand "echo 'Hello, World!'")

command:

{
  name = "run-command";
  bash = command;
}
```

### Example 3: Named Parameters with Defaults

```nix
# lib/actions/deploy.nix
{ pkgs, lib }:

# Deploy Action
#
# Deploys an application to the specified environment.
#
# Parameters:
#   - environment (required): Target environment (staging/production)
#   - version (required): Version to deploy
#   - region (optional): Deployment region [default: "us-east-1"]
#   - dryRun (optional): Perform dry run only [default: false]
#
# Example:
#   (actions.deploy {
#     environment = "production";
#     version = "v1.2.3";
#     region = "eu-west-1";
#   })

{
  environment,
  version,
  region ? "us-east-1",
  dryRun ? false,
}:

{
  name = "deploy-${environment}";
  deps = [ pkgs.kubectl pkgs.awscli2 ];
  bash = ''
    echo "→ Deploying to ${environment}"
    echo "  Version: ${version}"
    echo "  Region: ${region}"
    ${lib.optionalString dryRun "echo '  DRY RUN MODE'"}
    
    ${lib.optionalString (!dryRun) ''
      kubectl apply -f deployment.yaml
      kubectl set image deployment/app app=${version}
    ''}
  '';
}
```

### Example 4: Action Collection

```nix
# lib/actions/git.nix
{ pkgs, lib }:

# Git Actions Collection
#
# A collection of common git operations.
#
# Available actions:
#   - gitClone: Clone a repository
#   - gitCommit: Commit changes
#   - gitPush: Push to remote
#   - gitTag: Create a tag
#
# Usage:
#   actions.git.gitClone { url = "https://github.com/user/repo"; }
#   actions.git.gitCommit { message = "Update files"; }

{
  gitClone = { url, branch ? "main" }: {
    name = "git-clone";
    deps = [ pkgs.git ];
    bash = ''
      git clone --branch ${branch} ${url} .
    '';
  };
  
  gitCommit = { message, files ? "." }: {
    name = "git-commit";
    deps = [ pkgs.git ];
    bash = ''
      git add ${files}
      git commit -m "${message}"
    '';
  };
  
  gitPush = { remote ? "origin", branch ? "main" }: {
    name = "git-push";
    deps = [ pkgs.git ];
    bash = ''
      git push ${remote} ${branch}
    '';
  };
  
  gitTag = { tag, message ? "" }: {
    name = "git-tag";
    deps = [ pkgs.git ];
    bash = ''
      git tag -a ${tag} ${lib.optionalString (message != "") "-m '${message}'"}
      git push origin ${tag}
    '';
  };
}
```

### Example 5: Composable Action (Returns List)

```nix
# lib/actions/build-images.nix
{ pkgs, lib }:

# Build Images Action
#
# Builds and optionally pushes multiple Docker images.
#
# Parameters:
#   - registry (required): Container registry URL
#   - images (required): List of image configurations
#   - operation (optional): "build", "push", or "build-and-push" [default: "build-and-push"]
#   - tag (optional): Default tag for all images [default: "latest"]
#
# Image configuration:
#   - name (required): Image name
#   - dockerfile (optional): Path to Dockerfile [default: "Dockerfile"]
#   - context (optional): Build context [default: "."]
#   - buildArgs (optional): Build arguments as attribute set
#   - tags (optional): List of additional tags
#
# Usage:
#   This action returns a LIST of actions, use with ++
#
# Example:
#   actions = [
#     actions.checkout
#   ] ++ (actions.buildImages {
#     registry = "myregistry.io";
#     images = [
#       { 
#         name = "api"; 
#         buildArgs = { NODE_ENV = "production"; };
#       }
#       { 
#         name = "worker";
#         dockerfile = "Dockerfile.worker";
#       }
#     ];
#   });
#
# Returns:
#   List of actions (one per image)

{
  registry,
  images,
  operation ? "build-and-push",
  tag ? "latest",
}:

map (image: 
  let
    imageName = image.name;
    dockerfile = image.dockerfile or "Dockerfile";
    context = image.context or ".";
    buildArgs = image.buildArgs or {};
    additionalTags = image.tags or [];
    allTags = [ tag ] ++ additionalTags;
    
    buildArgsStr = lib.concatStringsSep " " 
      (lib.mapAttrsToList (k: v: "--build-arg ${k}=${lib.escapeShellArg v}") buildArgs);
    
    tagCommands = lib.concatMapStringsSep "\n" 
      (t: "docker tag ${registry}/${imageName}:${tag} ${registry}/${imageName}:${t}") 
      additionalTags;
    
    pushCommands = lib.concatMapStringsSep "\n"
      (t: "docker push ${registry}/${imageName}:${t}")
      allTags;
  in
  {
    name = "build-${imageName}";
    deps = [ pkgs.docker ];
    bash = ''
      echo "→ Building image: ${imageName}"
      
      # Build image
      docker build \
        -f ${dockerfile} \
        -t ${registry}/${imageName}:${tag} \
        ${buildArgsStr} \
        ${context}
      
      ${lib.optionalString (additionalTags != []) tagCommands}
      
      # Push if requested
      ${lib.optionalString (operation == "push" || operation == "build-and-push") ''
        echo "→ Pushing image: ${imageName}"
        ${pushCommands}
      ''}
    '';
  }
) images
```

---

## Testing

### Manual Testing

Create a test workflow in `examples/`:

```nix
# examples/test-my-action.nix
{ nixactions, pkgs }:

nixactions.mkWorkflow {
  name = "test-my-action";
  
  jobs.test = {
    executor = nixactions.executors.local;
    actions = [
      (nixactions.actions.myAction { param = "value"; })
    ];
  };
}
```

Build and run:
```bash
nix build .#example-test-my-action
./result/bin/test-my-action
```

### Integration Testing

Add to compile-examples:
```bash
./scripts/compile-examples.sh
```

Verify the generated script looks correct:
```bash
cat compiled-examples/test-my-action.sh
```

---

## Common Patterns

### 1. Environment Variables

```nix
{
  name = "use-env";
  bash = ''
    echo "User: $USER"
    echo "Custom var: ''${MY_VAR:-default}"
  '';
}
```

**Note:** Use `''${VAR}` to escape in Nix strings.

### 2. Conditional Logic

```nix
{
  name = "conditional";
  bash = ''
    ${lib.optionalString enableFeature ''
      echo "Feature enabled"
      run_feature_command
    ''}
    
    ${lib.optionalString (!enableFeature) ''
      echo "Feature disabled"
    ''}
  '';
}
```

### 3. Dependencies

```nix
{
  name = "use-tools";
  deps = [ 
    pkgs.curl 
    pkgs.jq 
    pkgs.git 
  ];
  bash = ''
    # These tools are now in PATH
    curl -s https://api.github.com | jq .
  '';
}
```

### 4. Multi-line Commands

```nix
{
  name = "complex";
  bash = ''
    # Use proper indentation
    if [ -f "package.json" ]; then
      echo "Found package.json"
      npm install
    else
      echo "No package.json found"
      exit 1
    fi
    
    # Use functions for clarity
    build_project() {
      echo "Building project..."
      npm run build
    }
    
    build_project
  '';
}
```

### 5. Error Handling

```nix
{
  name = "safe-action";
  bash = ''
    # Check prerequisites
    if ! command -v docker &> /dev/null; then
      echo "Error: docker not found"
      exit 1
    fi
    
    # Use || for fallbacks
    docker pull myimage || {
      echo "Warning: Could not pull image, using local"
    }
    
    # Clean up on failure
    cleanup() {
      echo "Cleaning up..."
      rm -rf temp/
    }
    trap cleanup EXIT
  '';
}
```

---

## Anti-Patterns

### ❌ DON'T: Hardcode values

```nix
# BAD
{
  name = "deploy";
  bash = ''
    kubectl apply -f deployment.yaml
    kubectl set image deployment/app app=myregistry.io/app:v1.2.3
  '';
}
```

### ✅ DO: Use parameters

```nix
# GOOD
{ registry, version }:
{
  name = "deploy";
  bash = ''
    kubectl apply -f deployment.yaml
    kubectl set image deployment/app app=${registry}:${version}
  '';
}
```

### ❌ DON'T: Mix concerns

```nix
# BAD - Does too many things
{
  name = "build-test-deploy";
  bash = ''
    npm install
    npm run build
    npm test
    kubectl apply -f deployment.yaml
  '';
}
```

### ✅ DO: Single responsibility

```nix
# GOOD - Separate actions
[
  actions.npm.install
  actions.npm.build
  actions.npm.test
  (actions.kubectl.apply { file = "deployment.yaml"; })
]
```

### ❌ DON'T: Ignore errors silently

```nix
# BAD
{
  bash = ''
    some_command || true  # Swallows all errors
  '';
}
```

### ✅ DO: Handle errors explicitly

```nix
# GOOD
{
  bash = ''
    if ! some_command; then
      echo "Warning: some_command failed, continuing anyway"
    fi
  '';
  
  # OR use continueOnError
  continueOnError = true;
}
```

---

## Checklist

Before submitting a new action, ensure:

- [ ] File name is kebab-case
- [ ] Action has descriptive `name` attribute
- [ ] Documentation header with usage example
- [ ] Parameters are documented with types and defaults
- [ ] Dependencies listed in `deps`
- [ ] Bash script is properly indented
- [ ] Error cases are handled
- [ ] Tested manually with example workflow
- [ ] Added to `lib/actions/default.nix` exports
- [ ] Follows one of the established patterns

---

## Questions?

When in doubt:
1. Look at existing actions in `lib/actions/`
2. Follow the pattern most similar to your use case
3. Keep it simple - start with Pattern 1 or 2
4. Add complexity only when needed

Remember: **Actions should be simple, focused, and reusable.**
