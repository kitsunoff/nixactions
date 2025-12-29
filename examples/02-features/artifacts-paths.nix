# Artifacts with nested paths example
{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "artifacts-paths";
  
  jobs = {
    build = {
      inherit executor;
      
      outputs = {
        # Nested paths - should preserve structure
        release-binary = "target/release/myapp";
        build-artifacts = "build/dist/";
      };
      
      steps = [
        {
          name = "build";
          bash = ''
            echo "→ Building with nested structure"
            
            # Create nested directories
            mkdir -p target/release
            mkdir -p build/dist
            
            # Create files
            echo "#!/bin/bash" > target/release/myapp
            echo "echo 'Release binary'" >> target/release/myapp
            chmod +x target/release/myapp
            
            echo "artifact 1" > build/dist/file1.txt
            echo "artifact 2" > build/dist/file2.txt
            
            echo "✓ Build complete"
            find . -type f
          '';
        }
      ];
    };
    
    test = {
      inherit executor;
      needs = ["build"];
      
      inputs = ["release-binary" "build-artifacts"];
      
      steps = [
        {
          name = "test";
          bash = ''
            echo "→ Testing restored paths"
            
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
            echo "✓ All paths restored correctly!"
          '';
        }
      ];
    };
  };
}
