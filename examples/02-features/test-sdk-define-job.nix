# Test SDK defineJob - Typed Job Definitions
#
# This example tests:
# - defineJob with typed inputs
# - envOutputs for passing data between jobs
# - jobOutput refs
# - envOutputsExtension
#
# Run: nix build .#example-test-sdk-define-job-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  sdk = nixactions.sdk;
  types = sdk.types;

  # === Typed Actions ===

  buildApp = sdk.defineAction {
    name = "build-app";
    inputs = {
      version = types.string;
      config = types.withDefault types.string "release";
    };
    run = ''
      echo "Building version $INPUT_version with config $INPUT_config"
      
      # Create build output
      mkdir -p dist
      echo "App v$INPUT_version ($INPUT_config)" > dist/app.txt
      
      # Set outputs for job
      OUTPUT_buildId="build-$INPUT_version-$(date +%s)"
      OUTPUT_artifact="dist/app.txt"
      
      echo "Build ID: $OUTPUT_buildId"
    '';
  };

  runTests = sdk.defineAction {
    name = "run-tests";
    inputs = {
      buildId = types.string;
    };
    run = ''
      echo "Running tests for build: $INPUT_buildId"
      
      # Simulate tests
      OUTPUT_testsPassed="42"
      OUTPUT_testsTotal="42"
      
      echo "Tests: $OUTPUT_testsPassed / $OUTPUT_testsTotal passed"
    '';
  };

  deployApp = sdk.defineAction {
    name = "deploy-app";
    inputs = {
      buildId = types.string;
      environment = types.enum [ "staging" "production" ];
    };
    run = ''
      echo "Deploying build $INPUT_buildId to $INPUT_environment"
      
      # Check artifact exists
      if [ -f "dist/app.txt" ]; then
        echo "Artifact content:"
        cat dist/app.txt
      else
        echo "ERROR: Artifact not found!"
        exit 1
      fi
      
      echo "Deployment complete!"
    '';
  };

  # === Typed Jobs ===

  buildJob = sdk.defineJob {
    name = "build";
    
    # Typed inputs
    inputs = {
      version = types.string;
      config = types.withDefault types.string "release";
    };
    
    # Env outputs - will be available to downstream jobs
    envOutputs = [ "buildId" ];
    
    # File artifacts
    artifacts = {
      dist = "dist/";
    };
    
    steps = ctx: [
      (buildApp { 
        version = ctx.inputs.version;
        config = ctx.inputs.config;
      })
    ];
  };

  testJob = sdk.defineJob {
    name = "test";
    
    # This job needs build's envOutputs
    needs = [ "build" ];
    artifactInputs = [ "dist" ];
    
    # Pass through env outputs
    envOutputs = [ "testsPassed" "testsTotal" ];
    
    steps = ctx: [
      # buildId comes from build job via jobOutput
      (runTests { 
        buildId = sdk.jobOutput "build" "buildId";
      })
    ];
  };

  deployJob = sdk.defineJob {
    name = "deploy";
    
    inputs = {
      environment = types.enum [ "staging" "production" ];
    };
    
    needs = [ "test" ];
    artifactInputs = [ "dist" ];
    
    steps = ctx: [
      (deployApp {
        buildId = sdk.jobOutput "build" "buildId";
        environment = ctx.inputs.environment;
      })
    ];
  };

in nixactions.mkWorkflow {
  name = "test-sdk-define-job";
  
  # Enable SDK extensions
  extensions = [ 
    sdk.validation 
    sdk.envOutputsExtension 
  ];
  
  jobs = {
    # Build job - produces envOutputs and artifacts
    build = buildJob { 
      version = "2.0.0"; 
      config = "production";
      executor = executor;
    };
    
    # Test job - consumes build's envOutputs
    test = testJob { 
      executor = executor;
    };
    
    # Deploy to staging
    deploy-staging = deployJob { 
      environment = "staging";
      executor = executor;
    };
    
    # Deploy to production (after staging)
    deploy-production = deployJob { 
      environment = "production";
      executor = executor;
      needs = [ "deploy-staging" ];  # Additional dependency
    };
  };
}
