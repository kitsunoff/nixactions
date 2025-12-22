# Artifacts Example with OCI executor in BUILD mode
# Builds custom image with all actions included
{ pkgs, platform }:

platform.mkWorkflow {
  name = "artifacts-oci-build";
  
  jobs = {
    # Build job - creates artifacts in custom OCI image
    build = {
      executor = platform.executors.oci { 
        image = "alpine";  # Minimal base image
        mode = "build";     # Build custom image with actions
      };
      
      # Declare what this job produces
      outputs = {
        dist = "dist/";
        myapp = "myapp";
      };
      
      actions = [
        {
          name = "build";
          bash = ''
            echo "→ Building application in custom OCI image"
            
            # Create outputs
            mkdir -p dist
            echo "console.log('Hello from custom image');" > dist/app.js
            echo "<html>Custom Image App</html>" > dist/index.html
            
            echo "#!/bin/bash" > myapp
            echo "echo 'I am the binary from custom image'" >> myapp
            chmod +x myapp
            
            echo "✓ Build complete in custom image"
            ls -lh
          '';
        }
      ];
    };
    
    # Test job - uses artifacts from build (also in custom image)
    test = {
      executor = platform.executors.oci { 
        image = "alpine";
        mode = "build";
      };
      needs = ["build"];
      
      # Declare what this job needs
      inputs = ["dist" "myapp"];
      
      actions = [
        {
          name = "test";
          bash = ''
            echo "→ Testing application in custom OCI image"
            
            # Artifacts restored automatically
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
            
            echo "✓ All tests passed in custom image"
          '';
        }
      ];
    };
  };
}
