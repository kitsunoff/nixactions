# Artifacts Management

Artifacts allow jobs to share files explicitly and safely.

---

## Philosophy

**Key principles:**

1. **Explicit transfer** - `inputs`/`outputs` API for reliable file sharing
2. **HOST-based storage** - `$NIXACTIONS_ARTIFACTS_DIR` exists ONLY on control node
3. **Executor transfers files** - `saveArtifact`/`restoreArtifact` copy between execution env and HOST
4. **Survives cleanup** - Artifacts stored outside workspace
5. **Custom restore paths** - Control where artifacts are restored in job directory

---

## Architecture

```
+---------------------------------------------------+
| CONTROL NODE (HOST)                               |
|                                                   |
|   $NIXACTIONS_ARTIFACTS_DIR/                      |
|   +-- dist/                                       |
|   |   +-- bundle.js                               |
|   +-- coverage/                                   |
|       +-- report.html                             |
|                                                   |
|   ^                                    |          |
|   | saveArtifact                       |          |
|   |                    restoreArtifact v          |
+---+-------------------------------------------+---+
    |                                           |
+---v-------------------------------------------v---+
| EXECUTION ENVIRONMENT (Container/Remote/Local)    |
|                                                   |
|   /workspace/jobs/build/                          |
|   +-- dist/              <- Created by job        |
|   |   +-- bundle.js                               |
|   +-- coverage/          <- Restored input        |
|       +-- report.html                             |
|                                                   |
+---------------------------------------------------+
```

---

## Declarative API

### Basic Usage

```nix
jobs = {
  build = {
    executor = nixactions.executors.local;
    
    # Declare outputs (what to save)
    outputs = {
      dist = "dist/";
      binary = "myapp";
    };
    
    steps = [{
      bash = ''
        npm run build
        # dist/ created in job directory
      '';
    }];
  };
  
  test = {
    needs = ["build"];
    executor = nixactions.executors.local;
    
    # Declare inputs (what to restore)
    inputs = [ "dist" "binary" ];
    
    steps = [{
      bash = ''
        # Artifacts restored before actions run
        ls dist/
        ./binary --version
      '';
    }];
  };
};
```

### Custom Restore Paths

Control where artifacts are restored:

```nix
inputs = [
  "dist"                              # Simple: restore to $JOB_DIR/
  { name = "libs"; path = "lib/"; }   # Custom: restore to $JOB_DIR/lib/
  { name = "config"; path = "etc/"; } # Custom: restore to $JOB_DIR/etc/
]
```

**Path semantics:**
- `.` or `./` - Root of job directory (default)
- `subdir/` - Subdirectory within job directory
- `../other/` - Relative to job directory (can go up)

---

## Use Cases

### Multiple Build Outputs

```nix
jobs = {
  build = {
    outputs = {
      frontend = "dist/frontend/";
      backend = "dist/backend/";
      shared = "dist/shared/";
    };
    steps = [{ bash = "npm run build:all"; }];
  };
  
  deploy = {
    needs = ["build"];
    inputs = [
      { name = "frontend"; path = "public/"; }
      { name = "backend"; path = "server/"; }
      { name = "shared"; path = "lib/"; }
    ];
    steps = [{
      bash = ''
        ls public/   # Frontend files
        ls server/   # Backend files
        ls lib/      # Shared files
      '';
    }];
  };
};
```

### Monorepo

```nix
jobs = {
  build-api = {
    outputs = { api = "services/api/dist/"; };
    steps = [{ bash = "cd services/api && npm run build"; }];
  };
  
  build-worker = {
    outputs = { worker = "services/worker/dist/"; };
    steps = [{ bash = "cd services/worker && npm run build"; }];
  };
  
  deploy = {
    needs = ["build-api" "build-worker"];
    inputs = [
      { name = "api"; path = "services/api/dist/"; }
      { name = "worker"; path = "services/worker/dist/"; }
    ];
    steps = [{
      bash = "deploy-monorepo.sh";
    }];
  };
};
```

