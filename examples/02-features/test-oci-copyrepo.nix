# Test OCI executor with copyRepo
{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-oci-copyrepo";
  
  jobs = {
    # Test with copyRepo enabled (default)
    with-copy = {
      executor = platform.executors.oci { 
        image = "nixos/nix";
        copyRepo = true;
      };
      
      actions = [
        {
          name = "check-files";
          bash = ''
            echo "Testing OCI executor with copyRepo=true"
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
    
    # Test with copyRepo disabled
    without-copy = {
      executor = platform.executors.oci { 
        image = "nixos/nix";
        copyRepo = false;
      };
      
      actions = [
        {
          name = "check-no-files";
          bash = ''
            echo "Testing OCI executor with copyRepo=false"
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
