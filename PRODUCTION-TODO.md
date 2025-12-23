# Production Readiness TODO

**Current Status: MVP (60% Production Ready)**  
**Estimated Time to Production: 2-3 weeks**

---

## 🔴 CRITICAL (BLOCKERS - Must Fix)

### 1. Secrets Masking in Logs
**Priority: CRITICAL** | **Time: 1-2 days** | **Risk: Security breach**

```bash
# Current: Secrets visible in logs
→ Deploying with key: sk_live_123abc456def

# Need: Masked secrets
→ Deploying with key: ***
```

**Implementation:**
- [ ] Track secret environment variables
- [ ] Scan all output for secret values
- [ ] Replace with `***` in logs
- [ ] Add `secrets: [...]` option to workflow config
- [ ] Auto-mask variables loaded by secret actions (sops, vault, etc.)

**Files to modify:**
- `lib/mk-workflow.nix` - Add secrets tracking
- `lib/logging.nix` - Add masking to `_log` function
- All secret actions - Auto-register secret vars

**Test:**
```bash
nix run .#example-secrets | grep -q "sk_live" && echo "FAIL: Secret leaked!" || echo "PASS"
```

---

### 2. Timeout Support
**Priority: CRITICAL** | **Time: 1 day** | **Risk: Infinite hangs**

```nix
{
  jobs = {
    build = {
      timeout = "30m";  # Job timeout
      actions = [
        {
          bash = "npm run build";
          timeout = "10m";  # Action timeout
        }
      ];
    };
  };
}
```

**Implementation:**
- [ ] Add `timeout` field to Job config
- [ ] Add `timeout` field to Action config
- [ ] Wrap action execution with `timeout` command or bash `SECONDS` check
- [ ] Kill process tree on timeout
- [ ] Log timeout with clear message

**Files to modify:**
- `lib/mk-workflow.nix` - Accept timeout in config
- Generated bash script - Add timeout wrapper

**Test:**
```nix
{
  actions = [{
    bash = "sleep 100";
    timeout = "1s";
  }];
}
# Should fail with timeout after 1s
```

---

### 3. Retry Logic
**Priority: HIGH** | **Time: 1 day** | **Risk: Flaky failures**

```nix
{
  actions = [{
    bash = "npm install";
    retry = {
      max_attempts = 3;
      backoff = "exponential";  # 1s, 2s, 4s
    };
  }];
}
```

**Implementation:**
- [ ] Add `retry` field to Action config
- [ ] Wrap action execution in retry loop
- [ ] Implement backoff strategies (linear, exponential)
- [ ] Log each retry attempt
- [ ] Only retry on non-zero exit codes

**Files to modify:**
- `lib/mk-workflow.nix` - Accept retry in config
- Generated bash script - Add retry loop

**Test:**
```nix
{
  actions = [{
    bash = "exit 1";  # Always fails
    retry.max_attempts = 3;
  }];
}
# Should try 3 times before failing
```

---

### 4. Better Error Messages
**Priority: HIGH** | **Time: 2-3 days** | **Risk: Poor DX**

```bash
# Current:
error: cannot coerce null to a string: null

# Need:
Error in workflow 'ci', job 'test', action 'deploy':
  ✗ Variable $BRANCH is not set
  
  Hint: Set BRANCH at workflow/job/action level:
    env = { BRANCH = "main"; };
  
  Or provide at runtime:
    BRANCH=main nix run .#ci
```

**Implementation:**
- [ ] Add try-catch wrappers around Nix code
- [ ] Add context (workflow/job/action names) to errors
- [ ] Detect common errors (missing vars, missing files)
- [ ] Provide helpful hints
- [ ] Pretty-print error messages

**Files to modify:**
- `lib/mk-workflow.nix` - Add error handling
- All actions - Add validation

**Test:**
- Missing env var → helpful error
- Missing file → helpful error
- Syntax error → helpful error

---

### 5. Graceful Cancellation
**Priority: HIGH** | **Time: 1 day** | **Risk: Resource leaks**

**Implementation:**
- [ ] Improve SIGINT/SIGTERM handling
- [ ] Ensure cleanup jobs run on cancellation
- [ ] Kill all child processes
- [ ] Cleanup containers/VMs
- [ ] Log cancellation clearly

**Files to modify:**
- Generated bash script - Improve trap handling
- Executors - Add cleanup on cancellation

**Test:**
```bash
# Start long workflow
nix run .#long-workflow &
PID=$!

# Cancel it
sleep 2
kill -SIGINT $PID

# Check cleanup ran
# Check no containers left running
```

---

## 🟡 HIGH PRIORITY (Should Have)

