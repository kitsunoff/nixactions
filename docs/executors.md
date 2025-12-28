# Executors

Executors define **where** and **how** jobs run.

---

## Overview

NixActions supports multiple executors:

| Executor | Status | Description |
|----------|--------|-------------|
| `local` | Implemented | Run on current machine |
| `oci` | Implemented | Run in Docker containers |
| `k8s` | Implemented | Run in Kubernetes pods |
| `ssh` | Planned | Run on remote hosts via SSH |
| `nixos-vm` | Planned | Run in NixOS VMs |

---

## Executor Contract (5-Hook Model)

All executors implement the same contract:

```nix
Executor :: {
  name     :: String,
  copyRepo :: Bool,
  
  # === WORKSPACE LEVEL ===
  setupWorkspace   :: { actionDerivations :: [Derivation] } -> Bash,
  cleanupWorkspace :: { actionDerivations :: [Derivation] } -> Bash,
  
  # === JOB LEVEL ===
  setupJob    :: { jobName :: String, actionDerivations :: [Derivation] } -> Bash,
  executeJob  :: { jobName :: String, actionDerivations :: [Derivation], env :: AttrSet } -> Bash,
  cleanupJob  :: { jobName :: String } -> Bash,
  
  # === ARTIFACTS ===
  saveArtifact    :: { name :: String, path :: String, jobName :: String } -> Bash,
  restoreArtifact :: { name :: String, path :: String, jobName :: String } -> Bash,
}
```

### Execution Flow

```
Workflow Start
==============
for each unique executor (by name):
  setupWorkspace({ actionDerivations = ALL actions using this executor })

Job Execution
=============
for each job:
  setupJob({ jobName, actionDerivations })
  for each input: restoreArtifact({ name, path, jobName })
  executeJob({ jobName, actionDerivations, env })
  for each output: saveArtifact({ name, path, jobName })
  cleanupJob({ jobName })

Workflow End (trap EXIT)
========================
for each unique executor:
  cleanupWorkspace({ actionDerivations })
```

---

## Local Executor

Runs jobs directly on the host machine in isolated directories.

### Configuration

```nix
platform.executors.local :: {
  copyRepo :: Bool = true,   # Copy repo to job directory
  name     :: String | Null = null,  # Custom name for workspace isolation
} -> Executor
```

### Usage

```nix
# Default
executor = platform.executors.local

# Without repo copy
executor = platform.executors.local { copyRepo = false; }

# Custom name (creates separate workspace)
executor = platform.executors.local { name = "build-env"; }
```

### Directory Structure

```
/tmp/nixactions/$WORKFLOW_ID/local/
+-- jobs/
    +-- job1/        # Job directory
    |   +-- (repo)   # Copy of repository (if copyRepo = true)
    |   +-- $JOB_ENV # Job environment file
    +-- job2/
    +-- ...
```

### Implementation Reference

```nix
mkExecutor {
  name = "local";
  copyRepo = true;
  
  setupWorkspace = { actionDerivations }: ''
    WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID/local"
    mkdir -p "$WORKSPACE_DIR_LOCAL/jobs"
    export WORKSPACE_DIR_LOCAL
  '';
  
  setupJob = { jobName, actionDerivations }: ''
    JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/${jobName}"
    mkdir -p "$JOB_DIR"
    
    # Copy repository if enabled
    if [ "$NIXACTIONS_COPY_REPO" = "true" ]; then
      cp -r "$PWD"/* "$JOB_DIR/"
    fi
    
    cd "$JOB_DIR"
  '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    # Set environment
    export KEY="value"
    
    # Execute actions
    for action in ${actionDerivations}; do
      $action/bin/action-name
    done
  '';
  
  cleanupWorkspace = { actionDerivations }: ''
    rm -rf "$WORKSPACE_DIR_LOCAL"
  '';
}
```

---

## OCI Executor

Runs jobs in Docker containers with images built via `pkgs.dockerTools.buildLayeredImage`.

### Configuration

```nix
platform.executors.oci :: {
  name          :: String | Null = null,
  mode          :: "shared" | "isolated" = "shared",
  copyRepo      :: Bool = true,
  extraPackages :: [Derivation] = [],
  extraMounts   :: [String] = [],
  containerEnv  :: AttrSet String = {},
} -> Executor
```

### Usage

