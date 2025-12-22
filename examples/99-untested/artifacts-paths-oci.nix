# Artifacts with nested paths - OCI executor
{ pkgs, platform }:

platform.mkWorkflow {
  name = "artifacts-paths-oci";
  
  jobs = {
    # Build job - creates nested directory structure
    build = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      
      # Save artifacts with nested paths
      outputs = {
        build-artifacts = "build/dist/";      # Directory with trailing slash
        release-binary = "target/release/myapp";  # File in nested directory
      };
      
      actions = [
        {
          name = "build";
          bash = ''
            echo "→ Building with nested structure in OCI"
            
            # Create nested directories
            mkdir -p target/release
            mkdir -p build/dist
            
            # Create files
            echo "#!/bin/bash" > target/release/myapp
            echo "echo 'Release binary from OCI'" >> target/release/myapp
            chmod +x target/release/myapp
            
            echo "artifact 1 from OCI" > build/dist/file1.txt
            echo "artifact 2 from OCI" > build/dist/file2.txt
            
            echo "✓ Build complete"
            find . -type f
          '';
        }
      ];
    };
    
    # Test job - verifies path preservation
    test = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      needs = ["build"];
      inputs = ["release-binary" "build-artifacts"];
      
      actions = [
        {
          name = "test";
          bash = ''
            echo "→ Testing restored paths in OCI"
            
            echo ""
            echo "Directory structure:"
            find . -type f -o -type d | sort
            
            echo ""
            echo "→ Checking target/release/myapp"
            if [ -f "target/release/myapp" ]; then
              echo "✓ target/release/myapp found"
              ./target/release/myapp
            else
              echo "✗ target/release/myapp NOT found"
              exit 1
            fi
            
            echo ""
            echo "→ Checking build/dist/"
            if [ -d "build/dist" ]; then
              echo "✓ build/dist/ found"
              ls -la build/dist/
              cat build/dist/file1.txt
              cat build/dist/file2.txt
            else
              echo "✗ build/dist/ NOT found"
              exit 1
            fi
            
            echo ""
            echo "✓ All paths restored correctly in OCI!"
          '';
        }
      ];
    };
  };
}
