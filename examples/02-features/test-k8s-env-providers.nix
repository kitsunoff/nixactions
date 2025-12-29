# Kubernetes Executor - Environment Providers Test
# 
# This example tests that envFrom providers work correctly in K8s pods.
# 
# Prerequisites:
# 1. Kubernetes cluster accessible via kubectl
# 2. Container registry with push access
# 3. Environment variables set:
#    - REGISTRY_USER: Registry username
#    - REGISTRY_PASSWORD: Registry password/token
#
# Usage:
#   ./scripts/test-k8s-kind.sh env-providers
#
#   # Or manually:
#   REGISTRY_USER=unused REGISTRY_PASSWORD=unused nix run .#example-test-k8s-env-providers-dedicated

{ pkgs
, nixactions
, executor  # K8s executor must be provided (requires registry config)
}:

let
  # Create a test .env file that will be baked into the image
  testEnvFile = pkgs.writeText "test.env" ''
    FILE_VAR=from_file
    SHARED_VAR=file_priority
    DB_HOST=k8s-db.default.svc
    DB_PORT=5432
  '';
in

nixactions.mkWorkflow {
  name = "k8s-env-providers-test";
  
  # Environment providers executed in order
  envFrom = [
    # 1. Static provider - lowest priority
    (nixactions.envProviders.static {
      STATIC_VAR = "from_static";
      SHARED_VAR = "static_priority";
      CI = "true";
      K8S_ENV = "test";
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
  env = {
    WORKFLOW_VAR = "from_workflow";
    # NOTE: SHARED_VAR not set here to test provider priority
  };
  
  jobs = {
    test-env-in-pod = {
      inherit executor;
      
      actions = [
        {
          name = "show-environment";
          bash = ''
            echo "=== Environment Variables in K8s Pod ==="
            echo ""
            echo "Pod info:"
            echo "  Hostname: $(hostname)"
            echo ""
            echo "Static provider:"
            echo "  STATIC_VAR = $STATIC_VAR"
            echo "  CI = $CI"
            echo "  K8S_ENV = $K8S_ENV"
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
          '';
        }
        {
          name = "validate-static";
          bash = ''
            echo "Validating static provider..."
            
            if [ "$STATIC_VAR" != "from_static" ]; then
              echo "FAIL: STATIC_VAR expected 'from_static', got '$STATIC_VAR'"
              exit 1
            fi
            
            if [ "$CI" != "true" ]; then
              echo "FAIL: CI expected 'true', got '$CI'"
              exit 1
            fi
            
            if [ "$K8S_ENV" != "test" ]; then
              echo "FAIL: K8S_ENV expected 'test', got '$K8S_ENV'"
              exit 1
            fi
            
            echo "PASS: Static provider variables correct"
          '';
        }
        {
          name = "validate-file";
          bash = ''
            echo "Validating file provider..."
            
            if [ "$FILE_VAR" != "from_file" ]; then
              echo "FAIL: FILE_VAR expected 'from_file', got '$FILE_VAR'"
              exit 1
            fi
            
            if [ "$DB_HOST" != "k8s-db.default.svc" ]; then
              echo "FAIL: DB_HOST expected 'k8s-db.default.svc', got '$DB_HOST'"
              exit 1
            fi
            
            if [ "$DB_PORT" != "5432" ]; then
              echo "FAIL: DB_PORT expected '5432', got '$DB_PORT'"
              exit 1
            fi
            
            echo "PASS: File provider variables correct"
          '';
        }
        {
          name = "validate-priority";
          bash = ''
            echo "Validating priority system..."
            
            # File provider should override static provider
            if [ "$SHARED_VAR" != "file_priority" ]; then
              echo "FAIL: SHARED_VAR expected 'file_priority', got '$SHARED_VAR'"
              echo "Priority system broken!"
              exit 1
            fi
            
            echo "PASS: Priority system working correctly"
          '';
        }
        {
          name = "validate-workflow-env";
          bash = ''
            echo "Validating workflow env..."
            
            if [ "$WORKFLOW_VAR" != "from_workflow" ]; then
              echo "FAIL: WORKFLOW_VAR expected 'from_workflow', got '$WORKFLOW_VAR'"
              exit 1
            fi
            
            echo "PASS: Workflow environment variables correct"
          '';
        }
      ];
    };
    
    test-job-env = {
      inherit executor;
      needs = [ "test-env-in-pod" ];
      
      # Job-level env
      env = {
        JOB_VAR = "from_job";
        JOB_SPECIFIC = "only_in_this_job";
      };
      
      actions = [
        {
          name = "validate-job-env";
          bash = ''
            echo "Validating job-level environment..."
            
            if [ "$JOB_VAR" != "from_job" ]; then
              echo "FAIL: JOB_VAR expected 'from_job', got '$JOB_VAR'"
              exit 1
            fi
            
            if [ "$JOB_SPECIFIC" != "only_in_this_job" ]; then
              echo "FAIL: JOB_SPECIFIC expected 'only_in_this_job', got '$JOB_SPECIFIC'"
              exit 1
            fi
            
            # Workflow-level vars should still be available
            if [ "$WORKFLOW_VAR" != "from_workflow" ]; then
              echo "FAIL: WORKFLOW_VAR should be inherited, got '$WORKFLOW_VAR'"
              exit 1
            fi
            
            # Provider vars should still be available
            if [ "$STATIC_VAR" != "from_static" ]; then
              echo "FAIL: STATIC_VAR should be inherited from provider, got '$STATIC_VAR'"
              exit 1
            fi
            
            echo "PASS: Job environment correctly inherits and extends"
          '';
        }
      ];
    };
    
    summary = {
      inherit executor;
      needs = [ "test-job-env" ];
      
      actions = [
        {
          name = "final-summary";
          bash = ''
            echo ""
            echo "=========================================="
            echo "  K8s Environment Providers Test Summary"
            echo "=========================================="
            echo ""
            echo "All tests passed:"
            echo "  - Static provider variables"
            echo "  - File provider variables"
            echo "  - Priority system (file > static)"
            echo "  - Workflow-level environment"
            echo "  - Job-level environment inheritance"
            echo ""
            echo "Environment providers work correctly in K8s!"
            echo ""
          '';
        }
      ];
    };
  };
}
