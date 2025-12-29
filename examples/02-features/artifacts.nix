# Artifacts Examples - Complete Test Suite
#
# Demonstrates outputs/inputs API with various restore path scenarios:
# 1. Simple artifacts (default restore to root)
# 2. Custom restore paths
# 3. Mixed syntax (simple + custom)
#
# Usage:
#   nix run .#example-artifacts-local
#   nix run .#example-artifacts-oci-shared
#   nix run .#example-artifacts-oci-isolated

{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "artifacts-demo";
  
  jobs = {
    # Build job - creates multiple artifacts
    build = {
      inherit executor;
      
      steps = [
        {
          name = "build";
          bash = ''
            echo "→ Building application"
            
            # Create dist artifacts
            mkdir -p dist/frontend dist/backend
            echo "Frontend v1.0" > dist/frontend/index.html
            echo "Frontend App" > dist/frontend/app.js
            echo "Backend v1.0" > dist/backend/server.js
            echo "API Config" > dist/backend/config.json
            
            # Create binary
            echo "#!/bin/bash" > myapp
            echo "echo 'I am the binary'" >> myapp
            chmod +x myapp
            
            # Create release
            mkdir -p target/release
            echo "Release binary" > target/release/app
            
            echo "✓ Build complete"
          '';
        }
      ];
      
      # Declare what this job produces
      outputs = {
        frontend = "dist/frontend/";
        backend = "dist/backend/";
        binary = "myapp";
        release = "target/release/app";
      };
    };
    
    # Test 1: Default restore (backward compatibility)
    test-default = {
      inherit executor;
      needs = ["build"];
      
      # Simple strings - restore to root (default)
      inputs = ["frontend" "backend"];
      
      steps = [
        {
          name = "test-default";
          bash = ''
            echo "→ Test 1: Default restore paths"
            
            # Should be at: dist/frontend/ and dist/backend/
            if [ -f "dist/frontend/index.html" ]; then
              echo "✓ Frontend restored to default path"
            else
              echo "✗ Frontend not found"
              exit 1
            fi
            
            if [ -f "dist/backend/server.js" ]; then
              echo "✓ Backend restored to default path"
            else
              echo "✗ Backend not found"
              exit 1
            fi
            
            echo "✓ Test 1 passed"
          '';
        }
      ];
    };
    
    # Test 2: Custom restore paths
    test-custom = {
      inherit executor;
      needs = ["build"];
      
      # Custom paths - restore to specific directories
      inputs = [
        { name = "frontend"; path = "public/"; }
        { name = "backend"; path = "server/"; }
      ];
      
      steps = [
        {
          name = "test-custom";
          bash = ''
            echo "→ Test 2: Custom restore paths"
            
            # Should be at: public/dist/frontend/ and server/dist/backend/
            if [ -f "public/dist/frontend/index.html" ]; then
              echo "✓ Frontend restored to custom path (public/)"
            else
              echo "✗ Frontend not found at custom path"
              exit 1
            fi
            
            if [ -f "server/dist/backend/server.js" ]; then
              echo "✓ Backend restored to custom path (server/)"
            else
              echo "✗ Backend not found at custom path"
              exit 1
            fi
            
            echo "✓ Test 2 passed"
          '';
        }
      ];
    };
    
    # Test 3: Mixed syntax (simple + custom)
    test-mixed = {
      inherit executor;
      needs = ["build"];
      
      # Mix simple strings and custom paths
      inputs = [
        "binary"                              # Default: to root
        { name = "release"; path = "bin/"; }  # Custom: to bin/
      ];
      
      steps = [
        {
          name = "test-mixed";
          bash = ''
            echo "→ Test 3: Mixed syntax"
            
            # Binary should be at default location
            if [ -x "myapp" ]; then
              echo "✓ Binary at default location"
              ./myapp
            else
              echo "✗ Binary not found"
              exit 1
            fi
            
            # Release should be at custom location
            if [ -f "bin/target/release/app" ]; then
              echo "✓ Release at custom location (bin/)"
            else
              echo "✗ Release not found at custom location"
              exit 1
            fi
            
            echo "✓ Test 3 passed"
          '';
        }
      ];
    };
    
    # Final validation - use all artifacts
    validate = {
      inherit executor;
      needs = ["test-default" "test-custom" "test-mixed"];
      
      inputs = [
        "frontend"
        "backend"
        "binary"
        "release"
      ];
      
      steps = [
        {
          name = "validate";
          bash = ''
            echo "→ Final validation"
            echo ""
            echo "All artifacts present:"
            find . -type f | grep -v ".job-env" | sort
            echo ""
            echo "✓ All artifact tests passed successfully!"
          '';
        }
      ];
    };
  };
}
