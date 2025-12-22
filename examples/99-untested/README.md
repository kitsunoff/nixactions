# Untested Examples

⚠️ **Warning:** These examples are NOT tested and may not work correctly.

These examples are included for reference but have not been validated in the current implementation.

## OCI Executor Examples

The following examples use the OCI (Docker) executor which is still under development:

### `docker-ci.nix`
Docker-based CI pipeline (NOT TESTED).

```bash
# May not work!
nix run ..#example-docker-ci
```

**Intended to demonstrate:**
- OCI executor with Docker containers
- Containerized builds
- Multi-stage pipelines in containers

**Status:** OCI executor needs testing and validation.

---

### `artifacts-simple-oci.nix`
Basic artifacts with OCI executor (NOT TESTED).

```bash
# May not work!
nix run ..#example-artifacts-simple-oci
```

**Intended to demonstrate:**
- Artifact transfer with OCI executor
- Docker cp for artifact saving/restoring

**Status:** OCI artifact transfer not validated.

---

### `artifacts-paths-oci.nix`
Multiple artifacts with OCI executor (NOT TESTED).

```bash
# May not work!
nix run ..#example-artifacts-paths-oci
```

**Intended to demonstrate:**
- Complex artifact graphs with OCI
- Multiple paths in containers

**Status:** OCI artifact transfer not validated.

---

### `artifacts-oci-build.nix`
Build artifacts inside OCI container (NOT TESTED).

```bash
# May not work!
nix run ..#example-artifacts-oci-build
```

**Intended to demonstrate:**
- Building inside containers
- Extracting build artifacts from containers

**Status:** OCI build mode not validated.

---

## Why Untested?

These examples are here because:

1. **OCI executor needs work** - Implementation incomplete
2. **No integration tests** - Haven't validated end-to-end
3. **Reference only** - Show intended design

## Future Plans

- [ ] Complete OCI executor implementation
- [ ] Test all OCI examples
- [ ] Move to `02-features/` when validated
- [ ] Add OCI-specific documentation

## Use At Your Own Risk

If you want to try these:

1. They might work partially
2. They might fail with unclear errors
3. Report issues if you find bugs
4. Contributions welcome!

---

## Contributing

If you want to help test/fix these:

1. Try running the example
2. Document what works/doesn't work
3. Fix issues and submit PR
4. Update this README when validated

Once tested, these will move to the appropriate category:
- `docker-ci.nix` → `03-real-world/`
- `artifacts-*-oci.nix` → `02-features/`
