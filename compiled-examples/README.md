# Compiled Examples

This directory contains compiled bash scripts generated from NixActions workflow definitions.

These scripts show the **final generated code** that gets executed when you run a workflow.

## Available Examples

### Local Executor Examples

#### artifacts-simple.sh
Basic artifact sharing between jobs using **local executor**.

**What it demonstrates:**
- Job `build` creates artifacts (`dist/` and `myapp`)
- Job `test` restores and uses those artifacts
- Artifacts saved/restored with `cp` on host

#### artifacts-paths.sh
Nested path preservation in artifacts using **local executor**.

**What it demonstrates:**
- Saving artifacts with nested directory structure (`target/release/myapp`, `build/dist/`)
- Path structure is preserved when restored
- Same host-based `cp` pattern

### OCI Executor Examples

#### artifacts-simple-oci.sh
Basic artifact sharing between jobs using **OCI (Docker) executor**.

**What it demonstrates:**
- Jobs run inside Docker containers
- Artifacts saved from container to host using `docker cp`
- Artifacts restored from host to container using `docker cp`
- Container workspace cleaned up after each job

#### artifacts-paths-oci.sh
Nested path preservation with **OCI executor**.

**What it demonstrates:**
- Same nested directory structure as local example
- But uses `docker cp` instead of plain `cp`
- Shows how executor abstraction works: same declarative API, different implementation

## Key Architecture Points

Looking at these compiled scripts, you can see each job follows this pattern:

### Job Lifecycle

```bash
job_build() {
  # 1. Setup workspace (lazy init - reuses if exists)
  if [ -z "${WORKSPACE_DIR_LOCAL:-}" ]; then
    WORKSPACE_DIR_LOCAL="/tmp/nixactions/$WORKFLOW_ID"
    mkdir -p "$WORKSPACE_DIR_LOCAL"
    export WORKSPACE_DIR_LOCAL
    echo "→ Local workspace: $WORKSPACE_DIR_LOCAL"
  fi
  
  # 2. Restore artifacts ON HOST (if job has inputs)
  echo "→ Restoring artifacts: release-binary build-artifacts"
  JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
  if [ -e "$NIXACTIONS_ARTIFACTS_DIR/release-binary" ]; then
    mkdir -p "$JOB_DIR"
    cp -r "$NIXACTIONS_ARTIFACTS_DIR/release-binary"/* "$JOB_DIR/"
  fi
  
  # 3. Execute job
  JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
  mkdir -p "$JOB_DIR"
  cd "$JOB_DIR"
  # ... job script runs here ...
  
  # 4. Save artifacts ON HOST (if job has outputs)
  echo "→ Saving artifacts"
  if [ -e "$JOB_DIR/build/dist/" ]; then
    rm -rf "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
    mkdir -p "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts"
    cp -r "$JOB_DIR/build/dist/" "$NIXACTIONS_ARTIFACTS_DIR/build-artifacts/build/dist/"
  fi
  
  # 5. Cleanup workspace
  if [ "${NIXACTIONS_KEEP_WORKSPACE:-}" != "1" ]; then
    echo "→ Cleaning up local workspace: $WORKSPACE_DIR_LOCAL"
    rm -rf "$WORKSPACE_DIR_LOCAL"
  fi
}
```

### Global Setup (once per workflow)

At the start of the workflow (line ~10):
```bash
NIXACTIONS_ARTIFACTS_DIR="${NIXACTIONS_ARTIFACTS_DIR:-$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts}"
mkdir -p "$NIXACTIONS_ARTIFACTS_DIR"
export NIXACTIONS_ARTIFACTS_DIR
```

**Important:** Artifacts directory is **NOT** cleaned up after jobs - this is how artifacts persist between jobs!

## Comparing Local vs OCI Executors

### Local Executor (artifacts-simple.sh)

**Save artifact:**
```bash
# Simple cp on host
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/build"
cp -r "$JOB_DIR/dist/" "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
```

**Restore artifact:**
```bash
# Simple cp on host
JOB_DIR="$WORKSPACE_DIR_LOCAL/jobs/test"
cp -r "$NIXACTIONS_ARTIFACTS_DIR/dist"/* "$JOB_DIR/"
```

### OCI Executor (artifacts-simple-oci.sh)

**Save artifact:**
```bash
# Check if exists in container
docker exec "$CONTAINER_ID" test -e "$JOB_DIR/dist/"

# Copy FROM container TO host
docker cp "$CONTAINER_ID:$JOB_DIR/dist/" "$NIXACTIONS_ARTIFACTS_DIR/dist/dist/"
```

**Restore artifact:**
```bash
# Ensure job dir exists in container
docker exec "$CONTAINER_ID" mkdir -p "$JOB_DIR"

# Copy FROM host TO container
for item in "$NIXACTIONS_ARTIFACTS_DIR/dist"/*; do
  docker cp "$item" "$CONTAINER_ID:$JOB_DIR/"
done
```

**Key Point:** Same declarative API in Nix (`outputs = { dist = "dist/"; }`), but different implementation based on executor. This is why `saveArtifact` and `restoreArtifact` are executor functions!

## Running These Scripts

### Direct execution:

```bash
# Local executor examples
./compiled-examples/artifacts-simple.sh
./compiled-examples/artifacts-paths.sh

# OCI executor examples (requires Docker)
./compiled-examples/artifacts-simple-oci.sh
./compiled-examples/artifacts-paths-oci.sh
```

### Via Nix:

```bash
# Local executor
nix run .#example-artifacts
nix run .#example-artifacts-paths

# OCI executor (requires Docker)
nix run .#example-artifacts-oci
nix run .#example-artifacts-paths-oci
```

**Note:** OCI examples require Docker to be installed and running.
