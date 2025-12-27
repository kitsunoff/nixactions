# NixActions Executor Design: SSH, NixOS VM, Kubernetes

## Executive Summary

Design document for three new executors:
1. **SSH Executor** - execute jobs on remote hosts via SSH
2. **NixOS VM Executor** - execute jobs in ephemeral NixOS virtual machines
3. **Kubernetes Executor** - execute jobs in Kubernetes pods

Each executor supports **two operating modes**:
- **Shared (Pool)** - multiple jobs share one runner
- **Dedicated (Isolated)** - each job gets its own runner

---

## Table of Contents

1. [General Architecture](#general-architecture)
2. [Shared vs Dedicated Runners](#shared-vs-dedicated-runners)
3. [SSH Executor](#ssh-executor)
4. [NixOS VM Executor](#nixos-vm-executor)
5. [Kubernetes Executor](#kubernetes-executor)
6. [Artifacts & Environment Transfer](#artifacts--environment-transfer)
7. [Security Model](#security-model)
8. [Implementation Roadmap](#implementation-roadmap)

---

## General Architecture

### Executor Contract (5-Hook Model)

All executors implement the standard contract:

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
Control Node (HOST)                    Remote (SSH/VM/K8s)
===================                    ====================

+------------------+
| nix run .#ci     |
+---------+--------+
          |
          v
+------------------+     setupWorkspace      +------------------+
| Setup workspace  | -------------------->   | Create runner    |
| (lazy init)      |     nix-copy-closure    | Copy derivations |
+---------+--------+                         +------------------+
          |
          v
+------------------+     setupJob            +------------------+
| Setup job        | -------------------->   | Create job dir   |
|                  |     copy repo           | Setup env        |
+---------+--------+                         +------------------+
          |
          v
+------------------+     restoreArtifact     +------------------+
| Restore inputs   | -------------------->   | Receive files    |
|                  |     scp/kubectl cp      |                  |
+---------+--------+                         +------------------+
          |
          v
+------------------+     executeJob          +------------------+
| Execute job      | -------------------->   | Run actions      |
|                  |     ssh/kubectl exec    | /nix/store/...   |
+---------+--------+                         +------------------+
          |
          v
+------------------+     saveArtifact        +------------------+
| Save outputs     | <--------------------   | Send files       |
|                  |     scp/kubectl cp      |                  |
+---------+--------+                         +------------------+
          |
          v
+------------------+     cleanupWorkspace    +------------------+
| Cleanup          | -------------------->   | Destroy runner   |
| (trap EXIT)      |                         | (if dedicated)   |
+------------------+                         +------------------+
```

---

## Shared vs Dedicated Runners

### Concept

**Shared Runner (Pool Mode):**
- One runner serves multiple jobs
- Runner exists independently of workflow
- Jobs get isolated directories inside the runner
- Suitable for: frequent builds, resource efficiency

**Dedicated Runner (Isolated Mode):**
- Each job gets its own runner
- Runner is created before job and destroyed after
- Full isolation between jobs
- Suitable for: security-sensitive tasks, clean environments

### Comparison Matrix

| Aspect | Shared | Dedicated |
|--------|--------|-----------|
| Startup time | Fast (runner ready) | Slow (runner creation) |
| Resource cost | Low (1 runner for N jobs) | High (N runners) |
| Isolation | Job directories | Full (separate runners) |
| State leakage | Possible (shared filesystem) | Impossible |
| Parallelism | Limited (1 runner) | Full (N runners) |
| Use case | CI/CD, builds | Security, testing |

### API Design

```nix
# Shared runner (default)
executor = platform.executors.ssh {
  host = "build-server.example.com";
  user = "builder";
  mode = "shared";  # default
};

# Dedicated runner
executor = platform.executors.ssh {
  host = "build-server.example.com";
  user = "builder";
  mode = "dedicated";  # new runner per job
};

# Pool of dedicated runners
executor = platform.executors.ssh {
  hosts = [
    "build-1.example.com"
    "build-2.example.com"
    "build-3.example.com"
  ];
  user = "builder";
  mode = "pool";  # round-robin distribution
};
```

### Mode Behaviors

#### Shared Mode
```
Workflow Start:
  +-- setupWorkspace()     <- Connect to existing runner, setup workspace dir
       +-- Copy derivations via nix-copy-closure (once)
       
Job 1:
  +-- setupJob()           <- Create /workspace/jobs/job1/
  +-- restoreArtifacts()   <- Copy to job dir
  +-- executeJob()         <- Run in job dir
  +-- saveArtifacts()      <- Copy from job dir
  +-- cleanupJob()         <- Remove job dir (optional)
  
Job 2:
  +-- setupJob()           <- Create /workspace/jobs/job2/
  ...
  
Workflow End:
  +-- cleanupWorkspace()   <- Remove workspace dir (runner stays)
```

#### Dedicated Mode
```
Job 1:
  +-- setupWorkspace()     <- Create new runner (VM/container/connection)
  |    +-- Copy derivations via nix-copy-closure
  +-- setupJob()           <- Create job dir
  +-- restoreArtifacts()
  +-- executeJob()
  +-- saveArtifacts()
  +-- cleanupJob()
  +-- cleanupWorkspace()   <- Destroy runner
  
Job 2:
  +-- setupWorkspace()     <- Create NEW runner
  ...
```

#### Pool Mode
```
Workflow Start:
  +-- Check available runners in pool
  
Job 1 (parallel):
  +-- Acquire runner-1 from pool
       +-- Execute job
       +-- Release runner-1 back to pool
       
Job 2 (parallel):
  +-- Acquire runner-2 from pool
       +-- Execute job
       +-- Release runner-2 back to pool
       
Job 3 (parallel):
  +-- Wait for available runner...
       +-- Acquire runner-1 (now free)
       +-- Execute job
       +-- Release runner-1
```

---

## SSH Executor

### Overview

Executes jobs on remote hosts via SSH. Requirements:
- SSH access to host
- Nix installed on remote host
- Permissions to copy closures

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
  workspaceDir = "/tmp/nixactions";  # on remote
  
  # Custom name for workspace isolation
  name = null;  # defaults to "ssh-${host}"
}
```

### Implementation

#### Type Signature

```nix
ssh :: {
  host         :: String,
  user         :: String,
  port         :: Int = 22,
  identityFile :: Path | Null = null,
  mode         :: "shared" | "dedicated" | "pool" = "shared",
  hosts        :: [String] = [],  # for pool mode
  copyRepo     :: Bool = true,
  workspaceDir :: String = "/tmp/nixactions",
  name         :: String | Null = null,
} -> Executor
```

#### Generated Code (Shared Mode)

```nix
# lib/executors/ssh.nix
{ pkgs, lib, mkExecutor }:

{
  host,
  user,
  port ? 22,
  identityFile ? null,
  mode ? "shared",
  hosts ? [],
  copyRepo ? true,
  workspaceDir ? "/tmp/nixactions",
  name ? null,
}:

let
  executorName = if name != null then name else "ssh-${host}";
  
  sshOpts = lib.concatStringsSep " " ([
    "-o StrictHostKeyChecking=accept-new"
    "-o BatchMode=yes"
    "-p ${toString port}"
  ] ++ lib.optional (identityFile != null) "-i ${identityFile}");
  
  sshCmd = "ssh ${sshOpts} ${user}@${host}";
  scpCmd = "scp ${sshOpts}";
  
  sshHelpers = import ./ssh-helpers.nix { inherit pkgs lib; };
in

mkExecutor {
  inherit copyRepo;
  name = executorName;
  
  # === WORKSPACE LEVEL ===
  
  setupWorkspace = { actionDerivations }: ''
    source ${sshHelpers}/bin/nixactions-ssh-executor
    
    # Initialize SSH connection
    SSH_HOST="${host}"
    SSH_USER="${user}"
    SSH_PORT="${toString port}"
    ${lib.optionalString (identityFile != null) ''SSH_IDENTITY="${identityFile}"''}
    export SSH_HOST SSH_USER SSH_PORT SSH_IDENTITY
    
    WORKSPACE_DIR_REMOTE="${workspaceDir}/$WORKFLOW_ID/${executorName}"
    export WORKSPACE_DIR_REMOTE
    
    # Create workspace on remote
    _log_workflow executor "${executorName}" host "${host}" event "->" "Setting up workspace"
    ${sshCmd} "mkdir -p $WORKSPACE_DIR_REMOTE"
    
    # Copy derivations to remote via nix-copy-closure
    _log_workflow executor "${executorName}" derivations "${toString (builtins.length actionDerivations)}" event "->" "Copying derivations"
    ${lib.concatMapStringsSep "\n" (drv: ''
      nix-copy-closure --to ${user}@${host} ${drv}
    '') actionDerivations}
    
    _log_workflow executor "${executorName}" event "OK" "Workspace ready"
  '';
  
  cleanupWorkspace = { actionDerivations }: ''
    if [ -n "''${WORKSPACE_DIR_REMOTE:-}" ]; then
      if [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_workflow executor "${executorName}" event "->" "Cleaning up remote workspace"
        ${sshCmd} "rm -rf $WORKSPACE_DIR_REMOTE" || true
      fi
    fi
  '';
  
  # === JOB LEVEL ===
  
  setupJob = { jobName, actionDerivations }: ''
    JOB_DIR_REMOTE="$WORKSPACE_DIR_REMOTE/jobs/${jobName}"
    export JOB_DIR_REMOTE
    
    # Create job directory on remote
    ${sshCmd} "mkdir -p $JOB_DIR_REMOTE"
    
    # Copy repository to remote job directory
    ${lib.optionalString copyRepo ''
      _log_job "${jobName}" event "->" "Copying repository to remote"
      
      # Create tarball excluding unnecessary files
      tar -czf - \
        --exclude='.git' \
        --exclude='result*' \
        --exclude='.direnv' \
        --exclude='node_modules' \
        --exclude='target' \
        -C "$PWD" . | \
        ${sshCmd} "tar -xzf - -C $JOB_DIR_REMOTE"
      
      _log_job "${jobName}" event "OK" "Repository copied"
    ''}
  '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    # Build environment export commands
    ENV_EXPORTS=""
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: ''
        ENV_EXPORTS="$ENV_EXPORTS export ${k}=${lib.escapeShellArg (toString v)};"
      '') env
    )}
    
    # Execute on remote
    ${sshCmd} ${lib.escapeShellArg ''
      set -euo pipefail
      cd ${"\$JOB_DIR_REMOTE"}
      
      # Load environment
      $ENV_EXPORTS
      
      # Source helpers
      source /nix/store/*-nixactions-logging/bin/nixactions-logging
      source /nix/store/*-nixactions-retry/bin/nixactions-retry
      source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
      
      _log_job "${jobName}" executor "${executorName}" event "START" "Job starting"
      
      ACTION_FAILED=false
      ${lib.concatMapStringsSep "\n" (action:
        let actionName = action.passthru.name or (builtins.baseNameOf action);
        in ''
          _log_action "${jobName}" "${actionName}" event "->" "Starting"
          if ! ${action}/bin/${actionName}; then
            ACTION_FAILED=true
          fi
        ''
      ) actionDerivations}
      
      if [ "$ACTION_FAILED" = "true" ]; then
        exit 1
      fi
    ''}
  '';
  
  cleanupJob = { jobName }: ''
    # Keep job directory for debugging, cleanup in cleanupWorkspace
    :
  '';
  
  # === ARTIFACTS ===
  
  saveArtifact = { name, path, jobName }: ''
    # Copy from remote to local artifacts dir
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
    ${scpCmd} -r "${user}@${host}:$JOB_DIR_REMOTE/${path}" \
      "$NIXACTIONS_ARTIFACTS_DIR/${name}/"
  '';
  
  restoreArtifact = { name, path, jobName }: ''
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      # Copy from local to remote
      if [ "${path}" = "." ] || [ "${path}" = "./" ]; then
        ${scpCmd} -r "$NIXACTIONS_ARTIFACTS_DIR/${name}/"* \
          "${user}@${host}:$JOB_DIR_REMOTE/"
      else
        ${sshCmd} "mkdir -p $JOB_DIR_REMOTE/${path}"
        ${scpCmd} -r "$NIXACTIONS_ARTIFACTS_DIR/${name}/"* \
          "${user}@${host}:$JOB_DIR_REMOTE/${path}/"
      fi
    else
      _log_workflow artifact "${name}" event "FAIL" "Artifact not found"
      return 1
    fi
  '';
}
```

### Pool Mode Implementation

```nix
# Pool mode - distribute jobs across multiple hosts
mkExecutor {
  name = "ssh-pool";
  
  setupWorkspace = { actionDerivations }: ''
    # Initialize pool state
    POOL_HOSTS=(${lib.concatStringsSep " " (map lib.escapeShellArg hosts)})
    POOL_SIZE=''${#POOL_HOSTS[@]}
    POOL_LOCK_DIR="/tmp/nixactions-pool-$WORKFLOW_ID"
    mkdir -p "$POOL_LOCK_DIR"
    
    export POOL_HOSTS POOL_SIZE POOL_LOCK_DIR
    
    # Setup workspace on ALL hosts in parallel
    for host in "''${POOL_HOSTS[@]}"; do
      (
        ssh ${sshOpts} ${user}@$host "mkdir -p ${workspaceDir}/$WORKFLOW_ID"
        ${lib.concatMapStringsSep "\n" (drv: ''
          nix-copy-closure --to ${user}@$host ${drv}
        '') actionDerivations}
      ) &
    done
    wait
  '';
  
  setupJob = { jobName, actionDerivations }: ''
    # Acquire host from pool (blocking)
    acquire_pool_host() {
      while true; do
        for i in $(seq 0 $((POOL_SIZE - 1))); do
          local lock_file="$POOL_LOCK_DIR/host-$i.lock"
          if mkdir "$lock_file" 2>/dev/null; then
            echo "''${POOL_HOSTS[$i]}"
            echo "$lock_file" > "$POOL_LOCK_DIR/${jobName}.host"
            return 0
          fi
        done
        sleep 1
      done
    }
    
    CURRENT_HOST=$(acquire_pool_host)
    export CURRENT_HOST
    
    _log_job "${jobName}" host "$CURRENT_HOST" event "->" "Acquired host from pool"
    
    JOB_DIR_REMOTE="${workspaceDir}/$WORKFLOW_ID/jobs/${jobName}"
    ssh ${sshOpts} ${user}@$CURRENT_HOST "mkdir -p $JOB_DIR_REMOTE"
    export JOB_DIR_REMOTE
  '';
  
  cleanupJob = { jobName }: ''
    # Release host back to pool
    if [ -f "$POOL_LOCK_DIR/${jobName}.host" ]; then
      rm -rf "$(cat "$POOL_LOCK_DIR/${jobName}.host")"
      rm -f "$POOL_LOCK_DIR/${jobName}.host"
      _log_job "${jobName}" event "->" "Released host to pool"
    fi
  '';
}
```

### Usage Examples

```nix
# Basic SSH executor
jobs.build = {
  executor = platform.executors.ssh {
    host = "build.example.com";
    user = "ci";
  };
  actions = [...];
};

# SSH with dedicated runners
jobs.security-scan = {
  executor = platform.executors.ssh {
    host = "scanner.example.com";
    user = "ci";
    mode = "dedicated";
  };
  actions = [...];
};

# SSH pool for parallel builds
jobs = {
  build-linux = {
    executor = platform.executors.ssh {
      hosts = [ "linux-1" "linux-2" "linux-3" ];
      user = "builder";
      mode = "pool";
    };
    actions = [...];
  };
  
  build-arm = {
    executor = platform.executors.ssh {
      hosts = [ "arm-1" "arm-2" ];
      user = "builder";
      mode = "pool";
    };
    actions = [...];
  };
};
```

---

## NixOS VM Executor

### Overview

Runs jobs in ephemeral NixOS virtual machines. Ideal for:
- Testing NixOS configurations
- Full isolation
- Reproducible environments

### Configuration

```nix
platform.executors.nixosVm {
  # VM Configuration
  configuration = ./vm-config.nix;  # NixOS config
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
  mode = "dedicated";  # "shared" | "dedicated"
  
  # Behavior
  copyRepo = true;
  
  # Custom name
  name = null;  # defaults to "nixos-vm"
}
```

### Implementation

```nix
# lib/executors/nixos-vm.nix
{ pkgs, lib, mkExecutor }:

{
  configuration ? null,
  modules ? [],
  memory ? 4096,
  cores ? 2,
  diskSize ? 10240,
  mode ? "dedicated",
  copyRepo ? true,
  name ? null,
}:

let
  executorName = if name != null then name else "nixos-vm";
  
  # Build VM derivation
  vmConfig = {
    imports = (if configuration != null then [ configuration ] else []) ++ modules ++ [
      # Base NixActions runner config
      ({ pkgs, ... }: {
        # Enable Nix
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        
        # SSH for control
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes";
        };
        
        # Auto-login for console access
        services.getty.autologinUser = "root";
        
        # Mount host /nix/store
        fileSystems."/nix/store" = {
          device = "store";
          fsType = "9p";
          options = [ "trans=virtio" "version=9p2000.L" "ro" ];
        };
        
        # Shared directory for workspace
        fileSystems."/workspace" = {
          device = "workspace";
          fsType = "9p";
          options = [ "trans=virtio" "version=9p2000.L" ];
        };
        
        # Network
        networking.useDHCP = true;
      })
    ];
  };
  
  vmBuild = (import (pkgs.path + "/nixos") {
    inherit (pkgs) system;
    configuration = vmConfig;
  }).vm;
  
  vmHelpers = import ./vm-helpers.nix { inherit pkgs lib; };
in

mkExecutor {
  inherit copyRepo;
  name = executorName;
  
  # === WORKSPACE LEVEL ===
  
  setupWorkspace = { actionDerivations }: 
    if mode == "shared" then ''
      source ${vmHelpers}/bin/nixactions-vm-executor
      
      # Check if VM already running (shared mode)
      VM_PID_FILE="/tmp/nixactions-vm-$WORKFLOW_ID-${executorName}.pid"
      
      if [ -f "$VM_PID_FILE" ] && kill -0 "$(cat "$VM_PID_FILE")" 2>/dev/null; then
        _log_workflow executor "${executorName}" event "->" "Reusing existing VM"
      else
        # Start new VM
        start_vm "${vmBuild}/bin/run-*-vm" "$VM_PID_FILE"
        
        # Wait for VM to be ready
        wait_for_vm_ssh
        
        _log_workflow executor "${executorName}" event "OK" "VM started"
      fi
      
      export VM_PID_FILE
    '' else ''
      # Dedicated mode - VM started per job
      :
    '';
  
  cleanupWorkspace = { actionDerivations }: 
    if mode == "shared" then ''
      if [ -f "$VM_PID_FILE" ] && [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_workflow executor "${executorName}" event "->" "Shutting down VM"
        kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
        rm -f "$VM_PID_FILE"
      fi
    '' else ''
      # Dedicated mode - VM cleanup in cleanupJob
      :
    '';
  
  # === JOB LEVEL ===
  
  setupJob = { jobName, actionDerivations }: 
    if mode == "dedicated" then ''
      source ${vmHelpers}/bin/nixactions-vm-executor
      
      # Start dedicated VM for this job
      VM_PID_FILE="/tmp/nixactions-vm-$WORKFLOW_ID-${jobName}.pid"
      
      _log_job "${jobName}" event "->" "Starting dedicated VM"
      start_vm "${vmBuild}/bin/run-*-vm" "$VM_PID_FILE"
      wait_for_vm_ssh
      
      export VM_PID_FILE
      
      # Create job directory in VM
      vm_ssh "mkdir -p /workspace/jobs/${jobName}"
      
      ${lib.optionalString copyRepo ''
        _log_job "${jobName}" event "->" "Copying repository to VM"
        tar -czf - -C "$PWD" . | vm_ssh "tar -xzf - -C /workspace/jobs/${jobName}"
      ''}
    '' else ''
      # Shared mode - just create job directory
      vm_ssh "mkdir -p /workspace/jobs/${jobName}"
      
      ${lib.optionalString copyRepo ''
        tar -czf - -C "$PWD" . | vm_ssh "tar -xzf - -C /workspace/jobs/${jobName}"
      ''}
    '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    vm_ssh ${lib.escapeShellArg ''
      set -euo pipefail
      cd /workspace/jobs/${jobName}
      
      # Environment
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") env
      )}
      
      # Source helpers
      source /nix/store/*-nixactions-logging/bin/nixactions-logging
      source /nix/store/*-nixactions-retry/bin/nixactions-retry
      source /nix/store/*-nixactions-runtime/bin/nixactions-runtime
      
      _log_job "${jobName}" executor "${executorName}" event "START" "Job starting in VM"
      
      ACTION_FAILED=false
      ${lib.concatMapStringsSep "\n" (action:
        let actionName = action.passthru.name or (builtins.baseNameOf action);
        in ''
          _log_action "${jobName}" "${actionName}" event "->" "Starting"
          if ! ${action}/bin/${actionName}; then
            ACTION_FAILED=true
          fi
        ''
      ) actionDerivations}
      
      if [ "$ACTION_FAILED" = "true" ]; then
        exit 1
      fi
    ''}
  '';
  
  cleanupJob = { jobName }: 
    if mode == "dedicated" then ''
      # Shutdown dedicated VM
      if [ -f "$VM_PID_FILE" ] && [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_job "${jobName}" event "->" "Shutting down VM"
        kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
        rm -f "$VM_PID_FILE"
      fi
    '' else ''
      # Shared mode - keep VM running
      :
    '';
  
  # === ARTIFACTS ===
  
  saveArtifact = { name, path, jobName }: ''
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
    vm_scp ":/workspace/jobs/${jobName}/${path}" "$NIXACTIONS_ARTIFACTS_DIR/${name}/"
  '';
  
  restoreArtifact = { name, path, jobName }: ''
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      if [ "${path}" = "." ]; then
        vm_scp "$NIXACTIONS_ARTIFACTS_DIR/${name}/"* ":/workspace/jobs/${jobName}/"
      else
        vm_ssh "mkdir -p /workspace/jobs/${jobName}/${path}"
        vm_scp "$NIXACTIONS_ARTIFACTS_DIR/${name}/"* ":/workspace/jobs/${jobName}/${path}/"
      fi
    else
      return 1
    fi
  '';
}
```

### VM Helpers

```nix
# lib/executors/vm-helpers.nix
{ pkgs, lib }:

pkgs.writeScriptBin "nixactions-vm-executor" ''
  #!${pkgs.bash}/bin/bash
  
  VM_SSH_PORT=2222
  VM_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $VM_SSH_PORT"
  
  start_vm() {
    local vm_bin=$1
    local pid_file=$2
    
    # Find available port
    VM_SSH_PORT=$(find_free_port 2222 2300)
    
    # Start VM in background
    QEMU_NET_OPTS="hostfwd=tcp::$VM_SSH_PORT-:22" \
      $vm_bin &
    echo $! > "$pid_file"
    
    export VM_SSH_PORT
  }
  
  wait_for_vm_ssh() {
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
      if ssh $VM_SSH_OPTS root@localhost true 2>/dev/null; then
        return 0
      fi
      sleep 1
      attempt=$((attempt + 1))
    done
    
    echo "Timeout waiting for VM SSH" >&2
    return 1
  }
  
  vm_ssh() {
    ssh $VM_SSH_OPTS root@localhost "$@"
  }
  
  vm_scp() {
    scp $VM_SSH_OPTS "$@"
  }
  
  find_free_port() {
    local start=$1
    local end=$2
    for port in $(seq $start $end); do
      if ! ss -tuln | grep -q ":$port "; then
        echo $port
        return 0
      fi
    done
    return 1
  }
  
  export -f start_vm wait_for_vm_ssh vm_ssh vm_scp find_free_port
''
```

### Usage Examples

```nix
# NixOS testing
jobs.test-nixos-config = {
  executor = platform.executors.nixosVm {
    configuration = ./nixos/test-config.nix;
    memory = 2048;
    cores = 2;
  };
  actions = [
    { bash = "systemctl status nginx"; }
    { bash = "curl localhost:80"; }
  ];
};

# Integration testing with custom modules
jobs.integration-test = {
  executor = platform.executors.nixosVm {
    modules = [
      ({ pkgs, ... }: {
        services.postgresql.enable = true;
        services.redis.enable = true;
        environment.systemPackages = [ pkgs.nodejs pkgs.postgresql ];
      })
    ];
    mode = "dedicated";  # Clean VM per test
  };
  actions = [
    { bash = "npm run integration-test"; }
  ];
};
```

---

## Kubernetes Executor

### Overview

Runs jobs in Kubernetes pods. Supports:
- Ephemeral pods (dedicated mode)
- Long-lived runner pods (shared mode)
- Integration with Kubernetes secrets

### Configuration

```nix
platform.executors.k8s {
  # Required
  namespace = "ci";
  
  # Pod template
  image = "nixos/nix:2.18.1";
  resources = {
    requests = { cpu = "500m"; memory = "1Gi"; };
    limits = { cpu = "2"; memory = "4Gi"; };
  };
  
  # Optional
  serviceAccount = "ci-runner";
  nodeSelector = { "kubernetes.io/arch" = "amd64"; };
  tolerations = [];
  
  # Volumes
  volumes = [
    {
      name = "nix-store";
      persistentVolumeClaim.claimName = "nix-store-pvc";
    }
  ];
  volumeMounts = [
    { name = "nix-store"; mountPath = "/nix/store"; readOnly = true; }
  ];
  
  # Mode
  mode = "dedicated";  # "shared" | "dedicated"
  
  # Behavior
  copyRepo = true;
  
  # Custom name
  name = null;  # defaults to "k8s-${namespace}"
}
```

### Implementation

```nix
# lib/executors/k8s.nix
{ pkgs, lib, mkExecutor }:

{
  namespace,
  image ? "nixos/nix:2.18.1",
  resources ? {},
  serviceAccount ? null,
  nodeSelector ? {},
  tolerations ? [],
  volumes ? [],
  volumeMounts ? [],
  mode ? "dedicated",
  copyRepo ? true,
  name ? null,
}:

let
  executorName = if name != null then name else "k8s-${namespace}";
  
  kubectl = "${pkgs.kubectl}/bin/kubectl";
  
  # Generate pod spec
  podSpec = jobName: {
    apiVersion = "v1";
    kind = "Pod";
    metadata = {
      name = "nixactions-${jobName}";
      namespace = namespace;
      labels = {
        "app.kubernetes.io/name" = "nixactions-runner";
        "app.kubernetes.io/component" = jobName;
        "nixactions.io/workflow" = "$WORKFLOW_ID";
      };
    };
    spec = {
      restartPolicy = "Never";
      containers = [{
        name = "runner";
        inherit image;
        command = [ "sleep" "infinity" ];
        resources = resources;
        volumeMounts = volumeMounts ++ [
          { name = "workspace"; mountPath = "/workspace"; }
        ];
      }];
      volumes = volumes ++ [
        { name = "workspace"; emptyDir = {}; }
      ];
    } // lib.optionalAttrs (serviceAccount != null) {
      serviceAccountName = serviceAccount;
    } // lib.optionalAttrs (nodeSelector != {}) {
      inherit nodeSelector;
    } // lib.optionalAttrs (tolerations != []) {
      inherit tolerations;
    };
  };
  
  k8sHelpers = import ./k8s-helpers.nix { inherit pkgs lib; };
in

mkExecutor {
  inherit copyRepo;
  name = executorName;
  
  # === WORKSPACE LEVEL ===
  
  setupWorkspace = { actionDerivations }: 
    if mode == "shared" then ''
      source ${k8sHelpers}/bin/nixactions-k8s-executor
      
      # Check for existing shared runner pod
      SHARED_POD_NAME="nixactions-shared-$WORKFLOW_ID"
      
      if ${kubectl} -n ${namespace} get pod "$SHARED_POD_NAME" 2>/dev/null | grep -q Running; then
        _log_workflow executor "${executorName}" pod "$SHARED_POD_NAME" event "->" "Reusing shared pod"
      else
        # Create shared runner pod
        create_runner_pod "$SHARED_POD_NAME" ${lib.escapeShellArg (builtins.toJSON (podSpec "shared"))}
        wait_for_pod "$SHARED_POD_NAME"
        
        # Copy derivations to pod (via shared volume)
        copy_derivations_to_pod "$SHARED_POD_NAME" ${lib.escapeShellArg (toString actionDerivations)}
        
        _log_workflow executor "${executorName}" event "OK" "Shared pod ready"
      fi
      
      export SHARED_POD_NAME
    '' else ''
      # Dedicated mode - pods created per job
      _log_workflow executor "${executorName}" mode "dedicated" event "->" "Pods will be created per job"
    '';
  
  cleanupWorkspace = { actionDerivations }: 
    if mode == "shared" then ''
      if [ -n "''${SHARED_POD_NAME:-}" ] && [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_workflow executor "${executorName}" event "->" "Deleting shared pod"
        ${kubectl} -n ${namespace} delete pod "$SHARED_POD_NAME" --wait=false || true
      fi
    '' else ''
      # Dedicated mode - pods deleted in cleanupJob
      :
    '';
  
  # === JOB LEVEL ===
  
  setupJob = { jobName, actionDerivations }: 
    if mode == "dedicated" then ''
      source ${k8sHelpers}/bin/nixactions-k8s-executor
      
      POD_NAME="nixactions-${jobName}-$WORKFLOW_ID"
      
      _log_job "${jobName}" event "->" "Creating dedicated pod"
      create_runner_pod "$POD_NAME" ${lib.escapeShellArg (builtins.toJSON (podSpec jobName))}
      wait_for_pod "$POD_NAME"
      
      # Copy derivations to pod
      copy_derivations_to_pod "$POD_NAME" ${lib.escapeShellArg (toString actionDerivations)}
      
      export POD_NAME
      
      # Create job directory
      ${kubectl} -n ${namespace} exec "$POD_NAME" -- mkdir -p /workspace/jobs/${jobName}
      
      ${lib.optionalString copyRepo ''
        _log_job "${jobName}" event "->" "Copying repository to pod"
        tar -czf - -C "$PWD" . | \
          ${kubectl} -n ${namespace} exec -i "$POD_NAME" -- tar -xzf - -C /workspace/jobs/${jobName}
      ''}
    '' else ''
      # Shared mode - use shared pod
      POD_NAME="$SHARED_POD_NAME"
      export POD_NAME
      
      ${kubectl} -n ${namespace} exec "$POD_NAME" -- mkdir -p /workspace/jobs/${jobName}
      
      ${lib.optionalString copyRepo ''
        tar -czf - -C "$PWD" . | \
          ${kubectl} -n ${namespace} exec -i "$POD_NAME" -- tar -xzf - -C /workspace/jobs/${jobName}
      ''}
    '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    # Build environment
    ENV_ARGS=""
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: ''
        ENV_ARGS="$ENV_ARGS -e ${k}=${lib.escapeShellArg (toString v)}"
      '') env
    )}
    
    ${kubectl} -n ${namespace} exec $ENV_ARGS "$POD_NAME" -- bash -c ${lib.escapeShellArg ''
      set -euo pipefail
      cd /workspace/jobs/${jobName}
      
      # Source helpers
      source /nix/store/*-nixactions-logging/bin/nixactions-logging 2>/dev/null || true
      source /nix/store/*-nixactions-retry/bin/nixactions-retry 2>/dev/null || true
      source /nix/store/*-nixactions-runtime/bin/nixactions-runtime 2>/dev/null || true
      
      echo "START Job starting in pod"
      
      ACTION_FAILED=false
      ${lib.concatMapStringsSep "\n" (action:
        let actionName = action.passthru.name or (builtins.baseNameOf action);
        in ''
          echo "-> ${actionName}"
          if ! ${action}/bin/${actionName}; then
            ACTION_FAILED=true
          fi
        ''
      ) actionDerivations}
      
      if [ "$ACTION_FAILED" = "true" ]; then
        exit 1
      fi
    ''}
  '';
  
  cleanupJob = { jobName }: 
    if mode == "dedicated" then ''
      if [ -n "''${POD_NAME:-}" ] && [ "''${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
        _log_job "${jobName}" event "->" "Deleting pod"
        ${kubectl} -n ${namespace} delete pod "$POD_NAME" --wait=false || true
      fi
    '' else ''
      # Shared mode - keep pod running
      :
    '';
  
  # === ARTIFACTS ===
  
  saveArtifact = { name, path, jobName }: ''
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/${name}"
    ${kubectl} -n ${namespace} cp \
      "$POD_NAME:/workspace/jobs/${jobName}/${path}" \
      "$NIXACTIONS_ARTIFACTS_DIR/${name}/"
  '';
  
  restoreArtifact = { name, path, jobName }: ''
    if [ -e "$NIXACTIONS_ARTIFACTS_DIR/${name}" ]; then
      if [ "${path}" = "." ]; then
        ${kubectl} -n ${namespace} cp \
          "$NIXACTIONS_ARTIFACTS_DIR/${name}/" \
          "$POD_NAME:/workspace/jobs/${jobName}/"
      else
        ${kubectl} -n ${namespace} exec "$POD_NAME" -- mkdir -p /workspace/jobs/${jobName}/${path}
        ${kubectl} -n ${namespace} cp \
          "$NIXACTIONS_ARTIFACTS_DIR/${name}/" \
          "$POD_NAME:/workspace/jobs/${jobName}/${path}/"
      fi
    else
      return 1
    fi
  '';
}
```

### K8s Helpers

```nix
# lib/executors/k8s-helpers.nix
{ pkgs, lib }:

pkgs.writeScriptBin "nixactions-k8s-executor" ''
  #!${pkgs.bash}/bin/bash
  
  KUBECTL="${pkgs.kubectl}/bin/kubectl"
  
  create_runner_pod() {
    local pod_name=$1
    local pod_spec=$2
    
    echo "$pod_spec" | sed "s/\$WORKFLOW_ID/$WORKFLOW_ID/g" | \
      $KUBECTL apply -f -
  }
  
  wait_for_pod() {
    local pod_name=$1
    local namespace=''${NAMESPACE:-default}
    local timeout=300
    
    $KUBECTL -n "$namespace" wait --for=condition=Ready pod/"$pod_name" --timeout=''${timeout}s
  }
  
  copy_derivations_to_pod() {
    local pod_name=$1
    shift
    local derivations="$@"
    
    # For now, assume /nix/store is mounted via PVC
    # Future: use nix-copy-closure over kubectl exec
    :
  }
  
  export -f create_runner_pod wait_for_pod copy_derivations_to_pod
''
```

### Usage Examples

```nix
# Basic Kubernetes execution
jobs.deploy = {
  executor = platform.executors.k8s {
    namespace = "ci";
    image = "nixos/nix:2.18.1";
  };
  actions = [
    { bash = "kubectl apply -f k8s/"; }
  ];
};

# With GPU
jobs.ml-training = {
  executor = platform.executors.k8s {
    namespace = "ml";
    image = "nvidia/cuda:12.0-nix";
    resources = {
      limits = { "nvidia.com/gpu" = "1"; };
    };
    nodeSelector = { "nvidia.com/gpu.present" = "true"; };
    mode = "dedicated";
  };
  actions = [
    { bash = "python train.py"; }
  ];
};

# Shared runner for multiple jobs
let
  ciRunner = platform.executors.k8s {
    namespace = "ci";
    mode = "shared";
    name = "ci-shared-runner";
  };
in {
  jobs = {
    test = { executor = ciRunner; actions = [...]; };
    lint = { executor = ciRunner; actions = [...]; };
    build = { executor = ciRunner; actions = [...]; };
  };
}
```

---

## Artifacts & Environment Transfer

### Artifact Transfer Patterns

#### Local -> Remote (restoreArtifact)

```
+------------------+                    +------------------+
| Control Node     |                    | Remote Runner    |
|                  |                    |                  |
| $NIXACTIONS_     |     SCP/kubectl    | /workspace/      |
| ARTIFACTS_DIR/   | -----------------> | jobs/$JOB/       |
| artifact-name/   |        cp          | target-path/     |
|                  |                    |                  |
+------------------+                    +------------------+
```

#### Remote -> Local (saveArtifact)

```
+------------------+                    +------------------+
| Control Node     |                    | Remote Runner    |
|                  |                    |                  |
| $NIXACTIONS_     |     SCP/kubectl    | /workspace/      |
| ARTIFACTS_DIR/   | <----------------- | jobs/$JOB/       |
| artifact-name/   |        cp          | path/            |
|                  |                    |                  |
+------------------+                    +------------------+
```

### Environment Transfer

#### SSH Executor

```bash
# Option 1: Pass via SSH command
ssh user@host "export K1=V1; export K2=V2; /nix/store/.../action"

# Option 2: Environment file
cat env.sh | ssh user@host "cat > /tmp/env.sh && source /tmp/env.sh && ..."

# Option 3: SSH SendEnv (requires server config)
ssh -o SendEnv="VAR1 VAR2" user@host "..."
```

#### Kubernetes Executor

```bash
# Via kubectl exec -e
kubectl exec -e "KEY=VALUE" -e "KEY2=VALUE2" pod -- bash -c "..."

# Via ConfigMap
kubectl create configmap job-env --from-env-file=.env
kubectl exec pod -- bash -c "source /etc/job-env && ..."
```

#### NixOS VM Executor

```bash
# Via SSH (same as SSH executor)
ssh -p 2222 root@localhost "export K=V; ..."

# Via 9p filesystem
echo "export K=V" > /tmp/vm-share/env.sh
vm_ssh "source /mnt/share/env.sh && ..."
```

### Security Considerations

1. **Secrets never in logs** - environment passed via secure channels
2. **Temporary files** - env files deleted after job
3. **No persistence** - dedicated runners destroyed after use
4. **Namespace isolation** - K8s pods in dedicated namespace
5. **SSH keys** - use agent forwarding, not file copying

---

## Security Model

### Isolation Levels

| Level | SSH | NixOS VM | Kubernetes |
|-------|-----|----------|------------|
| Network | Shared | Isolated (NAT) | Pod network policy |
| Filesystem | Shared host | Isolated (overlay) | Isolated (emptyDir) |
| Processes | Shared host | Isolated (VM) | Isolated (cgroup) |
| Secrets | SSH agent | None | K8s secrets |

### Recommendations

1. **CI/CD** - SSH shared mode (efficient, acceptable isolation)
2. **Untrusted code** - NixOS VM dedicated mode (full isolation)
3. **Production** - K8s with network policies (enterprise-grade)
4. **Security testing** - NixOS VM dedicated mode (clean environment)

### Trust Boundaries

```
+---------------------------------------------------------------+
| Control Node (TRUSTED)                                         |
|  - Workflow execution                                          |
|  - Secrets management                                          |
|  - Artifact storage                                            |
+------------------------------+--------------------------------+
                               |
                               | SSH/QEMU/kubectl
                               |
+------------------------------v--------------------------------+
| Runner (SEMI-TRUSTED)                                          |
|  - Action execution                                            |
|  - Limited filesystem access                                   |
|  - No secret access (passed at runtime)                        |
+---------------------------------------------------------------+
```

---

## Implementation Roadmap

### Phase 1: SSH Executor (2 weeks)

- [ ] Basic SSH executor (shared mode)
- [ ] nix-copy-closure integration
- [ ] Artifact transfer via SCP
- [ ] Environment passing
- [ ] Tests

### Phase 2: SSH Pool Mode (1 week)

- [ ] Multiple hosts support
- [ ] Host acquisition/release
- [ ] Load balancing
- [ ] Health checks

### Phase 3: NixOS VM Executor (2 weeks)

- [ ] VM generation from NixOS config
- [ ] 9p filesystem for /nix/store
- [ ] SSH control channel
- [ ] Dedicated mode (per-job VMs)
- [ ] Tests

### Phase 4: Kubernetes Executor (2 weeks)

- [ ] Pod creation/deletion
- [ ] kubectl cp for artifacts
- [ ] Environment via -e flags
- [ ] Shared pod mode
- [ ] Tests

### Phase 5: Documentation & Polish (1 week)

- [ ] Usage examples
- [ ] Security documentation
- [ ] Performance benchmarks
- [ ] Integration tests

---

## Summary

### Comparison

| Executor | Startup | Isolation | Use Case |
|----------|---------|-----------|----------|
| Local | Instant | None | Development, simple CI |
| OCI | Fast | Container | Docker-based workflows |
| SSH (shared) | Fast | Directory | Remote builds, existing infra |
| SSH (dedicated) | Medium | Connection | Security-sensitive |
| SSH (pool) | Fast | Directory | Parallel builds |
| NixOS VM | Slow | Full | NixOS testing, full isolation |
| K8s (shared) | Fast | Pod | Enterprise CI/CD |
| K8s (dedicated) | Medium | Pod | Stateless runners |

### Decision Matrix

```
Need isolation? ---------------------------------------------------------+
  |                                                                       |
  +-- No -----------------------------------------------------------------+
  |    +-- Fast? ---------------------------------------------------------+
  |        +-- Yes ------------------------------> Local/OCI              |
  |        +-- No -------------------------------> SSH (shared)           |
  |                                                                       |
  +-- Container level ----------------------------------------------------+
  |    +-- Kubernetes? ---------------------------------------------------+
  |        +-- Yes ------------------------------> K8s (dedicated)        |
  |        +-- No -------------------------------> OCI                    |
  |                                                                       |
  +-- Full isolation -----------------------------------------------------+
       +-- NixOS testing? ------------------------------------------------+
           +-- Yes ------------------------------> NixOS VM               |
           +-- No -------------------------------> SSH (dedicated)        |
```

---

## Appendix: Full Configuration Reference

### SSH Executor

```nix
platform.executors.ssh {
  # Connection
  host = "build.example.com";      # Required
  user = "builder";                 # Required
  port = 22;                        # Default: 22
  identityFile = "~/.ssh/id_ed25519"; # Default: null (use ssh-agent)
  
  # Mode
  mode = "shared";                  # "shared" | "dedicated" | "pool"
  hosts = [];                       # For pool mode
  
  # Behavior
  copyRepo = true;                  # Copy repo to remote
  workspaceDir = "/tmp/nixactions"; # Remote workspace location
  
  # Identity
  name = null;                      # Custom name for workspace isolation
}
```

### NixOS VM Executor

```nix
platform.executors.nixosVm {
  # Configuration (one of)
  configuration = ./vm-config.nix;  # NixOS config file
  modules = [];                     # Inline NixOS modules
  
  # Resources
  memory = 4096;                    # MB
  cores = 2;                        # CPU cores
  diskSize = 10240;                 # MB
  
  # Mode
  mode = "dedicated";               # "shared" | "dedicated"
  
  # Behavior
  copyRepo = true;
  
  # Identity
  name = null;
}
```

### Kubernetes Executor

```nix
platform.executors.k8s {
  # Required
  namespace = "ci";
  
  # Pod template
  image = "nixos/nix:2.18.1";
  resources = {
    requests = { cpu = "500m"; memory = "1Gi"; };
    limits = { cpu = "2"; memory = "4Gi"; };
  };
  
  # Optional
  serviceAccount = null;
  nodeSelector = {};
  tolerations = [];
  
  # Volumes
  volumes = [];
  volumeMounts = [];
  
  # Mode
  mode = "dedicated";               # "shared" | "dedicated"
  
  # Behavior
  copyRepo = true;
  
  # Identity
  name = null;
}
```
