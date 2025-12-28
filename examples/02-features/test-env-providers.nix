{ pkgs, platform, executor ? platform.executors.local }:

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

platform.mkWorkflow {
  name = "test-env-providers";
  
  # Environment providers executed in order
  envFrom = [
    # 1. Static provider - lowest priority
    (platform.envProviders.static {
      STATIC_VAR = "from_static";
      SHARED_VAR = "static_priority";
      CI = "true";
      NODE_ENV = "test";
    })
    
    # 2. File provider - higher priority than static
    (platform.envProviders.file {
      path = testEnvFile;
      required = false;
    })
    
    # 3. Required provider - validates vars are set
    (platform.envProviders.required [
      "STATIC_VAR"
      "FILE_VAR"
      "DB_HOST"
    ])
  ];
  
  # Workflow env - lowest priority of all
  env = {
    WORKFLOW_VAR = "from_workflow";
    SHARED_VAR = "workflow_priority";  # Will be overridden
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
            echo "Priority test (should be 'file_priority'):"
            echo "  SHARED_VAR = $SHARED_VAR"
            echo ""
            
            # Validate priority system works
            if [ "$SHARED_VAR" != "file_priority" ]; then
              echo "❌ Priority system broken! Expected 'file_priority', got '$SHARED_VAR'"
              exit 1
            fi
            
            echo "✓ Priority system working correctly"
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
    
    test-runtime-override = {
      needs = ["test-required"];
      inherit executor;
      
      # Job-level env has higher priority than workflow env
      env = {
        JOB_VAR = "from_job";
        SHARED_VAR = "should_be_file_priority";  # Providers already executed, won't override
      };
      
      actions = [
        {
          name = "test-job-env";
          bash = ''
            echo "Job-level variables:"
            echo "  JOB_VAR = $JOB_VAR"
            echo "  SHARED_VAR = $SHARED_VAR (should still be 'file_priority')"
            
            if [ "$SHARED_VAR" != "file_priority" ]; then
              echo "❌ Job env should not override providers!"
              exit 1
            fi
            
            echo "✓ Provider priority correctly enforced"
          '';
        }
      ];
    };
  };
}