### Test Coverage

```nix
jobs = {
  test = {
    outputs = {
      coverage = "coverage/";
    };
    steps = [{
      bash = "npm test -- --coverage";
    }];
  };
  
  upload-coverage = {
    needs = ["test"];
    inputs = ["coverage"];
    steps = [{
      bash = "codecov upload coverage/lcov.info";
    }];
  };
};
```

---

## Mixed Syntax

Old and new syntax can be mixed:

```nix
inputs = [
  "dist"                               # Old syntax (restore to root)
  { name = "config"; path = "etc/"; }  # New syntax (custom path)
]
```

Equivalent to:

```nix
inputs = [
  { name = "dist"; path = "."; }
  { name = "config"; path = "etc/"; }
]
```

---

## Generated Code

```bash
# Setup artifacts dir on HOST
NIXACTIONS_ARTIFACTS_DIR="$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"

job_build() {
  # Execute actions
  cd $JOB_DIR
  npm run build
  
  # Save outputs (on HOST)
  cp -r "$JOB_DIR/dist" "$NIXACTIONS_ARTIFACTS_DIR/dist/"
}

job_test() {
  # Restore inputs (on HOST)
  cp -r "$NIXACTIONS_ARTIFACTS_DIR/dist"/* "$JOB_DIR/"
  
  # Execute actions
  cd $JOB_DIR
  npm test
}
```

### OCI Executor

```bash
job_build() {
  docker exec $CONTAINER bash -c 'npm run build'
  
  # Save: docker cp from container to HOST
  docker cp "$CONTAINER:/workspace/jobs/build/dist" "$NIXACTIONS_ARTIFACTS_DIR/dist/"
}

job_test() {
  # Restore: docker cp from HOST to container
  docker cp "$NIXACTIONS_ARTIFACTS_DIR/dist" "$CONTAINER:/workspace/jobs/test/"
  
  docker exec $CONTAINER bash -c 'npm test'
}
```

---

## Executor Implementation

Each executor must implement `saveArtifact` and `restoreArtifact`:

```nix
# Local executor
saveArtifact = { name, path, jobName }: ''
  if [ -e "$JOB_DIR/${path}" ]; then
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
    cp -r "$JOB_DIR/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/"
  fi
'';

restoreArtifact = { name, path, jobName }: ''
  if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
    if [ "${path}" = "." ]; then
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}"/* "$JOB_DIR/"
    else
      mkdir -p "$JOB_DIR/${path}"
      cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}"/* "$JOB_DIR/${path}/"
    fi
  fi
'';
```

---

## Best Practices

### Name Artifacts Clearly

```nix
# Good: descriptive names
outputs = {
  frontend-dist = "dist/frontend/";
  backend-dist = "dist/backend/";
  test-coverage = "coverage/";
};

# Avoid: generic names
outputs = {
  files = "dist/";
  data = "output/";
};
```

### Use Custom Paths for Organization

```nix
# Good: organized structure
inputs = [
  { name = "frontend-dist"; path = "public/"; }
  { name = "backend-dist"; path = "server/"; }
];

# Result:
# $JOB_DIR/
#   public/    <- frontend files
#   server/    <- backend files
```

### Don't Over-Share

```nix
# Good: share only what's needed
outputs = {
  dist = "dist/";  # Built files only
};

# Avoid: sharing everything
outputs = {
  all = ".";  # Entire directory
};
```

---

## Limitations

1. **Artifacts are workflow-scoped** - Cleaned up when workflow ends
2. **No cross-workflow sharing** - Use external storage for that
3. **Size limits** - Large artifacts slow down transfers
4. **No streaming** - Entire artifact copied at once

---

## See Also

- [Executors](./executors.md) - Artifact transfer implementation
- [Core Contracts](./core-contracts.md) - Job inputs/outputs API
- [API Reference](./api-reference.md) - Full artifacts API
