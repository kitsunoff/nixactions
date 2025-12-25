# Test LOCAL executor: shared vs isolated
# This will prove that actionDerivations contains ALL actions from jobs sharing the same executor name

{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-local-shared-vs-isolated";
  
  jobs = {
    # ========================================
    # GROUP 1: SHARED executor (default local)
    # ========================================
    
    job1-shared = {
      executor = platform.executors.local;  # name = "local" (default)
      
      actions = [{
        name = "job1-action";
        bash = ''
          echo "→ Job 1 (SHARED executor: local)"
          echo "Action: job1-action"
        '';
      }];
    };
    
    job2-shared = {
      executor = platform.executors.local;  # name = "local" (SAME!)
      
      actions = [{
        name = "job2-action";
        bash = ''
          echo "→ Job 2 (SHARED executor: local)"
          echo "Action: job2-action"
        '';
      }];
    };
    
    job3-shared = {
      executor = platform.executors.local;  # name = "local" (SAME!)
      
      actions = [{
        name = "job3-action";
        bash = ''
          echo "→ Job 3 (SHARED executor: local)"
          echo "Action: job3-action"
        '';
      }];
    };
    
    # ========================================
    # GROUP 2: ISOLATED executors (custom names)
    # ========================================
    
    job4-isolated = {
      executor = platform.executors.local { name = "isolated-env-1"; };
      
      actions = [{
        name = "job4-action";
        bash = ''
          echo "→ Job 4 (ISOLATED executor: isolated-env-1)"
          echo "Action: job4-action"
        '';
      }];
    };
    
    job5-isolated = {
      executor = platform.executors.local { name = "isolated-env-2"; };
      
      actions = [{
        name = "job5-action";
        bash = ''
          echo "→ Job 5 (ISOLATED executor: isolated-env-2)"
          echo "Action: job5-action"
        '';
      }];
    };
  };
}