```nix
# Default (shared mode)
executor = platform.executors.oci {}

# With extra packages (use linuxPkgs!)
executor = platform.executors.oci {
  extraPackages = [ platform.linuxPkgs.git platform.linuxPkgs.curl ];
}

# Isolated mode (container per job)
executor = platform.executors.oci {
  mode = "isolated";
}

# Custom name
executor = platform.executors.oci {
  name = "build-env";
}

# Additional mounts
executor = platform.executors.oci {
  extraMounts = [ "/data:/data:ro" ];
}
```

### Modes

#### Shared Mode (Default)

One container for all jobs using this executor:

```
setupWorkspace
    |
    +-> buildLayeredImage (all action derivations)
    +-> docker load
    +-> docker run -d
          |
          +-> setupJob(job1) -> mkdir /workspace/jobs/job1
          |   executeJob(job1) -> docker exec
          |   cleanupJob(job1)
          |
          +-> setupJob(job2) -> mkdir /workspace/jobs/job2
              ...
    |
cleanupWorkspace -> docker stop/rm
```

#### Isolated Mode

New container for each job:

```
setupJob(job1)
    +-> buildLayeredImage (job1 derivations)
    +-> docker run
    
executeJob(job1) -> docker exec

cleanupJob(job1) -> docker stop/rm

setupJob(job2) -> new container
    ...
```

### Cross-Platform Support

OCI executor automatically builds Linux images on Darwin:

| Host | Container | How |
|------|-----------|-----|
| `aarch64-darwin` | `aarch64-linux` | Uses `linuxPkgs` |
| `x86_64-darwin` | `x86_64-linux` | Uses `linuxPkgs` |
| Linux | Same arch | Uses same `pkgs` |

**Important:** Use `platform.linuxPkgs` for packages in OCI executor:

```nix
executor = platform.executors.oci {
  extraPackages = [ 
    platform.linuxPkgs.git 
    platform.linuxPkgs.nodejs 
  ];
}
```

### Image Contents

```nix
dockerTools.buildLayeredImage {
  name = "nixactions-${executorName}";
  tag = "latest";
  
  contents = [
    # Base utilities
    bash coreutils findutils gnugrep gnused
    
    # Runtime helpers
    loggingHelpers retryHelpers runtimeHelpers
    
    # Action derivations
  ] ++ actionDerivations ++ extraPackages;
}
```

---

## Executor Deduplication

Executors are deduplicated by `name`. Jobs with same executor share workspace:

### Same Executor (Shared Workspace)

```nix
jobs = {
  build = { 
    executor = platform.executors.oci {};  # name = "oci"
    ...
  };
  test = { 
    executor = platform.executors.oci {};  # name = "oci" (SAME!)
    ...
  };
}

# Result:
# - 1 workspace
# - 1 call to setupWorkspace with ALL actions
# - 2 job directories: /workspace/jobs/build, /workspace/jobs/test
```

### Custom Names (Separate Workspaces)

```nix
jobs = {
  build = { 
    executor = platform.executors.oci { name = "build-env"; };
    ...
  };
  test = { 
    executor = platform.executors.oci { name = "test-env"; };
    ...
  };
}

# Result:
# - 2 workspaces
# - 2 calls to setupWorkspace (one per executor)
# - Complete isolation
```

### Why This Matters

**actionDerivations aggregation enables:**

1. **Dependency pre-loading** - Executor knows ALL dependencies
2. **Shared resource allocation** - Create shared caches, volumes
3. **Custom image building** - Bake all actions into one image

---

## SSH Executor (Planned)

Execute jobs on remote hosts via SSH.

### Configuration

```nix
platform.executors.ssh {
  # Required
  host = "build-server.example.com";
  user = "builder";
  
  # Optional
  port = 22;
  identityFile = "~/.ssh/id_ed25519";
  
  # Mode
  mode = "shared";  # "shared" | "dedicated" | "pool"
  
  # Pool mode only
  hosts = [ "build-1" "build-2" "build-3" ];
  
  # Behavior
  copyRepo = true;
  workspaceDir = "/tmp/nixactions";
  
  # Custom name
  name = null;
}
```

### Modes

- **Shared**: One connection serves multiple jobs
- **Dedicated**: New connection per job
- **Pool**: Round-robin across multiple hosts

### Usage Examples

