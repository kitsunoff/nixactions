# Kubernetes Executor Implementation Plan

## Overview

Implement K8s executor that runs jobs in Kubernetes pods, reusing OCI image building logic.

## Architecture

```
setupWorkspace:
  1. docker load < tarball
  2. docker tag → registry/image:content-hash
  3. docker push (auth from env)
  4. kubectl run pod --image=...
  5. kubectl cp $PWD → pod:/workspace/.golden   ← "golden standard"

setupJob(jobName):
  1. kubectl exec: cp -r /workspace/.golden /workspace/jobs/{jobName}

executeJob(jobName):
  1. kubectl exec: cd /workspace/jobs/{jobName} && run actions

cleanupJob(jobName):
  1. (nothing for shared, delete pod for dedicated)

cleanupWorkspace:
  1. kubectl delete pod
```

## Tasks

### Phase 1: Refactor - Extract shared image building logic

- [ ] Create `lib/executors/oci-image-builder.nix`
  - [ ] Move `buildExecutorImage` from oci.nix
  - [ ] Move `toLinuxPkg` helper
  - [ ] Move `mkUniqueActionName` helper
  - [ ] Export `linuxActionDerivations` generation logic
  - [ ] Add `gnutar` to image contents (needed for kubectl cp)

- [ ] Update `lib/executors/oci.nix`
  - [ ] Import from oci-image-builder.nix
  - [ ] Verify OCI executor still works

- [ ] Test OCI executor after refactor
  - [ ] `nix run .#example-simple-oci-shared`
  - [ ] `nix run .#example-simple-oci-isolated`

### Phase 2: K8s Executor Implementation

- [ ] Create `lib/executors/k8s.nix`

- [ ] Configuration:
  ```nix
  {
    namespace = "default";
    registry = {
      url = null;           # required
      usernameEnv = null;   # required  
      passwordEnv = null;   # required
    };
    mode = "shared";        # "shared" | "dedicated"
    copyRepo = true;
    name = null;
    extraPackages = [];
    kubeconfigEnv = null;   # default: ~/.kube/config
    contextEnv = null;      # default: current context
    serviceAccount = null;
    nodeSelector = {};
    resources = {
      requests = { cpu = "500m"; memory = "1Gi"; };
      limits = { cpu = "2"; memory = "4Gi"; };
    };
    labels = {};
    annotations = {};
    podReadyTimeout = 300;  # 5 min
  }
  ```

- [ ] Implement hooks:
  - [ ] `setupWorkspace` (shared mode)
    - docker load/tag/push
    - kubectl run pod
    - kubectl wait --for=condition=Ready (5 min timeout, fail if not ready)
    - kubectl cp PWD → pod:/workspace/.golden
  - [ ] `setupWorkspace` (dedicated mode)
    - docker load/tag/push only
  - [ ] `cleanupWorkspace`
    - kubectl delete pod (shared mode)
    - nothing (dedicated mode)
  - [ ] `setupJob`
    - kubectl exec cp -r .golden → jobs/{jobName} (shared)
    - full pod creation + cp (dedicated)
  - [ ] `executeJob`
    - kubectl exec bash -c '...'
  - [ ] `cleanupJob`
    - nothing (shared)
    - kubectl delete pod (dedicated)
  - [ ] `saveArtifact`
    - kubectl cp pod:path → host
  - [ ] `restoreArtifact`
    - kubectl cp host → pod:path

- [ ] Pod naming: `nixactions-{workflowId}-{executorName}`

- [ ] Use full nix paths for commands:
  - `${pkgs.docker}/bin/docker`
  - `${pkgs.kubectl}/bin/kubectl`
  - `${pkgs.gzip}/bin/zcat`

### Phase 3: Integration

- [ ] Update `lib/executors/default.nix`
  - [ ] Add k8s executor export

- [ ] Update `lib/default.nix` (if needed)
  - [ ] Expose k8s in platform.executors

### Phase 4: Examples

- [ ] Create `examples/02-features/test-k8s.nix`
  - Basic k8s test with shared mode

- [ ] Create `examples/02-features/test-k8s-isolated.nix`
  - K8s test with dedicated mode

- [ ] Update `flake.nix`
  - Add k8s examples to packages (but skip in default build - needs cluster)

### Phase 5: Documentation

- [ ] Update `docs/executors.md`
  - [ ] K8s executor configuration
  - [ ] Usage examples
  - [ ] Registry auth setup
  - [ ] Troubleshooting

### Phase 6: Testing

- [ ] Manual test with local registry (docker run -d -p 5000:5000 registry:2)
- [ ] Test shared mode
- [ ] Test dedicated mode
- [ ] Test artifacts (save/restore)
- [ ] Test failure scenarios (pod not ready, registry auth fail)

## Dependencies

Runtime (in nix store, full paths used):
- `pkgs.docker` - load, tag, push, login
- `pkgs.kubectl` - run, exec, cp, delete, wait
- `pkgs.gzip` - zcat for tarball

In image:
- `lpkgs.gnutar` - required for kubectl cp

## Notes

- Pod ready timeout: 5 minutes, fail if not ready
- Image tag: content hash (same as OCI)
- Workspace structure:
  ```
  /workspace/
  ├── .golden/          ← repo copy (setupWorkspace)
  └── jobs/
      ├── build/        ← cp from .golden (setupJob)
      └── test/
  ```
