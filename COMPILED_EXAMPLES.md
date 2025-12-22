# Compiled Examples

This directory contains compiled bash scripts for all NixActions workflow examples.
These are the actual scripts that get executed when you run `nix run .#example-*`.

## Architecture v2: Executors Own Workspace

All compiled scripts use the new architecture where executors manage their own workspaces:

- **Local executor** → `/tmp/nixactions/$WORKFLOW_ID`
- **SSH executor** → `/var/tmp/nixactions/$WORKFLOW_ID` on remote host
- **OCI executor** → Docker container with `/workspace`
- **K8s executor** → Kubernetes pod with `/workspace`
- **Nomad executor** → Nomad allocation with `/workspace`

## Available Scripts

### Single Executor Workflows

All jobs use the same executor (local):

1. **compiled-simple.sh** (6.0K)
   - Basic workflow with one job
   - Demonstrates: checkout, basic actions

2. **compiled-parallel.sh** (8.9K)
   - Parallel execution with multiple levels
   - Demonstrates: parallel jobs, dependency ordering

3. **compiled-complete.sh** (14K)
   - Full CI/CD pipeline with 5 levels
   - Demonstrates: linting, testing, building, deployment, notifications

4. **compiled-secrets.sh** (13K)
   - Environment variables at workflow/job/action levels
   - Demonstrates: env var precedence, runtime overrides

5. **compiled-test-env.sh** (10K)
   - Environment variable propagation between actions
   - Demonstrates: actions sharing env within job

6. **compiled-test-isolation.sh** (7.7K)
   - Job isolation proof
   - Demonstrates: subshell isolation, no env leaks between jobs

7. **compiled-python-ci.sh** (19K)
   - Real-world Python CI/CD pipeline
   - Demonstrates: pytest, flake8, mypy, docker build

8. **compiled-python-ci-simple.sh** (9.5K)
   - Simplified Python CI
   - Demonstrates: job isolation clearly

9. **compiled-nix-shell.sh** (9.6K)
   - Dynamic package loading with nixShell action
   - Demonstrates: runtime package installation without executor modification

### Multi-Executor Workflow

Jobs use different executors (local + OCI):

10. **compiled-docker-ci.sh** (16K)
    - **4 unique executors**:
      - `local` - for Docker image building
      - `oci-python-3.11-slim` - Python tests in container
      - `oci-node-20-slim` - Node tests in container
      - `oci-ubuntu-22.04` - Ubuntu tests in container
    - Each executor creates its own workspace
    - Demonstrates: multi-executor support, workspace isolation

## Running Scripts

All scripts are standalone and can be executed directly:

```bash
# Simple workflow
./compiled-simple.sh

# Parallel execution
./compiled-parallel.sh

# Dynamic package loading
./compiled-nix-shell.sh

# Multi-executor (requires Docker)
./compiled-docker-ci.sh
```

## Environment Variables

All scripts support:

- `NIXACTIONS_KEEP_WORKSPACE=1` - Preserve workspace after execution
- Runtime env overrides: `VAR=value ./compiled-script.sh`

## Script Structure

Each compiled script contains:

1. **Header** - Bash shebang, set options
2. **Workflow ID generation** - Unique ID with timestamp and PID
3. **Workspace setup** - Call `setupWorkspace` for each unique executor
4. **Job status tracking** - Associative arrays for success/failure
5. **Cleanup handler** - Trap EXIT/SIGINT/SIGTERM
6. **Condition checks** - `success()`, `failure()`, `always()`, `cancelled()`
7. **Job functions** - One function per job
8. **Level execution** - Run jobs level-by-level (DAG)
9. **Final report** - Summary of succeeded/failed jobs
10. **Cleanup** - Call `cleanupWorkspace` for all executors

## Key Features Demonstrated

### Parallel Execution
Jobs without dependencies run in parallel using bash background jobs (`&`).

### Dependency Management
Jobs grouped by dependency depth (levels), executed level-by-level.

### Job Isolation
Each job runs in subshell `( job_name )` - environment doesn't leak.

### Workspace Isolation
Each executor manages its own workspace - local uses `/tmp`, OCI uses containers.

### Multi-Executor Support
Workflows can use different executors - each creates and manages its own workspace.

### Conditional Execution
Jobs can run based on conditions: `if: success()`, `if: failure()`, `if: always()`.

### Continue on Error
Jobs can fail without stopping workflow: `continueOnError: true`.

## Regenerating Scripts

To regenerate all scripts after changes:

```bash
nix build .#example-simple --no-link --print-out-paths
# Copy from /nix/store/.../bin/* to compiled-*.sh
```

Or use the automated approach from the implementation.
