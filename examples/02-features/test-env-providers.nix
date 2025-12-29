{ pkgs, nixactions, executor ? nixactions.executors.local }:

# Test: Environment Providers
# 
# This example demonstrates the envFrom provider system:
# - Static provider (hardcoded values)
# - File provider (load from .env file)
# - Required provider (validate required vars)
# - Priority system (runtime > file > static)

let
  # Create a test .env file
  testEnvFile = pkgs.writeText "test.env" ''
    FILE_VAR=from_file
    SHARED_VAR=file_priority
    DB_HOST=localhost
    DB_PORT=5432
  '';
in

nixactions.mkWorkflow {
  name = "test-env-providers";
  
  # Environment providers executed in order
  envFrom = [
    # 1. Static provider - lowest priority
    (nixactions.envProviders.static {
      STATIC_VAR = "from_static";
      SHARED_VAR = "static_priority";
      CI = "true";
      NODE_ENV = "test";
    })
    
    # 2. File provider - higher priority than static
    (nixactions.envProviders.file {
      path = testEnvFile;
      required = false;
    })
    
    # 3. Required provider - validates vars are set
    (nixactions.envProviders.required [
      "STATIC_VAR"
      "FILE_VAR"
      "DB_HOST"
    ])
  ];
  
  # Workflow env - higher priority than workflow envFrom (providers)
  # But lower priority than job env/envFrom
  env = {
    WORKFLOW_VAR = "from_workflow";
    # NOTE: SHARED_VAR intentionally NOT set here to test provider priority
  };
  
  jobs = {
    test-priority = {
      inherit executor;
      
      actions = [
        {
          name = "show-environment";
          bash = ''
            echo "=== Environment Variables ==="
            echo ""
            echo "Static provider:"
            echo "  STATIC_VAR = $STATIC_VAR"
            echo "  CI = $CI"
            echo "  NODE_ENV = $NODE_ENV"
            echo ""
            echo "File provider:"
            echo "  FILE_VAR = $FILE_VAR"
            echo "  DB_HOST = $DB_HOST"
            echo "  DB_PORT = $DB_PORT"
            echo ""
            echo "Workflow env:"
            echo "  WORKFLOW_VAR = $WORKFLOW_VAR"
            echo ""
            echo "Priority test (file provider overrides static provider):"
            echo "  SHARED_VAR = $SHARED_VAR"
            echo ""
            
            # Validate priority system works
            # File provider is executed after static provider, so it overrides
            if [ "$SHARED_VAR" != "file_priority" ]; then
              echo "FAIL: Expected 'file_priority' (file provider), got '$SHARED_VAR'"
              exit 1
            fi
            
            echo "PASS: Provider order priority working correctly"
          '';
        }
      ];
    };
    
    test-required = {
      needs = ["test-priority"];
      inherit executor;
      
      actions = [
        {
          name = "test-required-validation";
          bash = ''
            echo "Testing required provider validation..."
            
            # These should all be set
            : "''${STATIC_VAR:?STATIC_VAR is required}"
            : "''${FILE_VAR:?FILE_VAR is required}"
            : "''${DB_HOST:?DB_HOST is required}"
            
            echo "✓ All required variables present"
          '';
        }
      ];
    };
    
    test-job-env-override = {
      needs = ["test-required"];
      inherit executor;
      
      # Job-level env has higher priority than workflow envFrom (providers)
      # Per docs: Job env (5) > Job envFrom (6) > Workflow env (7) > Workflow envFrom (8)
      env = {
        JOB_VAR = "from_job";
        SHARED_VAR = "job_override";  # This SHOULD override provider value
      };
      
      actions = [
        {
          name = "test-job-env";
          bash = ''
            echo "Job-level variables:"
            echo "  JOB_VAR = $JOB_VAR"
            echo "  SHARED_VAR = $SHARED_VAR (should be 'job_override')"
            
            if [ "$JOB_VAR" != "from_job" ]; then
              echo "FAIL: JOB_VAR expected 'from_job', got '$JOB_VAR'"
              exit 1
            fi
            
            # Job env has higher priority than workflow providers
            if [ "$SHARED_VAR" != "job_override" ]; then
              echo "FAIL: Job env should override providers! Expected 'job_override', got '$SHARED_VAR'"
              exit 1
            fi
            
            echo "PASS: Job env correctly overrides providers"
          '';
        }
      ];
    };
  };
}
