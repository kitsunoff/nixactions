# Test OCI executor with copyRepo
# Uses buildLayeredImage - no external image required!
{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-oci-copyrepo";
  
  jobs = {
    # Test with copyRepo enabled (default) - shared mode
    with-copy = {
      executor = platform.executors.oci { 
        name = "oci-shared";
        mode = "shared";
        copyRepo = true;
      };
      
      actions = [
        {
          name = "check-files";
          bash = ''
            echo "Testing OCI executor with copyRepo=true (shared mode)"
            echo "Current directory: $PWD"
            ls -la
            
            # Check if README.md exists (copied from repo)
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
    
    # Test with copyRepo disabled - isolated mode
    without-copy = {
      executor = platform.executors.oci { 
        name = "oci-isolated";
        mode = "isolated";
        copyRepo = false;
      };
      
      actions = [
        {
          name = "check-no-files";
          bash = ''
            echo "Testing OCI executor with copyRepo=false (isolated mode)"
            echo "Current directory: $PWD"
            ls -la
            
            # README.md should NOT exist
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
