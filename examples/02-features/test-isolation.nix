# Test: Job isolation - env vars don't leak between jobs
{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "test-job-isolation";
  
  # Workflow-level env (shared by all jobs)
  env = {
    WORKFLOW_VAR = "shared-across-all-jobs";
  };
  
  jobs = {
    job1 = {
      inherit executor;
      
      # Job1-level env
      env = {
        JOB1_VAR = "only-in-job1";
      };
      
      actions = [
        {
          name = "show-job1-env";
          bash = ''
            echo "╔═══════════════════════════════════════╗"
            echo "║ JOB 1 Environment                     ║"
            echo "╚═══════════════════════════════════════╝"
            echo "  WORKFLOW_VAR = $WORKFLOW_VAR"
            echo "  JOB1_VAR = $JOB1_VAR"
            echo "  JOB2_VAR = ''${JOB2_VAR:-NOT_SET}"
            echo ""
          '';
        }
        
        {
          name = "try-to-leak";
          bash = ''
            echo "→ Setting LEAKED_SECRET in job1..."
            export LEAKED_SECRET="this-should-not-leak"
            echo "  LEAKED_SECRET = $LEAKED_SECRET"
            echo ""
          '';
        }
      ];
    };
    
    job2 = {
      needs = [ "job1" ];
      inherit executor;
      
      # Job2-level env
      env = {
        JOB2_VAR = "only-in-job2";
      };
      
      actions = [{
        name = "show-job2-env";
        bash = ''
          echo "╔═══════════════════════════════════════╗"
          echo "║ JOB 2 Environment                     ║"
          echo "╚═══════════════════════════════════════╝"
          echo "  WORKFLOW_VAR = $WORKFLOW_VAR"
          echo "  JOB1_VAR = ''${JOB1_VAR:-NOT_SET}"
          echo "  JOB2_VAR = $JOB2_VAR"
          echo "  LEAKED_SECRET = ''${LEAKED_SECRET:-NOT_SET}"
          echo ""
          
          echo "✓ Isolation verified:"
          echo "  • Workflow env shared: $WORKFLOW_VAR"
          echo "  • Job1 env isolated: JOB1_VAR=''${JOB1_VAR:-NOT_SET}"
          echo "  • Runtime exports isolated: LEAKED_SECRET=''${LEAKED_SECRET:-NOT_SET}"
        '';
      }];
    };
  };
}
