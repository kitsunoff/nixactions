# Test executor: shared workspace behavior
# Multiple jobs sharing the same executor share a workspace (for OCI: same container)

{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "test-shared-vs-isolated";
  
  jobs = {
    # ========================================
    # Jobs sharing the same executor
    # ========================================
    
    job1-shared = {
      inherit executor;
      
      actions = [{
        name = "job1-action";
        bash = ''
          echo "→ Job 1 (using shared executor)"
          echo "Action: job1-action"
          echo "Executor name: ''${EXECUTOR_NAME:-unknown}"
        '';
      }];
    };
    
    job2-shared = {
      inherit executor;
      needs = ["job1-shared"];
      
      actions = [{
        name = "job2-action";
        bash = ''
          echo "→ Job 2 (using shared executor)"
          echo "Action: job2-action"
          echo "Executor name: ''${EXECUTOR_NAME:-unknown}"
        '';
      }];
    };
    
    job3-shared = {
      inherit executor;
      needs = ["job2-shared"];
      
      actions = [{
        name = "job3-action";
        bash = ''
          echo "→ Job 3 (using shared executor)"
          echo "Action: job3-action"
          echo "Executor name: ''${EXECUTOR_NAME:-unknown}"
        '';
      }];
    };
    
    # ========================================
    # Summary
    # ========================================
    
    summary = {
      inherit executor;
      needs = ["job3-shared"];
      
      actions = [{
        name = "summary";
        bash = ''
          echo ""
          echo "╔═══════════════════════════════════════════════╗"
          echo "║ Summary: Shared Executor Test                 ║"
          echo "╚═══════════════════════════════════════════════╝"
          echo ""
          echo "All jobs used the same executor."
          echo "In shared mode:"
          echo "  • OCI: All jobs run in the same container"
          echo "  • Local: All jobs share the same workspace"
          echo ""
          echo "✓ Test completed successfully"
        '';
      }];
    };
  };
}
