# Design: Custom Restore Paths for Inputs

**Status:** ✅ IMPLEMENTED (Dec 25, 2025)

## Problem

Currently, artifacts are always restored to the root of the job directory:

```nix
jobs.deploy = {
  inputs = [ "dist" "binary" ];  # Both restored to $JOB_DIR/
  # Result: $JOB_DIR/dist/..., $JOB_DIR/binary
};
```

**Issues:**
- Can't control where artifacts are restored
- Can't restore to subdirectories (e.g., `lib/`, `vendor/`)
- Can't namespace artifacts from different sources
- Name conflicts if multiple artifacts have same structure

## Use Cases

### 1. Multiple build outputs to different locations
```nix
# Want:
# - frontend dist -> public/
# - backend dist -> server/
# - shared libs -> lib/

inputs = [
  { name = "frontend-dist"; path = "public/"; }
  { name = "backend-dist"; path = "server/"; }
  { name = "shared-libs"; path = "lib/"; }
]
```

### 2. Monorepo with multiple services
```nix
# Want:
# - api build -> services/api/
# - worker build -> services/worker/
# - common -> shared/

inputs = [
  { name = "api-dist"; path = "services/api/dist/"; }
  { name = "worker-dist"; path = "services/worker/dist/"; }
  { name = "common"; path = "shared/"; }
]
```

### 3. Legacy systems with specific directory structure
```nix
# Want:
# - application -> /opt/app/
# - config -> /etc/app/
# - data -> /var/app/

inputs = [
  { name = "app-binary"; path = "/opt/app/"; }
  { name = "app-config"; path = "/etc/app/"; }
  { name = "app-data"; path = "/var/app/"; }
]
```

## Proposed Design

### API: Hybrid Approach

Support both simple strings (backward compatible) and attribute sets (with custom path):

```nix
inputs = [
  "dist"                              # Simple: restore to $JOB_DIR/
  { name = "libs"; path = "lib/"; }   # Custom: restore to $JOB_DIR/lib/
  { name = "config"; path = "../shared/"; }  # Relative paths allowed
]
```

### Syntax

**Simple (string):**
```nix
inputs = [ "artifact-name" ]
# Equivalent to:
inputs = [ { name = "artifact-name"; path = "."; } ]
```

**Custom path (attribute set):**
```nix
inputs = [
  {
    name = "artifact-name";  # Required: artifact to restore
    path = "target/dir/";     # Required: where to restore (relative to $JOB_DIR)
  }
]
```

**Path semantics:**
- `.` or `./` - Root of job directory (default)
- `subdir/` - Subdirectory within job directory
- `../other/` - Relative to job directory (can go up)
- `/absolute/` - Absolute path (use with caution!)

### Examples

#### Example 1: Default behavior (unchanged)
```nix
jobs.deploy = {
  needs = [ "build" ];
  inputs = [ "dist" ];  # Restored to $JOB_DIR/
  actions = [
    (actions.runCommand "ls dist/")  # Works as before
  ];
}
```

#### Example 2: Custom subdirectories
```nix
jobs.package = {
  needs = [ "build-frontend" "build-backend" ];
  inputs = [
    { name = "frontend"; path = "public/"; }
    { name = "backend"; path = "server/"; }
  ];
  actions = [
    (actions.runCommand ''
      ls public/    # Frontend files
      ls server/    # Backend files
    '')
  ];
}
```

#### Example 3: Mixed usage
```nix
jobs.test = {
  needs = [ "build" "lint" ];
  inputs = [
    "dist"                          # Default: to root
    { name = "lint-results"; path = "reports/"; }  # Custom: to reports/
  ];
  actions = [
    (actions.runCommand ''
      cat dist/package.json
      cat reports/lint.txt
    '')
  ];
}
```

#### Example 4: Monorepo
```nix
jobs.deploy-all = {
  needs = [ "build-api" "build-worker" "build-frontend" ];
  inputs = [
    { name = "api-dist"; path = "services/api/"; }
    { name = "worker-dist"; path = "services/worker/"; }
    { name = "frontend-dist"; path = "public/"; }
    { name = "shared-config"; path = "config/"; }
  ];
  actions = [
    (actions.runCommand "deploy-monorepo")
  ];
}
```

## Implementation

### 1. Update `mk-workflow.nix`

Normalize inputs to always be attribute sets:

```nix
# Convert inputs to normalized form
normalizeInput = input:
  if builtins.isString input
  then { name = input; path = "."; }
  else input;

normalizedInputs = map normalizeInput (job.inputs or []);
```

### 2. Update executor interface

Change `restoreArtifact` signature:

