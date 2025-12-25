# Test custom executor names
# This example shows how to use the same image but with different names
# to create separate workspaces/container pools

{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-custom-executor-names";
  
  jobs = {
    # Build job - uses custom name "build-env"
    build = {
      executor = platform.executors.oci { 
        image = "nixos/nix";
        name = "build-env";  # Custom name!
      };
      
      actions = [{
        name = "build";
        bash = ''
          echo "→ Building in build-env executor"
          echo "Container: $HOSTNAME"
          echo "Workspace: $PWD"
        '';
      }];
    };
    
    # Test job - uses custom name "test-env"  
    # Same image, but DIFFERENT workspace!
    test = {
      executor = platform.executors.oci { 
        image = "nixos/nix";
        name = "test-env";  # Different name = different workspace!
      };
      
      needs = ["build"];
      
      actions = [{
        name = "test";
        bash = ''
          echo "→ Testing in test-env executor"
          echo "Container: $HOSTNAME"
          echo "Workspace: $PWD"
        '';
      }];
    };
    
    # Deploy job - NO custom name (uses default)
    # Should use workspace "oci-nixos_nix"
    deploy = {
      executor = platform.executors.oci { 
        image = "nixos/nix";
        # No name = uses default "oci-nixos_nix"
      };
      
      needs = ["test"];
      
      actions = [{
        name = "deploy";
        bash = ''
          echo "→ Deploying in default executor"
          echo "Container: $HOSTNAME"
          echo "Workspace: $PWD"
        '';
      }];
    };
  };
}
