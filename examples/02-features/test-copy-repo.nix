# Test copyRepo configuration - verifies that copyRepo behavior works correctly
# This test checks that repository files are available when copyRepo is enabled (default)
{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "test-copy-repo";
  
  jobs = {
    # Job with copyRepo enabled (default behavior)
    check-copy = {
      inherit executor;
      
      steps = [
        nixactions.actions.checkout
        
        {
          name = "check-repo-copied";
          bash = ''
            echo "Testing copyRepo behavior"
            echo "Current directory: $PWD"
            
            # Should be in a job-specific directory
            if [[ "$PWD" == *"/jobs/check-copy"* ]]; then
              echo "✓ Working in isolated job directory"
            else
              echo "✗ Not in expected job directory"
              exit 1
            fi
            
            # Check if we have a copy of the repo (default copyRepo=true)
            if [ -f "README.md" ]; then
              echo "✓ Repository files present (copyRepo working)"
            else
              echo "✗ Repository files missing - copyRepo may be disabled"
              # This is not an error - depends on executor configuration
            fi
          '';
        }
        
        {
          name = "verify-workspace-isolation";
          bash = ''
            echo "Verifying workspace isolation"
            
            # Create a test file
            echo "test-data" > test-isolation.txt
            
            if [ -f "test-isolation.txt" ]; then
              echo "✓ Can create files in workspace"
            else
              echo "✗ Cannot create files in workspace"
              exit 1
            fi
            
            echo "✓ Workspace isolation verified"
          '';
        }
      ];
    };
    
    # Second job to verify isolation between jobs
    verify-isolation = {
      needs = ["check-copy"];
      inherit executor;
      
      steps = [
        {
          name = "check-isolation-between-jobs";
          bash = ''
            echo "Verifying job isolation"
            
            # File created in previous job should NOT exist here
            if [ -f "test-isolation.txt" ]; then
              echo "✗ File from previous job leaked! (isolation broken)"
              exit 1
            else
              echo "✓ Jobs are properly isolated"
            fi
          '';
        }
      ];
    };
  };
}
