{ pkgs, platform, executor ? platform.executors.local }:

# Comprehensive test suite for action conditions
# Tests all condition types, bash expressions, and edge cases

platform.mkWorkflow {
  name = "test-conditions-comprehensive";
  
  jobs = {
    # Test 1: success() condition - default behavior
    test-success-condition = {
      inherit executor;
      
      actions = [
        {
          name = "first-succeeds";
          bash = ''
            echo "First action succeeds"
          '';
          # Implicit condition: success()
        }
        {
          name = "second-runs-on-success";
          bash = ''
            echo "Second action runs because first succeeded"
          '';
          condition = "success()";
        }
      ];
    };
    
    # Test 2: failure() condition - runs only after failure
    test-failure-condition = {
      inherit executor;
      needs = ["test-success-condition"];
      continueOnError = true;
      
      actions = [
        {
          name = "first-fails";
          bash = ''
            echo "First action fails"
            exit 1
          '';
        }
        {
          name = "skip-on-failure";
          bash = ''
            echo "This should be SKIPPED because first failed"
            exit 1  # Should not execute
          '';
          condition = "success()";
        }
        {
          name = "run-on-failure";
          bash = ''
            echo "This RUNS because first action failed"
          '';
          condition = "failure()";
        }
      ];
    };
    
    # Test 3: always() condition - runs regardless of previous failures
    test-always-condition = {
      inherit executor;
      needs = ["test-failure-condition"];
      continueOnError = true;
      
      actions = [
        {
          name = "first-fails";
          bash = ''
            echo "First action fails"
            exit 1
          '';
        }
        {
          name = "always-runs";
          bash = ''
            echo "This ALWAYS runs, even after failure"
          '';
          condition = "always()";
        }
        {
          name = "also-always-runs";
          bash = ''
            echo "This also ALWAYS runs"
          '';
          condition = "always()";
        }
      ];
    };
    
    # Test 4: Bash condition with environment variables
    test-bash-env-conditions = {
      inherit executor;
      needs = ["test-always-condition"];
      
      env = {
        DEPLOY_ENV = "production";
        ENABLE_FEATURE = "true";
        VERSION = "1.2.3";
      };
      
      actions = [
        {
          name = "check-production";
          bash = ''
            echo "Running in PRODUCTION (DEPLOY_ENV=$DEPLOY_ENV)"
          '';
          condition = ''[ "$DEPLOY_ENV" = "production" ]'';
        }
        {
          name = "skip-staging";
          bash = ''
            echo "This should be SKIPPED (not staging)"
            exit 1
          '';
          condition = ''[ "$DEPLOY_ENV" = "staging" ]'';
        }
        {
          name = "check-feature-enabled";
          bash = ''
            echo "Feature is ENABLED (ENABLE_FEATURE=$ENABLE_FEATURE)"
          '';
          condition = ''[ "$ENABLE_FEATURE" = "true" ]'';
        }
        {
          name = "skip-feature-disabled";
          bash = ''
            echo "This should be SKIPPED (feature not disabled)"
            exit 1
          '';
          condition = ''[ "$ENABLE_FEATURE" = "false" ]'';
        }
      ];
    };
    
    # Test 5: Complex bash conditions with operators
    test-complex-bash-conditions = {
      inherit executor;
      needs = ["test-bash-env-conditions"];
      
      env = {
        COUNT = "5";
        NAME = "test";
      };
      
      actions = [
        {
          name = "numeric-comparison-gt";
          bash = ''
            echo "COUNT is greater than 3 (COUNT=$COUNT)"
          '';
          condition = ''[ "$COUNT" -gt 3 ]'';
        }
        {
          name = "numeric-comparison-lt";
          bash = ''
            echo "This should be SKIPPED (COUNT not less than 3)"
            exit 1
          '';
          condition = ''[ "$COUNT" -lt 3 ]'';
        }
        {
          name = "string-pattern-match";
          bash = ''
            echo "NAME contains 'test' (NAME=$NAME)"
          '';
          condition = ''[[ "$NAME" == *test* ]]'';
        }
        {
          name = "file-exists-check";
          bash = ''
            echo "Job env file exists: $JOB_ENV"
          '';
          condition = ''[ -f "$JOB_ENV" ]'';
        }
      ];
    };
    
    # Test 6: Condition with AND/OR logic
    test-logical-conditions = {
      inherit executor;
      needs = ["test-complex-bash-conditions"];
      
      env = {
        ENV = "production";
        DEBUG = "false";
      };
      
      actions = [
        {
          name = "and-condition-true";
          bash = ''
            echo "Both conditions are TRUE (ENV=production AND DEBUG=false)"
          '';
          condition = ''[ "$ENV" = "production" ] && [ "$DEBUG" = "false" ]'';
        }
        {
          name = "and-condition-false";
          bash = ''
            echo "This should be SKIPPED (one condition is false)"
            exit 1
          '';
          condition = ''[ "$ENV" = "production" ] && [ "$DEBUG" = "true" ]'';
        }
        {
          name = "or-condition-true";
          bash = ''
            echo "At least one condition is TRUE (ENV=production OR DEBUG=true)"
          '';
          condition = ''[ "$ENV" = "production" ] || [ "$DEBUG" = "true" ]'';
        }
        {
          name = "or-condition-all-false";
          bash = ''
            echo "This should be SKIPPED (both conditions false)"
            exit 1
          '';
          condition = ''[ "$ENV" = "staging" ] || [ "$ENV" = "development" ]'';
        }
      ];
    };
    
    # Test 7: Condition with command substitution
    test-command-substitution-conditions = {
      inherit executor;
      needs = ["test-logical-conditions"];
      
      actions = [
        {
          name = "check-directory-not-empty";
          bash = ''
            echo "Current directory has files"
            ls -la
          '';
          condition = ''[ "$(ls -A . | wc -l)" -gt 0 ]'';
        }
        {
          name = "check-hostname";
          bash = ''
            echo "Hostname is set: $(hostname)"
          '';
          condition = ''[ -n "$(hostname)" ]'';
        }
      ];
    };
    
    # Test 8: Mixed conditions in sequence
    test-mixed-condition-sequence = {
      inherit executor;
      needs = ["test-command-substitution-conditions"];
      continueOnError = true;
      
      env = {
        STEP = "build";
      };
      
      actions = [
        {
          name = "step-1-build";
          bash = ''
            echo "Step 1: Build (STEP=$STEP)"
          '';
          condition = ''[ "$STEP" = "build" ]'';
        }
        {
          name = "step-2-test";
          bash = ''
            echo "Step 2: Test (runs after build)"
          '';
          condition = "success()";
        }
        {
          name = "step-3-deploy-skipped";
          bash = ''
            echo "This should be SKIPPED (STEP != deploy)"
            exit 1
          '';
          condition = ''[ "$STEP" = "deploy" ]'';
        }
        {
          name = "step-4-cleanup";
          bash = ''
            echo "Step 4: Cleanup (always runs)"
          '';
          condition = "always()";
        }
      ];
    };
    
    # Test 9: Empty/unset variable conditions
    test-empty-variable-conditions = {
      inherit executor;
      needs = ["test-mixed-condition-sequence"];
      
      env = {
        SET_VAR = "value";
        # UNSET_VAR not defined
        EMPTY_VAR = "";
      };
      
      actions = [
        {
          name = "check-var-set";
          bash = ''
            echo "SET_VAR is set: $SET_VAR"
          '';
          condition = ''[ -n "$SET_VAR" ]'';
        }
        {
          name = "check-var-empty";
          bash = ''
            echo "EMPTY_VAR is empty: '$EMPTY_VAR'"
          '';
          condition = ''[ -z "$EMPTY_VAR" ]'';
        }
        {
          name = "check-var-not-empty-skip";
          bash = ''
            echo "This should be SKIPPED (EMPTY_VAR is empty)"
            exit 1
          '';
          condition = ''[ -n "$EMPTY_VAR" ]'';
        }
      ];
    };
    
    # Test 10: Condition evaluation order
    test-condition-evaluation-order = {
      inherit executor;
      needs = ["test-empty-variable-conditions"];
      continueOnError = true;
      
      actions = [
        {
          name = "action-1-succeeds";
          bash = ''
            echo "Action 1: SUCCESS"
          '';
        }
        {
          name = "action-2-fails";
          bash = ''
            echo "Action 2: FAIL"
            exit 1
          '';
        }
        {
          name = "action-3-skipped-on-success";
          bash = ''
            echo "This should be SKIPPED (previous action failed)"
            exit 1
          '';
          condition = "success()";
        }
        {
          name = "action-4-runs-on-failure";
          bash = ''
            echo "Action 4: Runs because action 2 failed"
          '';
          condition = "failure()";
        }
        {
          name = "action-5-always";
          bash = ''
            echo "Action 5: Always runs regardless of failures"
          '';
          condition = "always()";
        }
      ];
    };
  };
}
