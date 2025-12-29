# Test SDK with Environment Providers
#
# This example tests SDK integration with envProviders:
# - static provider sets variables
# - SDK actions use fromEnv to access them
# - Workflow-level and job-level providers
#
# Run: nix build .#example-test-sdk-env-providers-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  sdk = nixactions.sdk;
  types = sdk.types;
  envProviders = nixactions.envProviders;

  # Action that uses environment variables from providers
  useConfig = sdk.mkAction {
    name = "use-config";
    inputs = {
      appName = types.string;
      appEnv = types.string;
      apiUrl = types.string;
    };
    run = ''
      echo "=== Application Configuration ==="
      echo "App Name: $INPUT_appName"
      echo "Environment: $INPUT_appEnv"
      echo "API URL: $INPUT_apiUrl"
      echo "================================="
    '';
  };

  # Action that verifies required env vars are present
  verifyEnv = sdk.mkAction {
    name = "verify-env";
    inputs = {
      varName = types.string;
      expectedValue = types.string;
      actualValue = types.string;
    };
    run = ''
      echo "Checking $INPUT_varName..."
      if [ "$INPUT_actualValue" = "$INPUT_expectedValue" ]; then
        echo "SUCCESS: $INPUT_varName = '$INPUT_actualValue'"
      else
        echo "FAILURE: Expected '$INPUT_expectedValue', got '$INPUT_actualValue'"
        exit 1
      fi
    '';
  };

  # Action that combines workflow and job-level env
  showAllEnv = sdk.mkAction {
    name = "show-all-env";
    inputs = {
      workflowVar = types.string;
      jobVar = types.string;
    };
    run = ''
      echo "Workflow-level: $INPUT_workflowVar"
      echo "Job-level: $INPUT_jobVar"
    '';
  };

in nixactions.mkWorkflow {
  name = "test-sdk-env-providers";
  
  extensions = [ sdk.validation ];
  
  # Workflow-level environment from provider
  envFrom = [
    (envProviders.static {
      WORKFLOW_VAR = "from-workflow";
      APP_NAME = "TestApp";
      APP_ENV = "development";
    })
  ];
  
  jobs = {
    # Test 1: SDK action using workflow-level env provider
    test-workflow-env = {
      inherit executor;
      steps = [
        (useConfig {
          appName = sdk.fromEnv "APP_NAME";
          appEnv = sdk.fromEnv "APP_ENV";
          apiUrl = "http://localhost:3000";  # literal value
        })
        
        (verifyEnv {
          varName = "APP_NAME";
          expectedValue = "TestApp";
          actualValue = sdk.fromEnv "APP_NAME";
        })
      ];
    };
    
    # Test 2: Job-level env provider overrides workflow-level
    test-job-env = {
      inherit executor;
      envFrom = [
        (envProviders.static {
          JOB_VAR = "from-job";
          APP_ENV = "production";  # Override workflow-level
        })
      ];
      steps = [
        (showAllEnv {
          workflowVar = sdk.fromEnv "WORKFLOW_VAR";
          jobVar = sdk.fromEnv "JOB_VAR";
        })
        
        # Verify override worked
        (verifyEnv {
          varName = "APP_ENV";
          expectedValue = "production";  # Should be overridden
          actualValue = sdk.fromEnv "APP_ENV";
        })
      ];
    };
    
    # Test 3: Static env + provider combined
    test-combined = {
      inherit executor;
      env = {
        STATIC_VAR = "from-static";
      };
      envFrom = [
        (envProviders.static {
          PROVIDER_VAR = "from-provider";
        })
      ];
      steps = [
        {
          name = "check-both";
          bash = ''
            echo "Static: $STATIC_VAR"
            echo "Provider: $PROVIDER_VAR"
            echo "Workflow: $WORKFLOW_VAR"
            
            if [ "$STATIC_VAR" = "from-static" ] && \
               [ "$PROVIDER_VAR" = "from-provider" ] && \
               [ "$WORKFLOW_VAR" = "from-workflow" ]; then
              echo "SUCCESS: All environment sources work together"
            else
              echo "FAILURE: Some env vars missing"
              exit 1
            fi
          '';
        }
        
        # SDK action using all sources
        (sdk.mkAction {
          name = "use-all-sources";
          inputs = {
            static = types.string;
            provider = types.string;
            workflow = types.string;
          };
          run = ''
            echo "All sources received:"
            echo "  Static: $INPUT_static"
            echo "  Provider: $INPUT_provider"
            echo "  Workflow: $INPUT_workflow"
          '';
        } {
          static = sdk.fromEnv "STATIC_VAR";
          provider = sdk.fromEnv "PROVIDER_VAR";
          workflow = sdk.fromEnv "WORKFLOW_VAR";
        })
      ];
    };
  };
}