### 6. Test Remote Executors
**Priority: HIGH** | **Time: 3-5 days** | **Risk: Unknown stability**

**Tasks:**
- [ ] Test OCI executor (docker-ci.nix)
- [ ] Test SSH executor with real SSH
- [ ] Test kubernetes executor with minikube
- [ ] Move working examples out of `99-untested/`
- [ ] Document executor requirements
- [ ] Add executor troubleshooting guides

**Files to test:**
- `examples/99-untested/docker-ci.nix`
- `examples/99-untested/artifacts-oci*.nix`
- `lib/executors/oci.nix`
- `lib/executors/ssh.nix`
- `lib/executors/k8s.nix`

---

### 7. Job Outputs
**Priority: MEDIUM** | **Time: 2-3 days** | **Impact: Feature gap**

```nix
{
  jobs = {
    version = {
      actions = [{
        bash = ''
          echo "VERSION=1.2.3" >> $GITHUB_OUTPUT
        '';
      }];
    };
    
    deploy = {
      needs = ["version"];
      actions = [{
        bash = ''
          echo "Version: ${{ needs.version.outputs.VERSION }}"
        '';
      }];
    };
  };
}
```

**Implementation:**
- [ ] Add `$GITHUB_OUTPUT` file per job
- [ ] Parse outputs after job completes
- [ ] Make available to dependent jobs
- [ ] Support interpolation syntax `${{ needs.job.outputs.var }}`

---

### 8. Caching Support
**Priority: MEDIUM** | **Time: 3-5 days** | **Impact: Speed**

```nix
{
  jobs = {
    test = {
      cache = {
        paths = ["node_modules"];
        key = "deps-${{ hashFiles('package-lock.json') }}";
      };
    };
  };
}
```

**Implementation:**
- [ ] Add cache directory (`~/.cache/nixactions/cache`)
- [ ] Hash-based cache keys
- [ ] Restore before actions
- [ ] Save after actions
- [ ] LRU eviction policy

---

## 🟢 NICE TO HAVE (Quality of Life)

### 9. CLI Tool
**Priority: LOW** | **Time: 2-3 days**

```bash
nixactions run ci
nixactions validate
nixactions list
nixactions graph ci
```

**Implementation:**
- [ ] Create CLI wrapper script
- [ ] Add subcommands (run, validate, list, graph)
- [ ] Add to flake apps

---

### 10. Automated Testing
**Priority: MEDIUM** | **Time: 3-5 days**

**Tasks:**
- [ ] Create test framework
- [ ] Test all 20 compiled examples
- [ ] Test error conditions
- [ ] Test cancellation
- [ ] Add CI/CD for NixActions itself
- [ ] Test matrix (multiple platforms)

---

## 📊 Definition of Done (Production Ready)

### Must Have (CRITICAL):
- ✅ Secrets masking implemented and tested
- ✅ Timeout support for jobs and actions
- ✅ Retry logic for flaky operations
- ✅ Better error messages with context
- ✅ Graceful cancellation with cleanup

### Should Have (HIGH):
- ✅ OCI executor tested and working
- ✅ SSH executor tested and working
- ✅ Job outputs implementation
- ✅ All examples passing tests

### Nice to Have (MEDIUM):
- ✅ Caching support
- ✅ CLI tool
- ✅ Automated test suite
- ✅ CI/CD for NixActions

---

## 🎯 Recommended Implementation Order

1. **Week 1: Critical Blockers**
   - Day 1-2: Secrets masking
   - Day 3: Timeout support
   - Day 4: Retry logic
   - Day 5: Better error messages

2. **Week 2: Testing & Reliability**
   - Day 1: Graceful cancellation
   - Day 2-4: Test remote executors
   - Day 5: Fix bugs found

3. **Week 3: Nice-to-Haves**
   - Day 1-2: Job outputs
   - Day 3-4: Caching
   - Day 5: Documentation updates

**Total: ~15 working days to production-ready**

---

## 🚦 Current Production Readiness Score

| Category | Score | Blocker? |
|----------|-------|----------|
| Core Engine | 95% | ✅ No |
| Local Executor | 90% | ✅ No |
| **Security** | 30% | 🔴 **YES** |
| **Reliability** | 40% | 🔴 **YES** |
| Remote Executors | 20% | 🟡 Partial |
| Testing | 20% | 🟡 Partial |
| Developer Experience | 60% | ✅ No |

**Overall: 60% → Need 90%+ for production**

---

## 📝 Agent Instructions

For each task above:

1. **Read** the current implementation
2. **Design** the solution (write plan in comments)
3. **Implement** the feature
4. **Test** with examples
5. **Document** in README/examples
6. **Commit** with clear message

**Start with:** Task #1 (Secrets Masking) - highest impact on security