```nix
# Before
restoreArtifact = { name, jobName }: ''...''

# After
restoreArtifact = { name, path, jobName }: ''...''
```

### 3. Update `local-helpers.nix`

```bash
restore_local_artifact() {
  local name=$1
  local target_path=$2  # NEW: target path
  local job_name=$3
  
  JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/$job_name"
  
  if [ -e "$NIXACTIONS_ARTIFACTS_DIR/$name" ]; then
    # Create target directory
    TARGET="$JOB_DIR/$target_path"
    mkdir -p "$(dirname "$TARGET")"
    
    # Handle different path cases
    if [ "$target_path" = "." ] || [ "$target_path" = "./" ]; then
      # Restore to root
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$JOB_DIR/" 2>/dev/null || true
    else
      # Restore to specific path
      mkdir -p "$TARGET"
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/$name"/* "$TARGET/" 2>/dev/null || true
    fi
    
    return 0
  else
    _log_workflow artifact "$name" event "✗" "Artifact not found"
    return 1
  fi
}
```

### 4. Update `oci-helpers.nix`

Similar changes for OCI executor:

```bash
restore_oci_artifact() {
  local name=$1
  local target_path=$2  # NEW
  local job_name=$3
  local container_id=$4
  
  # Docker cp to specific path in container
  if [ "$target_path" = "." ]; then
    docker cp "$NIXACTIONS_ARTIFACTS_DIR/$name"/. "$container_id:$JOB_DIR/"
  else
    docker exec "$container_id" mkdir -p "$JOB_DIR/$target_path"
    docker cp "$NIXACTIONS_ARTIFACTS_DIR/$name"/. "$container_id:$JOB_DIR/$target_path/"
  fi
}
```

### 5. Update `local.nix` and `oci.nix`

```nix
restoreArtifact = { name, path, jobName }: ''
  restore_local_artifact "${name}" "${path}" "${jobName}"
'';
```

### 6. Update `mk-workflow.nix` restore logic

```nix
${lib.optionalString (normalizedInputs != []) ''
  # Restore artifacts
  _log_job "${jobName}" artifacts "${toString (map (i: i.name) normalizedInputs)}" event "→" "Restoring artifacts"
  ${lib.concatMapStringsSep "\n" (input: ''
    ${executor.restoreArtifact { 
      name = input.name; 
      path = input.path; 
      inherit jobName; 
    }}
    _log_job "${jobName}" artifact "${input.name}" path "${input.path}" event "✓" "Restored"
  '') normalizedInputs}
''}
```

## Migration Path

### Backward Compatibility

Existing code continues to work:

```nix
# Old syntax (still works)
inputs = [ "dist" "binary" ]

# Equivalent to:
inputs = [
  { name = "dist"; path = "."; }
  { name = "binary"; path = "."; }
]
```

### Gradual Migration

Users can mix old and new syntax:

```nix
inputs = [
  "dist"                              # Old syntax
  { name = "config"; path = "etc/"; } # New syntax
]
```

## Validation

Add assertions to catch common errors:

```nix
# In mk-workflow.nix
validateInput = input:
  assert lib.assertMsg (input ? name) "Input must have 'name' attribute";
  assert lib.assertMsg (input ? path) "Input must have 'path' attribute";
  assert lib.assertMsg (builtins.isString input.name) "Input 'name' must be a string";
  assert lib.assertMsg (builtins.isString input.path) "Input 'path' must be a string";
  input;
```

## Documentation Updates

### Update INPUTS_OUTPUTS_DESIGN.md

Add section on custom restore paths with examples.

### Update STYLE_GUIDE.md

Document best practices:
- When to use custom paths
- How to organize artifacts
- Naming conventions

## Testing

Create example workflows to test:

1. **Simple inputs** (backward compat)
2. **Custom paths** (subdirectories)
3. **Multiple artifacts** to different locations
4. **Relative paths** (going up directories)
5. **Absolute paths** (edge case)

## Questions

1. **Should we allow absolute paths?**
   - Pros: Maximum flexibility
   - Cons: Security concerns, executor-dependent
   - Decision: Allow but document risks

2. **Should we validate paths?**
   - Check for path traversal attempts?
   - Restrict to job directory?
   - Decision: Start permissive, add validation if needed

3. **Should path be required in attribute set?**
   - Alternative: `{ name = "artifact"; path ? "."; }`
   - Decision: Make required for explicitness

## Next Steps

1. Implement in `lib/executors/local-helpers.nix`
2. Update `lib/executors/oci-helpers.nix`
3. Modify `lib/mk-workflow.nix` normalization
4. Update executor interfaces
5. Add tests and examples
6. Update documentation
7. Migration guide for users
