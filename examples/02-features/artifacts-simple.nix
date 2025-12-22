# Simple Artifacts Example - declarative outputs/inputs API
{ pkgs, platform }:

platform.mkWorkflow {
  name = "artifacts-simple";
  
  jobs = {
    # Build job - creates artifacts
    build = {
      executor = platform.executors.local;
      
      # Declare what this job produces
      outputs = {
        dist = "dist/";
        myapp = "myapp";
      };
      
      actions = [
        {
          name = "build";
          bash = ''
            echo "→ Building application"
            
            # Create outputs
            mkdir -p dist
            echo "console.log('Hello from dist');" > dist/app.js
            echo "<html>App</html>" > dist/index.html
            
            echo "#!/bin/bash" > myapp
            echo "echo 'I am the binary'" >> myapp
            chmod +x myapp
            
            echo "✓ Build complete"
            ls -lh
          '';
        }
      ];
      # Artifacts saved automatically after job!
    };
    
    # Test job - uses artifacts from build
    test = {
      executor = platform.executors.local;
      needs = ["build"];
      
      # Declare what this job needs
      inputs = ["dist" "myapp"];
      
      actions = [
        {
          name = "test";
          bash = ''
            echo "→ Testing application"
            
            # Artifacts restored automatically before job!
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
            
            echo "✓ All tests passed"
          '';
        }
      ];
    };
  };
}