```nix
# Basic SSH
executor = platform.executors.ssh {
  host = "build.example.com";
  user = "ci";
};

# Dedicated mode for security
executor = platform.executors.ssh {
  host = "scanner.example.com";
  user = "ci";
  mode = "dedicated";
};

# Pool for parallel builds
executor = platform.executors.ssh {
  hosts = [ "linux-1" "linux-2" "linux-3" ];
  user = "builder";
  mode = "pool";
};
```

---

## Kubernetes Executor

Run jobs in Kubernetes pods with custom Nix-built images.

### How It Works

1. **Build phase** (`nix build`): Builds OCI image with all action derivations
2. **Setup phase** (`nix run`):
   - Loads image locally via `docker load`
   - Pushes to configured registry
   - Creates pod with `kubectl run`
   - Copies repository to pod as "golden standard"
3. **Job execution**: Jobs run via `kubectl exec` in the pod
4. **Cleanup**: Pod deleted on workflow completion

### Configuration

```nix
platform.executors.k8s {
  # === Required ===
  namespace = "ci";
  
  registry = {
    url = "ghcr.io/myorg";       # Container registry URL
    usernameEnv = "REGISTRY_USER";     # Env var with username
    passwordEnv = "REGISTRY_PASSWORD"; # Env var with password/token
  };
  
  # === Mode ===
  mode = "shared";        # "shared" (one pod) | "dedicated" (pod per job)
  
  # === Standard Options ===
  copyRepo = true;
  name = null;            # Custom executor name
  extraPackages = [];     # Additional packages in image
  containerEnv = {};      # Environment variables in container
  
  # === Kubeconfig ===
  kubeconfigEnv = null;   # Env var with path to kubeconfig (default: ~/.kube/config)
  contextEnv = null;      # Env var with context name (default: current context)
  
  # === Pod Spec ===
  serviceAccount = null;
  nodeSelector = {};
  resources = {
    requests = { cpu = "500m"; memory = "1Gi"; };
    limits = { cpu = "2"; memory = "4Gi"; };
  };
  labels = {};
  annotations = {};
  
  # === Timeouts ===
  podReadyTimeout = 300;  # 5 minutes (fail if pod not ready)
}
```

### Usage Examples

```nix
# Basic K8s with GitHub Container Registry
executor = platform.executors.k8s {
  namespace = "ci";
  registry = {
    url = "ghcr.io/myorg";
    usernameEnv = "GITHUB_USER";
    passwordEnv = "GITHUB_TOKEN";
  };
};

# Local registry for testing
executor = platform.executors.k8s {
  namespace = "default";
  registry = {
    url = "localhost:5000";
    usernameEnv = "REGISTRY_USER";
    passwordEnv = "REGISTRY_PASSWORD";
  };
};

# Dedicated mode (pod per job)
executor = platform.executors.k8s {
  namespace = "ci";
  registry = { ... };
  mode = "dedicated";
};

# With GPU
executor = platform.executors.k8s {
  namespace = "ml";
  registry = { ... };
  nodeSelector = { "nvidia.com/gpu.present" = "true"; };
  resources.limits = { "nvidia.com/gpu" = "1"; };
};

# Custom kubeconfig
executor = platform.executors.k8s {
  namespace = "ci";
  registry = { ... };
  kubeconfigEnv = "KUBECONFIG";
  contextEnv = "KUBE_CONTEXT";
};
```

### Modes

#### Shared Mode (Default)

One pod serves all jobs in the workflow:

```
setupWorkspace
    |
    +-> docker load/tag/push
    +-> kubectl run pod
    +-> kubectl cp $PWD → pod:/workspace/.golden
          |
          +-> setupJob(job1) → cp .golden → jobs/job1
          |   executeJob(job1) → kubectl exec
          |   cleanupJob(job1) → (nothing)
          |
          +-> setupJob(job2) → cp .golden → jobs/job2
              executeJob(job2) → kubectl exec
              ...
    |
cleanupWorkspace → kubectl delete pod
```

**Pros:** Faster (no pod startup per job), shared workspace
**Cons:** Less isolation between jobs

#### Dedicated Mode

Each job gets its own pod:

```
setupWorkspace → docker load/tag/push (once)

setupJob(job1)
    +-> kubectl run pod-job1
    +-> kubectl cp $PWD → pod:/workspace
executeJob(job1) → kubectl exec
cleanupJob(job1) → kubectl delete pod

setupJob(job2) → new pod
    ...
```

**Pros:** Full isolation, parallel job support
**Cons:** Slower (pod startup per job)

