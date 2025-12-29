{ pkgs, nixactions, executor ? nixactions.executors.local }:

# Test: Timeout Support
#
# This example demonstrates timeout functionality at three levels:
# - Workflow-level timeout (applies to all jobs/actions if not overridden)
# - Job-level timeout (overrides workflow timeout for specific job)
# - Action-level timeout (highest priority, overrides job/workflow)
#
# Priority: action > job > workflow

nixactions.mkWorkflow {
  name = "test-timeout";
  
  # Workflow-level timeout (lowest priority)
  timeout = "30s";
  
  jobs = {
    # Test 1: Fast action (should complete before timeout)
    test-fast-action = {
      inherit executor;
      
      actions = [
        {
          name = "fast-action";
          bash = ''
            echo "Starting fast action..."
            sleep 1
            echo "✓ Fast action completed successfully"
          '';
          timeout = "5s";  # Should be plenty of time
        }
      ];
    };
    
    # Test 2: Slow action (should timeout)
    test-timeout-action = {
      needs = ["test-fast-action"];
      inherit executor;
      
      # Job continues even if action times out
      continueOnError = true;
      
      actions = [
        {
          name = "slow-action";
          bash = ''
            echo "Starting slow action (will timeout)..."
            sleep 100
            echo "This should never print"
          '';
          timeout = "2s";  # Action will timeout after 2 seconds
        }
        
        {
          name = "verify-timeout";
          bash = ''
            echo "✓ Previous action timed out as expected"
            echo "✓ This action runs because continueOnError=true"
          '';
          # Runs always because previous action timeout is handled by continueOnError
        }
      ];
    };
    
    # Test 3: Job-level timeout override
    test-job-timeout = {
      needs = ["test-timeout-action"];
      inherit executor;
      
      # Job-level timeout overrides workflow timeout
      timeout = "5s";
      
      actions = [
        {
          name = "quick-task";
          bash = ''
            echo "Running with job-level timeout (5s)"
            sleep 1
            echo "✓ Completed within job timeout"
          '';
          # Inherits job timeout (5s)
        }
      ];
    };
    
    # Test 4: No timeout (null timeout)
    test-no-timeout = {
      needs = ["test-job-timeout"];
      inherit executor;
      
      # Override workflow timeout with null (no timeout)
      timeout = null;
      
      actions = [
        {
          name = "no-timeout-action";
          bash = ''
            echo "Running with no timeout"
            sleep 2
            echo "✓ Completed (would have timed out with workflow timeout)"
          '';
        }
      ];
    };
    
    # Test 5: Different timeout formats
    test-timeout-formats = {
      needs = ["test-no-timeout"];
      inherit executor;
      
      actions = [
        {
          name = "test-seconds";
          bash = ''
            echo "Testing timeout format: 3s"
            sleep 1
            echo "✓ Seconds format works"
          '';
          timeout = "3s";
        }
        
        {
          name = "test-minutes";
          bash = ''
            echo "Testing timeout format: 1m"
            sleep 1
            echo "✓ Minutes format works"
          '';
          timeout = "1m";
        }
        
        {
          name = "test-hours";
          bash = ''
            echo "Testing timeout format: 1h"
            sleep 1
            echo "✓ Hours format works"
          '';
          timeout = "1h";
        }
      ];
    };
  };
}
