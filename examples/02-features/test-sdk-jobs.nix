# Test SDK with Multi-Job Workflows
#
# This example tests SDK in multi-job scenarios:
# - Job dependencies with needs
# - Passing data between jobs via artifacts
# - SDK actions producing artifacts
#
# Note: Cross-job data passing uses artifacts (files), not environment variables.
#       Use outputs/inputs for file-based data, not jobOutput refs.
#
# Run: nix build .#example-test-sdk-jobs-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  sdk = nixactions.sdk;
  types = sdk.types;

  # === Actions for multi-job workflow ===

  # Build action - produces build info
  buildApp = sdk.mkAction {
    name = "build-app";
    inputs = {
      version = types.string;
      config = types.withDefault types.string "default";
    };
    outputs = {
      buildId = types.string;
    };
    run = ''
      BUILD_ID="build-$INPUT_version-$(date +%s)"
      OUTPUT_buildId="$BUILD_ID"
      
      echo "Building app version $INPUT_version with config $INPUT_config"
      echo "Build ID: $OUTPUT_buildId"
      
      # Create build artifact
      mkdir -p dist
      echo "{ \"version\": \"$INPUT_version\", \"buildId\": \"$BUILD_ID\", \"config\": \"$INPUT_config\" }" > dist/build-info.json
      echo "Build complete" > dist/app.bin
    '';
  };

  # Test action - runs tests
  runTests = sdk.mkAction {
    name = "run-tests";
    inputs = {
      testSuite = types.withDefault types.string "all";
    };
    outputs = {
      passed = types.string;
      total = types.string;
    };
    run = ''
      echo "Running test suite: $INPUT_testSuite"
      
      # Simulate test results
      OUTPUT_passed="42"
      OUTPUT_total="42"
      
      echo "Tests passed: $OUTPUT_passed/$OUTPUT_total"
      
      # Create test report artifact
      mkdir -p reports
      echo "Test Suite: $INPUT_testSuite" > reports/test-results.txt
      echo "Passed: $OUTPUT_passed" >> reports/test-results.txt
      echo "Total: $OUTPUT_total" >> reports/test-results.txt
    '';
  };

  # Deploy action - deploys using artifacts from previous jobs
  deployApp = sdk.mkAction {
    name = "deploy-app";
    inputs = {
      environment = types.enum [ "staging" "production" ];
    };
    run = ''
      echo "Deploying to $INPUT_environment"
      
      # Check build artifact exists (from build job via inputs)
      if [ -f "dist/build-info.json" ]; then
        echo "Found build info:"
        cat dist/build-info.json
      else
        echo "ERROR: Build artifact not found!"
        exit 1
      fi
      
      # Check test results exist (from test job via inputs)
      if [ -f "reports/test-results.txt" ]; then
        echo "Found test results:"
        cat reports/test-results.txt
      else
        echo "ERROR: Test results not found!"
        exit 1
      fi
      
      echo "Deployment to $INPUT_environment complete!"
    '';
  };

  # Summary action - uses step outputs within same job
  showSummary = sdk.mkAction {
    name = "show-summary";
    inputs = {
      buildId = types.string;
      testsPassed = types.string;
      testsTotal = types.string;
    };
    run = ''
      echo "========== BUILD SUMMARY =========="
      echo "Build ID: $INPUT_buildId"
      echo "Tests: $INPUT_testsPassed / $INPUT_testsTotal"
      echo "==================================="
    '';
  };

in nixactions.mkWorkflow {
  name = "test-sdk-jobs";
  
  extensions = [ sdk.validation ];
  
  jobs = {
    # Job 1: Build
    build = {
      inherit executor;
      steps = [
        (buildApp { version = "1.0.0"; config = "release"; })
      ];
      # Export artifacts for downstream jobs
      outputs = {
        dist = "dist/";
      };
    };
    
    # Job 2: Test (depends on build)
    test = {
      inherit executor;
      needs = [ "build" ];
      # Import build artifacts
      inputs = [ "dist" ];
      steps = [
        # Verify build artifact is available
        {
          name = "verify-build";
          bash = ''
            if [ -f "dist/build-info.json" ]; then
              echo "Build artifact found:"
              cat dist/build-info.json
            else
              echo "ERROR: Build artifact missing!"
              exit 1
            fi
          '';
        }
        (runTests { testSuite = "integration"; })
      ];
      outputs = {
        reports = "reports/";
      };
    };
    
    # Job 3: Deploy to staging (depends on test)
    deploy-staging = {
      inherit executor;
      needs = [ "test" ];
      inputs = [ "dist" "reports" ];
      steps = [
        (deployApp { environment = "staging"; })
      ];
    };
    
    # Job 4: Deploy to production (depends on staging)
    deploy-production = {
      inherit executor;
      needs = [ "deploy-staging" ];
      inputs = [ "dist" "reports" ];
      steps = [
        (deployApp { environment = "production"; })
      ];
    };
    
    # Job 5: Single job with step output chaining
    single-job-chain = {
      inherit executor;
      steps = [
        (buildApp { version = "2.0.0"; })
        (runTests {})
        # Use step outputs within same job
        (showSummary {
          buildId = sdk.stepOutput "build-app" "buildId";
          testsPassed = sdk.stepOutput "run-tests" "passed";
          testsTotal = sdk.stepOutput "run-tests" "total";
        })
      ];
    };
  };
}
