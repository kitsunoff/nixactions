# Complete workflow example - demonstrates all major features
{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "complete-ci-pipeline";
  
  # Workflow-level environment variables
  env = {
    PROJECT_NAME = "nixactions";
    BUILD_ENV = "ci";
  };
  
  jobs = {
    # === Level 0: Parallel initial checks ===
    
    lint = {
      inherit executor;
      
      # Job-level environment
      env = {
        LINT_MODE = "strict";
      };
      
      actions = [
        {
          name = "lint-nix";
          deps = [ pkgs.nixpkgs-fmt ];
          bash = ''
            echo "→ Linting Nix code in $LINT_MODE mode"
            echo "Project: $PROJECT_NAME"
            nixpkgs-fmt --check lib/ examples/ flake.nix || true
            echo "✓ Nix linting complete"
          '';
        }
      ];
    };
    
    security = {
      inherit executor;
      
      # This job can fail without stopping the workflow
      continueOnError = true;
      
      actions = [{
        name = "security-scan";
        bash = ''
          echo "→ Running security scan..."
          echo "Checking for common vulnerabilities..."
          
          # Simulate security scan
          if [ -f "secrets.txt" ]; then
            echo "⚠ Warning: Found unencrypted secrets file!"
            exit 1
          fi
          
          echo "✓ Security scan complete"
        '';
      }];
    };
    
    validate = {
      inherit executor;
      
      actions = [{
        name = "validate-structure";
        bash = ''
          echo "→ Validating project structure..."
          
          # Check required files exist
          for file in flake.nix lib/default.nix; do
            if [ ! -f "$file" ]; then
              echo "✗ Missing required file: $file"
              exit 1
            fi
            echo "✓ Found $file"
          done
          
          echo "✓ Project structure valid"
        '';
      }];
    };
    
    # === Level 1: Tests (after initial checks) ===
    
    test = {
      needs = [ "lint" "validate" ];
      inherit executor;
      
      actions = [
        {
          name = "run-tests";
          bash = ''
            echo "→ Running test suite..."
            echo "Environment: $BUILD_ENV"
            
            # Simulate tests
            echo "Testing core functionality..."
            sleep 1
            echo "✓ All tests passed (10/10)"
          '';
        }
      ];
    };
    
    # === Level 2: Build (after tests) ===
    
    build = {
      needs = [ "test" ];
      inherit executor;
      
      actions = [
        {
          name = "build-artifacts";
          deps = [ pkgs.coreutils pkgs.gnutar pkgs.gzip ];
          bash = ''
            echo "→ Building project: $PROJECT_NAME"
            
            # Create build directory
            mkdir -p build
            
            # Simulate build
            echo "Compiling sources..."
            sleep 1
            
            # Create artifact
            tar czf build/nixactions.tar.gz lib/ examples/ flake.nix
            
            echo "✓ Build complete"
            echo "Artifact: $(du -h build/nixactions.tar.gz | cut -f1)"
          '';
        }
      ];
    };
    
    # === Level 3: Deploy (only on success) ===
    
    deploy = {
      needs = [ "build" ];
      "if" = "success()";
      inherit executor;
      
      actions = [{
        name = "deploy-to-staging";
        bash = ''
          echo "→ Deploying to staging..."
          echo "This would deploy build/nixactions.tar.gz"
          echo "✓ Deployment complete"
        '';
      }];
    };
    
    # === Level 3: Notifications (parallel with deploy) ===
    
    notify-success = {
      needs = [ "build" ];
      "if" = "success()";
      inherit executor;
      
      actions = [{
        name = "notify-success";
        bash = ''
          echo "→ Sending success notification..."
          echo "✉ CI pipeline completed successfully!"
          echo "   Project: $PROJECT_NAME"
          echo "   All jobs passed"
        '';
      }];
    };
    
    notify-failure = {
      needs = [ "build" ];
      "if" = "failure()";
      inherit executor;
      
      actions = [{
        name = "notify-failure";
        bash = ''
          echo "→ Sending failure notification..."
          echo "✉ CI pipeline failed!"
          echo "   Project: $PROJECT_NAME"
          echo "   Check logs for details"
        '';
      }];
    };
    
    # === Level 4: Cleanup (always runs) ===
    
    cleanup = {
      needs = [ "deploy" "notify-success" "notify-failure" ];
      "if" = "always()";
      inherit executor;
      
      actions = [{
        name = "cleanup-resources";
        bash = ''
          echo "→ Cleaning up..."
          
          # Clean temporary files
          if [ -d "build" ]; then
            rm -rf build
            echo "✓ Removed build directory"
          fi
          
          echo "✓ Cleanup complete"
        '';
      }];
    };
  };
}
