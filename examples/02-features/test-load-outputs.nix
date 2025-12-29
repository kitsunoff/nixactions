# Test loadOutputs - Cross-job data passing via JSON
#
# This example demonstrates:
# - Saving structured outputs as JSON in one job
# - Loading and validating outputs in another job
# - Type checking at runtime
#
# Run: nix build .#example-test-load-outputs-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  types = nixactions.sdk.types;
  
  # Define schema for build outputs
  loadBuildOutputs = nixactions.actions.loadOutputs {
    file = ".build-outputs.json";
    schema = {
      buildId = types.string;
      version = types.string;
      exitCode = types.int;
      success = types.bool;
    };
  };

in nixactions.mkWorkflow {
  name = "test-load-outputs";
  
  jobs = {
    # Producer job - creates JSON output
    build = {
      inherit executor;
      steps = [
        {
          name = "build-app";
          bash = ''
            echo "Building application..."
            
            # Simulate build process
            BUILD_ID="build-$(date +%s)"
            VERSION="1.2.3"
            EXIT_CODE=0
            SUCCESS=true
            
            # Save as JSON
            cat > .build-outputs.json << EOF
            {
              "buildId": "$BUILD_ID",
              "version": "$VERSION",
              "exitCode": $EXIT_CODE,
              "success": $SUCCESS
            }
            EOF
            
            echo "Build outputs saved:"
            cat .build-outputs.json
          '';
        }
      ];
      outputs = {
        buildOutputs = ".build-outputs.json";
      };
    };
    
    # Consumer job - loads and uses outputs
    test = {
      inherit executor;
      needs = [ "build" ];
      inputs = [ "buildOutputs" ];
      steps = [
        # Load outputs - exports buildId, version, exitCode, success
        (loadBuildOutputs {})
        
        # Use the loaded outputs
        # Variables come from loadBuildOutputs step via JOB_ENV
        {
          name = "verify-outputs";
          shellcheck = false;
          bash = ''
            echo "=== Verifying Build Outputs ==="
            echo "Build ID: $buildId"
            echo "Version: $version"
            echo "Exit Code: $exitCode"
            echo "Success: $success"
            
            # Verify values
            if [ -z "$buildId" ]; then
              echo "ERROR: buildId is empty!" >&2
              exit 1
            fi
            
            if [ "$version" != "1.2.3" ]; then
              echo "ERROR: version mismatch! Expected 1.2.3, got $version" >&2
              exit 1
            fi
            
            if [ "$exitCode" != "0" ]; then
              echo "ERROR: exitCode should be 0, got $exitCode" >&2
              exit 1
            fi
            
            if [ "$success" != "true" ]; then
              echo "ERROR: success should be true, got $success" >&2
              exit 1
            fi
            
            echo "=== All outputs verified! ==="
          '';
        }
      ];
    };
    
    # Another consumer - demonstrates reuse
    deploy = {
      inherit executor;
      needs = [ "build" "test" ];
      inputs = [ "buildOutputs" ];
      steps = [
        (loadBuildOutputs {})
        {
          name = "deploy";
          shellcheck = false;
          bash = ''
            echo "Deploying version $version (build: $buildId)"
            if [ "$success" = "true" ]; then
              echo "Deployment successful!"
            else
              echo "Skipping deployment - build was not successful"
              exit 1
            fi
          '';
        }
      ];
    };
  };
}
