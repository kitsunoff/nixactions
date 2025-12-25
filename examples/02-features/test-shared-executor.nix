# Test shared executor concept
# Multiple jobs using the SAME executor (by name)
# Should result in:
# - 1 setupWorkspace call
# - actionDerivations contains ALL actions from ALL jobs
# - 1 cleanupWorkspace call

{ pkgs, platform }:

platform.mkWorkflow {
  name = "test-shared-executor";
  
  jobs = {
    # Job 1: Build
    build = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      # This will use executor name = "oci-nixos_nix"
      
      actions = [{
        name = "build-action";
        bash = ''
          echo "→ Building..."
          echo "Job: build"
          echo "Executor: oci-nixos_nix"
          echo "Workspace: $PWD"
          mkdir -p output
          echo "build result" > output/artifact.txt
        '';
      }];
      
      outputs = {
        build-output = "output/";
      };
    };
    
    # Job 2: Test (uses SAME executor)
    test = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      # This will ALSO use executor name = "oci-nixos_nix" (SHARED!)
      
      needs = ["build"];
      inputs = ["build-output"];
      
      actions = [{
        name = "test-action";
        bash = ''
          echo "→ Testing..."
          echo "Job: test"
          echo "Executor: oci-nixos_nix (SHARED with build!)"
          echo "Workspace: $PWD"
          
          if [ -f "output/artifact.txt" ]; then
            echo "✓ Artifact found!"
            cat output/artifact.txt
          else
            echo "✗ Artifact NOT found!"
            exit 1
          fi
        '';
      }];
    };
    
    # Job 3: Deploy (uses SAME executor)
    deploy = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      # This will ALSO use executor name = "oci-nixos_nix" (SHARED!)
      
      needs = ["test"];
      
      actions = [{
        name = "deploy-action";
        bash = ''
          echo "→ Deploying..."
          echo "Job: deploy"
          echo "Executor: oci-nixos_nix (SHARED with build and test!)"
          echo "Workspace: $PWD"
        '';
      }];
    };
  };
}
