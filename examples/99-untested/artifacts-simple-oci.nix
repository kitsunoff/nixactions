# Simple Artifacts Example with OCI executor
{ pkgs, platform }:

platform.mkWorkflow {
  name = "artifacts-simple-oci";
  
  jobs = {
    # Build job - creates artifacts in OCI container
    build = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      
      # Declare what this job produces
      outputs = {
        dist = "dist/";
        myapp = "myapp";
      };
      
      actions = [
        {
          name = "build";
          bash = ''
            echo "→ Building application in OCI container"
            
            # Create outputs
            mkdir -p dist
            echo "console.log('Hello from OCI container');" > dist/app.js
            echo "<html>OCI App</html>" > dist/index.html
            
            echo "#!/bin/bash" > myapp
            echo "echo 'I am the binary from OCI'" >> myapp
            chmod +x myapp
            
            echo "✓ Build complete"
            ls -lh
          '';
        }
      ];
      # Artifacts saved automatically via docker cp after job!
    };
    
    # Test job - uses artifacts from build (also in OCI)
    test = {
      executor = platform.executors.oci { image = "nixos/nix"; };
      needs = ["build"];
      
      # Declare what this job needs
      inputs = ["dist" "myapp"];
      
      actions = [
        {
          name = "test";
          bash = ''
            echo "→ Testing application in OCI container"
            
            # Artifacts restored automatically via docker cp before job!
            echo "Files available:"
            ls -lh
            
            # Verify dist exists
            if [ -d "dist" ]; then
              echo "✓ dist/ found"
              ls -lh dist/
            else
              echo "✗ dist/ not found"
              exit 1
            fi
            
            # Verify binary exists
            if [ -f "myapp" ]; then
              echo "✓ myapp found"
              ./myapp
            else
              echo "✗ myapp not found"
              exit 1
            fi
            
            echo "✓ All tests passed in OCI"
          '';
        }
      ];
    };
  };
}
