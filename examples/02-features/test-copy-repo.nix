# Test copyRepo configuration - verifies that copyRepo can be disabled
{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-copy-repo";
  
  jobs = {
    # Job with copyRepo enabled (default)
    with-copy = {
      executor = platform.executors.local;
      
      actions = [
        platform.actions.checkout
        
        {
          name = "check-repo-copied";
          bash = ''
            echo "Testing with copyRepo=true (default)"
            echo "Current directory: $PWD"
            
            # Should be in a job-specific directory
            if [[ "$PWD" == *"/jobs/with-copy"* ]]; then
              echo "✓ Working in isolated job directory"
            else
              echo "✗ Not in expected job directory"
              exit 1
            fi
            
            # Check if we have a copy of the repo
            if [ -f "README.md" ]; then
              echo "✓ Repository files present"
            else
              echo "✗ Repository files missing"
              exit 1
            fi
          '';
        }
      ];
    };
    
    # Job with copyRepo disabled
    without-copy = {
      executor = platform.executors.local { copyRepo = false; };
      
      actions = [
        {
          name = "check-no-copy";
          bash = ''
            echo "Testing with copyRepo=false"
            echo "Current directory: $PWD"
            
            # Should still be in a job directory
            if [[ "$PWD" == *"/jobs/without-copy"* ]]; then
              echo "✓ Working in job directory"
            else
              echo "✗ Not in expected job directory"
              exit 1
            fi
            
            # Repository should NOT be copied
            if [ ! -f "README.md" ]; then
              echo "✓ Repository not copied (as expected)"
            else
              echo "✗ Repository was copied (unexpected)"
              exit 1
            fi
          '';
        }
      ];
    };
  };
}
