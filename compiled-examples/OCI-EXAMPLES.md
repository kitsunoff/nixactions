# OCI Executor Artifacts Examples

These examples demonstrate how artifacts work with the **OCI (Docker) executor**.

## Key Differences from Local Executor

| Aspect | Local Executor | OCI Executor |
|--------|---------------|--------------|
| **Workspace** | `/tmp/nixactions/$WORKFLOW_ID` | Docker container |
| **Save** | `cp` on host | `docker cp` from container to host |
| **Restore** | `cp` on host | `docker cp` from host to container |
| **Cleanup** | `rm -rf` workspace dir | `docker stop && docker rm` |

## How It Works

### 1. Setup Workspace (per job)

```bash
# Create and start container
CONTAINER_ID=$(docker create -v /nix/store:/nix/store:ro nixos/nix sleep infinity)
docker start "$CONTAINER_ID"
docker exec "$CONTAINER_ID" mkdir -p /workspace
```

### 2. Restore Artifacts (before job)

```bash
# Copy from host to container
docker exec "$CONTAINER_ID" mkdir -p "/workspace/jobs/test"
for item in "$NIXACTIONS_ARTIFACTS_DIR/my-artifact"/*; do
  docker cp "$item" "$CONTAINER_ID:/workspace/jobs/test/"
done
```

### 3. Execute Job (in container)

```bash
# Run job script inside container
docker exec "$CONTAINER_ID" bash -c '
  cd /workspace/jobs/build
  # ... job script ...
'
```

### 4. Save Artifacts (after job)

```bash
# Check if path exists in container
docker exec "$CONTAINER_ID" test -e "/workspace/jobs/build/dist/"

# Copy from container to host
docker cp "$CONTAINER_ID:/workspace/jobs/build/dist/" \
  "$NIXACTIONS_ARTIFACTS_DIR/my-artifact/dist/"
```

### 5. Cleanup (after job)

```bash
docker stop "$CONTAINER_ID"
docker rm "$CONTAINER_ID"
```

## Artifacts Directory Structure

Artifacts are stored **on the host** (same as local executor):

```
$HOME/.cache/nixactions/$WORKFLOW_ID/artifacts/
├── dist/
│   └── dist/
│       ├── app.js
│       └── index.html
└── myapp/
    └── myapp
```

This ensures artifacts **persist** across jobs, even though containers are created and destroyed.

## Running the Examples

```bash
# Requires Docker to be installed and running
nix run .#example-artifacts-oci
nix run .#example-artifacts-paths-oci
```

## See Also

- `artifacts-simple-oci.sh` - compiled bash script showing full implementation
- `artifacts-paths-oci.sh` - nested paths with OCI executor
- `README.md` - comparison table and architecture overview
