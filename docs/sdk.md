# NixActions SDK

The SDK provides typed actions with eval-time validation and automatic bash code generation.

## Overview

Instead of writing raw bash steps, the SDK lets you define **typed actions** with:
- Declared inputs and outputs with types
- Eval-time validation (catch errors before running)
- Automatic bash code generation
- Step output passing between actions

## Quick Start

```nix
{ pkgs, nixactions, executor }:

let
  sdk = nixactions.sdk;
  types = sdk.types;

  # Define a typed action
  greet = sdk.mkAction {
    name = "greet";
    inputs = {
      name = types.string;
      style = types.withDefault (types.enum [ "formal" "casual" ]) "casual";
    };
    outputs = {
      message = types.string;
    };
    run = ''
      if [ "$INPUT_style" = "formal" ]; then
        OUTPUT_message="Good day, $INPUT_name."
      else
        OUTPUT_message="Hey $INPUT_name!"
      fi
      echo "$OUTPUT_message"
    '';
  };

  # Define another action that uses the output
  announce = sdk.mkAction {
    name = "announce";
    inputs = {
      message = types.string;
    };
    run = ''
      echo "=== $INPUT_message ==="
    '';
  };

in nixactions.mkWorkflow {
  name = "greeting-workflow";
  
  # Enable validation
  extensions = [ sdk.validation ];
  
  jobs.greet = {
    inherit executor;
    steps = [
      (greet { name = "World"; })
      (announce { message = sdk.stepOutput "greet" "message"; })
    ];
  };
}
```

## API Reference

### Types

```nix
types.string           # Any string value
types.int              # Integer (validated at runtime)
types.bool             # true/false
types.path             # File path (validated exists at runtime)
types.enum [ "a" "b" ] # One of the specified values
types.optional <type>  # Nullable version of type
types.array <type>     # List of values
types.withDefault <type> <value>  # Type with default value
```

### mkAction

```nix
sdk.mkAction {
  name = "action-name";        # Required: unique action name
  description = "...";         # Optional: for documentation
  inputs = { ... };            # Optional: typed input parameters
  outputs = { ... };           # Optional: typed output parameters
  run = ''...'';               # Required: bash script to execute
  packages = [ ... ];          # Optional: runtime dependencies
}
```

**Input Access**: Use `$INPUT_<name>` in your script.

**Output Setting**: Set `OUTPUT_<name>=value` in your script.

### Step Name Override with `as`

When calling the same action multiple times, use `as` to give each call a unique name:

```nix
steps = [
  (greet { name = "Alice"; as = "greet-alice"; })
  (greet { name = "Bob"; as = "greet-bob"; })
  
  # Reference specific step output
  (announce { message = sdk.stepOutput "greet-bob" "message"; })
];
```

Without `as`, repeated calls would overwrite each other's outputs.

### References

Reference values that are resolved at runtime:

```nix
# Output from a previous step in the same job
sdk.stepOutput "step-name" "output-name"

# Environment variable (resolved at runtime)
sdk.fromEnv "ENV_VAR_NAME"

# Matrix value (for matrix builds)
sdk.matrix "key"
```

### Validation

Enable eval-time validation with the `validation` extension:

```nix
nixactions.mkWorkflow {
  extensions = [ sdk.validation ];
  # ...
}
```

Validation checks:
- All required inputs are provided
- Input types are correct (for literal values)
- Default values are applied

For stricter validation including step reference checking:

```nix
extensions = [ sdk.fullValidation ];
```

## How It Works

### Input Resolution

1. User provides input values when calling the action
2. Missing inputs use defaults from type definitions
3. Refs (like `stepOutput`) are converted to bash variable expansions
4. Literals are escaped and quoted

### Output Persistence

1. Action sets `OUTPUT_<name>=value`
2. SDK appends export to `$JOB_ENV` file
3. Next action sources `$JOB_ENV` before running
4. Variable becomes available as `$STEP_OUTPUT_<stepname>_<outputname>`

### Type Validation

**Eval-time** (Nix evaluation):
- Checks input values match declared types
- Refs skip validation (resolved at runtime)

**Runtime** (bash execution):
- Types like `int`, `bool`, `path` validate actual values
- Generates bash code for validation

## Examples

### Action with Optional Input

```nix
deploy = sdk.mkAction {
  name = "deploy";
  inputs = {
    environment = types.string;
    dryRun = types.optional types.bool;
  };
  run = ''
    if [ "$INPUT_dryRun" = "true" ]; then
      echo "DRY RUN: would deploy to $INPUT_environment"
    else
      echo "Deploying to $INPUT_environment"
    fi
  '';
};

# Usage
(deploy { environment = "prod"; })              # dryRun is null
(deploy { environment = "prod"; dryRun = true; })
```

### Chaining Actions with Outputs

```nix
build = sdk.mkAction {
  name = "build";
  outputs = { artifact = types.string; };
  run = ''
    npm run build
    OUTPUT_artifact="dist/app.tar.gz"
  '';
};

upload = sdk.mkAction {
  name = "upload";
  inputs = { file = types.string; };
  run = ''
    aws s3 cp "$INPUT_file" s3://bucket/
  '';
};

# In workflow
steps = [
  (build {})
  (upload { file = sdk.stepOutput "build" "artifact"; })
];
```

### Using Environment References

```nix
push = sdk.mkAction {
  name = "push";
  inputs = {
    registry = types.string;
  };
  run = ''
    # Registry URL comes from workflow env or runtime
    docker push "$INPUT_registry/myapp:latest"
  '';
};

# In workflow - value from environment at runtime
jobs.push = {
  env.REGISTRY = "ghcr.io/myorg";
  steps = [
    (push { registry = sdk.fromEnv "REGISTRY"; })
  ];
};
```

## Comparison

| Feature | Raw Steps | SDK Actions |
|---------|-----------|-------------|
| Type checking | None | Eval + Runtime |
| Input validation | Manual | Automatic |
| Output passing | Manual via JOB_ENV | Automatic |
| Code reuse | Copy/paste | Define once, use many |
| Error messages | Runtime bash errors | Eval-time Nix errors |
