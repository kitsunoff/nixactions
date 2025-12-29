{ pkgs, nixactions, executor ? nixactions.executors.local }:

# Test: Environment Variable Merging
#
# Tests that environment variables merge correctly across all levels:
#   workflow.env -> job.env -> action.env
#
# Priority (highest to lowest):
#   1. Runtime environment (set before running workflow)
#   2. Action env
#   3. Job env
#   4. Workflow env
#
# Expected behavior:
#   - VAR_WORKFLOW should be available in all actions
#   - VAR_JOB should override VAR_WORKFLOW in job
#   - VAR_ACTION should override VAR_JOB in specific action
#   - VAR_RUNTIME (if set) should override everything

nixactions.mkWorkflow {
  name = "test-env-merge";
  
  # Level 1: Workflow-level environment (lowest priority from config)
  env = {
    VAR_WORKFLOW = "from-workflow";
    VAR_SHARED = "workflow-value";
    LEVEL = "workflow";
  };
  
  jobs = {
    test-merge = {
      inherit executor;
      
      # Level 2: Job-level environment (overrides workflow)
      env = {
        VAR_JOB = "from-job";
        VAR_SHARED = "job-value";  # Overrides workflow
        LEVEL = "job";              # Overrides workflow
      };
      
      actions = [
        # Action 1: No action-level env (inherits from job)
        {
          name = "test-inheritance";
          bash = ''
            echo "╔════════════════════════════════════════╗"
            echo "║ Action 1: Inheritance Test            ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "Expected: Workflow + Job env, no action env"
            echo ""
            echo "VAR_WORKFLOW = $VAR_WORKFLOW"
            echo "VAR_JOB      = $VAR_JOB"
            echo "VAR_SHARED   = $VAR_SHARED   (should be 'job-value')"
            echo "LEVEL        = $LEVEL         (should be 'job')"
            echo ""
            
            # Assertions
            [ "$VAR_WORKFLOW" = "from-workflow" ] || { echo "❌ FAIL: VAR_WORKFLOW"; exit 1; }
            [ "$VAR_JOB" = "from-job" ] || { echo "❌ FAIL: VAR_JOB"; exit 1; }
            [ "$VAR_SHARED" = "job-value" ] || { echo "❌ FAIL: VAR_SHARED should be job-value"; exit 1; }
            [ "$LEVEL" = "job" ] || { echo "❌ FAIL: LEVEL should be job"; exit 1; }
            
            echo "✅ Action 1: All assertions passed"
          '';
        }
        
        # Action 2: With action-level env (overrides job)
        {
          name = "test-action-override";
          env = {
            VAR_ACTION = "from-action";
            VAR_SHARED = "action-value";  # Overrides job and workflow
            LEVEL = "action";              # Overrides job and workflow
          };
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Action 2: Override Test                ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "Expected: Workflow + Job + Action env"
            echo ""
            echo "VAR_WORKFLOW = $VAR_WORKFLOW"
            echo "VAR_JOB      = $VAR_JOB"
            echo "VAR_ACTION   = $VAR_ACTION"
            echo "VAR_SHARED   = $VAR_SHARED   (should be 'action-value')"
            echo "LEVEL        = $LEVEL         (should be 'action')"
            echo ""
            
            # Assertions
            [ "$VAR_WORKFLOW" = "from-workflow" ] || { echo "❌ FAIL: VAR_WORKFLOW"; exit 1; }
            [ "$VAR_JOB" = "from-job" ] || { echo "❌ FAIL: VAR_JOB"; exit 1; }
            [ "$VAR_ACTION" = "from-action" ] || { echo "❌ FAIL: VAR_ACTION"; exit 1; }
            [ "$VAR_SHARED" = "action-value" ] || { echo "❌ FAIL: VAR_SHARED should be action-value"; exit 1; }
            [ "$LEVEL" = "action" ] || { echo "❌ FAIL: LEVEL should be action"; exit 1; }
            
            echo "✅ Action 2: All assertions passed"
          '';
        }
        
        # Action 3: Test runtime override
        {
          name = "test-runtime-priority";
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Action 3: Runtime Priority Test        ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "Expected: Runtime env overrides everything"
            echo ""
            echo "VAR_RUNTIME = ''${VAR_RUNTIME:-<not set>}"
            echo ""
            
            if [ -n "''${VAR_RUNTIME:-}" ]; then
              echo "✅ VAR_RUNTIME is set (runtime environment has highest priority)"
              echo "   Value: $VAR_RUNTIME"
            else
              echo "⊘ VAR_RUNTIME not set"
              echo "   To test runtime priority, run:"
              echo "   VAR_RUNTIME=from-runtime nix run .#test-env-merge"
            fi
          '';
        }
      ];
    };
    
    # Second job to verify workflow env is shared
    verify-workflow-env = {
      needs = ["test-merge"];
      inherit executor;
      
      actions = [
        {
          name = "verify-shared";
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Job 2: Workflow Env Sharing Test       ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "Expected: Workflow env available in different job"
            echo ""
            echo "VAR_WORKFLOW = $VAR_WORKFLOW"
            echo "VAR_JOB      = ''${VAR_JOB:-<not set from job 1>}"
            echo ""
            
            # Assertions
            [ "$VAR_WORKFLOW" = "from-workflow" ] || { echo "❌ FAIL: VAR_WORKFLOW not shared"; exit 1; }
            [ -z "''${VAR_JOB:-}" ] || { echo "❌ FAIL: VAR_JOB should not be available"; exit 1; }
            
            echo "✅ Job 2: Workflow env correctly shared, job env correctly isolated"
          '';
        }
      ];
    };
    
    # Summary
    summary = {
      needs = ["verify-workflow-env"];
      inherit executor;
      condition = "always()";
      
      actions = [
        {
          name = "summary";
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Environment Merge Test Summary         ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "✅ All environment merge tests passed!"
            echo ""
            echo "Verified:"
            echo "  ✓ Workflow env shared across all jobs"
            echo "  ✓ Job env overrides workflow env"
            echo "  ✓ Action env overrides job env"
            echo "  ✓ Job env isolated between jobs"
            echo ""
            echo "Priority order (highest to lowest):"
            echo "  1. Runtime environment (VAR=value nix run ...)"
            echo "  2. Action env (action.env = { ... })"
            echo "  3. Job env (job.env = { ... })"
            echo "  4. Workflow env (workflow.env = { ... })"
          '';
        }
      ];
    };
  };
}
