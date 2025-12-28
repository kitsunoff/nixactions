# Roadmap

Current status and planned features for NixActions.

---

## Current Status: v4.0

NixActions v4.0 implements the core vision:

> GitHub Actions execution model + Nix reproducibility + Actions as Derivations

---

## Phase 1: MVP - COMPLETED

- [x] Actions as derivations (build-time compilation)
- [x] Build-time validation
- [x] Executor provisioning with 5-hook model
- [x] Condition system (job + step level)
- [x] Built-in conditions: `success()`, `failure()`, `always()`, `cancelled()`
- [x] Bash script conditions
- [x] Local executor with workspace/job isolation
- [x] OCI executor with `buildLayeredImage`
- [x] Shared and isolated modes for OCI
- [x] Cross-platform support (Darwin -> Linux containers)
- [x] Basic actions library
- [x] Retry mechanism (3 backoff strategies)
- [x] Timeout handling
- [x] Artifacts management with custom restore paths
- [x] Environment providers (file, sops, static, required)
- [x] Matrix job generation (`mkMatrixJobs`)
- [x] Structured logging (3 formats)
- [x] Executor deduplication by name
- [x] 30+ working examples
- [x] Comprehensive test suites

---

## Phase 2: Remote Executors - IN PROGRESS

### SSH Executor

- [ ] Basic SSH executor (shared mode)
- [ ] nix-copy-closure integration
- [ ] Artifact transfer via SCP
- [ ] Environment passing
- [ ] Pool mode (multiple hosts)
- [ ] Dedicated mode (per-job connection)

### Kubernetes Executor

- [ ] Pod creation/deletion
- [ ] kubectl cp for artifacts
- [ ] Environment via -e flags
- [ ] Shared pod mode
- [ ] PVC support for /nix/store

### NixOS VM Executor

- [ ] VM generation from NixOS config
- [ ] 9p filesystem for /nix/store
- [ ] SSH control channel
- [ ] Dedicated mode (per-job VMs)

---

## Phase 3: Ecosystem

### Extended Actions Library

- [ ] More setup actions (Go, Java, etc.)
- [ ] Cloud provider actions (AWS, GCP, Azure)
- [ ] Container registry actions
- [ ] Notification actions (Slack, Discord, etc.)
- [ ] Database actions

### Documentation

- [x] Architecture documentation
- [x] API reference
- [x] User guide
- [ ] Tutorial series
- [ ] Video walkthroughs
- [ ] Cookbook/recipes

### Developer Experience

- [ ] Better error messages
- [ ] Workflow visualization
- [ ] Dry-run mode
- [ ] Watch mode for development

---

## Phase 4: Production Hardening

### Reliability

- [ ] Graceful shutdown handling
- [ ] State recovery on failure
- [ ] Distributed locking for pool executors
- [ ] Health checks for remote executors

### Observability

- [ ] OpenTelemetry integration
- [ ] Prometheus metrics
- [ ] Log aggregation support
- [ ] Tracing across jobs

### Security

- [ ] Secret scanning in logs
- [ ] Audit logging
- [ ] RBAC for multi-tenant setups
- [ ] Secure artifact storage

---

## Phase 5: Advanced Features

### Caching

- [ ] Build cache sharing
- [ ] Artifact caching across workflows
- [ ] Remote cache support

### Triggers

- [ ] Git webhook integration
- [ ] Cron scheduling
- [ ] Event-driven execution

### UI/Dashboard

- [ ] Web UI for workflow status
- [ ] Real-time log streaming
- [ ] Historical runs
- [ ] Metrics dashboard

---

## Non-Goals

These are explicitly out of scope:

- **GitHub Actions compatibility** - Not trying to run GitHub Actions YAML
- **Marketplace** - Use Nix packages instead
- **Hosted service** - Run your own infrastructure
- **Agent daemon** - Agentless by design

---

## Contributing

Want to help? Check:

1. [GitHub Issues](https://github.com/yourorg/nixactions/issues) for open tasks
2. [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines
3. The items marked with `[ ]` above

Priority areas:
- SSH executor implementation
- Documentation improvements
- More examples
- Bug fixes

---

## Version History

### v4.0 (Current)

- Actions as Derivations
- 5-Hook Executor Model
- OCI executor with buildLayeredImage
- Full condition system
- Retry mechanism
- Environment providers

### v3.0 (Legacy)

- String-based action composition
- Basic executor model
- Limited conditions

---

## See Also

- [Philosophy](./philosophy.md) - Design principles
- [Architecture](./architecture.md) - System design
- [Comparison](./comparison.md) - vs other CI/CD