### Workspace Structure

```
/workspace/
├── .golden/          ← Repository copy (shared mode only)
└── jobs/
    ├── build/        ← Job working directory
    └── test/
```

### Prerequisites

1. **Kubernetes cluster** accessible via `kubectl`
2. **Container registry** with push access
3. **Environment variables** for registry auth:
   ```bash
   export REGISTRY_USER=myuser
   export REGISTRY_PASSWORD=mytoken
   ```

### Testing with Local Registry

```bash
# Start local registry
docker run -d -p 5000:5000 --name registry registry:2

# Run K8s example (uses localhost:5000 by default)
REGISTRY_USER=unused REGISTRY_PASSWORD=unused \
  nix run .#example-test-k8s-shared
```

### Troubleshooting

**Pod not ready:**
- Check pod events: `kubectl describe pod nixactions-...`
- Check pod logs: `kubectl logs nixactions-...`
- Increase `podReadyTimeout` if image pull is slow

**Registry auth failed:**
- Verify env vars are set: `echo $REGISTRY_USER`
- Test manually: `docker login <registry>`

**kubectl cp failed:**
- Ensure `tar` is available in the image (included by default)

---

## NixOS VM Executor (Planned)

Run jobs in ephemeral NixOS virtual machines.

### Configuration

```nix
platform.executors.nixosVm {
  # Configuration
  configuration = ./vm-config.nix;
  # OR
  modules = [
    ({ pkgs, ... }: {
      environment.systemPackages = [ pkgs.nodejs ];
    })
  ];
  
  # Resources
  memory = 4096;  # MB
  cores = 2;
  diskSize = 10240;  # MB
  
  # Mode
  mode = "dedicated";
  
  # Behavior
  copyRepo = true;
  name = null;
}
```

### Use Cases

- Testing NixOS configurations
- Full isolation requirements
- Reproducible test environments

---

## Creating Custom Executors

Use `mkExecutor` to create custom executors:

```nix
platform.mkExecutor {
  name = "custom";
  copyRepo = true;
  
  setupWorkspace = { actionDerivations }: ''
    echo "Setting up workspace with ${toString (length actionDerivations)} actions"
    mkdir -p /workspace
  '';
  
  cleanupWorkspace = { actionDerivations }: ''
    rm -rf /workspace
  '';
  
  setupJob = { jobName, actionDerivations }: ''
    mkdir -p /workspace/jobs/${jobName}
  '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    cd /workspace/jobs/${jobName}
    ${lib.concatMapStringsSep "\n" (action: ''
      ${action}/bin/${action.passthru.name}
    '') actionDerivations}
  '';
  
  cleanupJob = { jobName }: ''
    # Optional cleanup
  '';
  
  saveArtifact = { name, path, jobName }: ''
    cp -r "/workspace/jobs/${jobName}/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/"
  '';
  
  restoreArtifact = { name, path, jobName }: ''
    cp -r "$NIXACTIONS_ARTIFACTS_DIR/${name}/"* "/workspace/jobs/${jobName}/${path}/"
  '';
}
```

---

## Comparison

| Executor | Startup | Isolation | Use Case |
|----------|---------|-----------|----------|
| Local | Instant | Directory | Development, simple CI |
| OCI (shared) | Fast | Container | Docker-based workflows |
| OCI (isolated) | Medium | Container | Clean container per job |
| SSH (shared) | Fast | Directory | Remote builds |
| SSH (dedicated) | Medium | Connection | Security-sensitive |
| SSH (pool) | Fast | Directory | Parallel builds |
| NixOS VM | Slow | Full VM | NixOS testing, full isolation |
| K8s (shared) | Fast | Pod | Enterprise CI/CD |
| K8s (dedicated) | Medium | Pod | Stateless runners |

---

## Decision Matrix

```
Need isolation?
  |
  +-- No
  |    +-- Fast? --> Local/OCI (shared)
  |    +-- Remote? --> SSH (shared)
  |
  +-- Container level
  |    +-- Kubernetes? --> K8s
  |    +-- Docker? --> OCI (isolated)
  |
  +-- Full isolation
       +-- NixOS testing? --> NixOS VM
       +-- Security? --> SSH (dedicated)
```

---

## See Also

- [Core Contracts](./core-contracts.md) - Executor contract details
- [Architecture](./architecture.md) - System overview
- [API Reference](./api-reference.md) - Full executor API
