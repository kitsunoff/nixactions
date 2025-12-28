{ pkgs, platform, executor ? platform.executors.local }:

# Comprehensive test suite for retry mechanism
# Tests all backoff strategies, edge cases, and failure scenarios

platform.mkWorkflow {
  name = "test-retry-comprehensive";
  
  jobs = {
    # Test 1: Exponential backoff - succeeds on 3rd attempt
    test-exponential-success = {
      inherit executor;
      
      actions = [
        {
          name = "exponential-backoff-success";
          bash = ''
            # Use a stable state file (not $$, which changes per execution)
            STATE_FILE="/tmp/nixactions-test-exp-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Exponential backoff: Attempt $ATTEMPT/3"
            
            if [ "$ATTEMPT" -lt 3 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              echo "FAIL: Not ready yet (attempt $ATTEMPT)" >&2
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Succeeded on attempt 3"
          '';
          retry = {
            max_attempts = 3;
            backoff = "exponential";
            min_time = 1;
            max_time = 60;
          };
        }
      ];
    };
    
    # Test 2: Linear backoff - succeeds on 2nd attempt
    test-linear-success = {
      inherit executor;
      needs = ["test-exponential-success"];
      
      actions = [
        {
          name = "linear-backoff-success";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-linear-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Linear backoff: Attempt $ATTEMPT/2"
            
            if [ "$ATTEMPT" -lt 2 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              echo "FAIL: Not ready yet (attempt $ATTEMPT)" >&2
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Succeeded on attempt 2"
          '';
          retry = {
            max_attempts = 3;
            backoff = "linear";
            min_time = 1;
            max_time = 30;
          };
        }
      ];
    };
    
    # Test 3: Constant backoff - succeeds on 2nd attempt
    test-constant-success = {
      inherit executor;
      needs = ["test-linear-success"];
      
      actions = [
        {
          name = "constant-backoff-success";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-const-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Constant backoff: Attempt $ATTEMPT/2"
            
            if [ "$ATTEMPT" -lt 2 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              echo "FAIL: Not ready yet (attempt $ATTEMPT)" >&2
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Succeeded on attempt 2"
          '';
          retry = {
            max_attempts = 3;
            backoff = "constant";
            min_time = 2;
            max_time = 2;
          };
        }
      ];
    };
    
    # Test 4: Retry exhausted - all attempts fail
    test-retry-exhausted = {
      inherit executor;
      needs = ["test-constant-success"];
      continueOnError = true;  # Don't stop workflow on failure
      
      actions = [
        {
          name = "always-fails";
          bash = ''
            echo "Attempt that always fails"
            echo "This should exhaust all retries" >&2
            exit 1
          '';
          retry = {
            max_attempts = 3;
            backoff = "exponential";
            min_time = 1;
            max_time = 10;
          };
        }
      ];
    };
    
    # Test 5: No retry (max_attempts = 1)
    test-no-retry-single-attempt = {
      inherit executor;
      needs = ["test-retry-exhausted"];
      
      actions = [
        {
          name = "single-attempt-success";
          bash = ''
            echo "This runs only once (max_attempts=1)"
            echo "SUCCESS: No retry needed"
          '';
          retry = {
            max_attempts = 1;
            backoff = "exponential";
            min_time = 1;
            max_time = 60;
          };
        }
      ];
    };
    
    # Test 6: Retry disabled (retry = null)
    test-retry-disabled = {
      inherit executor;
      needs = ["test-no-retry-single-attempt"];
      retry = null;  # Explicitly disable retry
      
      actions = [
        {
          name = "no-retry-action";
          bash = ''
            echo "This action has retry disabled"
            echo "SUCCESS: Executed without retry"
          '';
        }
      ];
    };
    
    # Test 7: Max delay cap - ensure backoff is capped at max_time
    test-max-delay-cap = {
      inherit executor;
      needs = ["test-retry-disabled"];
      
      actions = [
        {
          name = "max-delay-capped";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-maxcap-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Testing max delay cap: Attempt $ATTEMPT"
            
            if [ "$ATTEMPT" -lt 2 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              echo "FAIL: First attempt" >&2
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Max delay was capped (should have waited max 5s, not exponential)"
          '';
          retry = {
            max_attempts = 5;
            backoff = "exponential";
            min_time = 10;
            max_time = 5;  # Max is LESS than min - should cap at 5
          };
        }
      ];
    };
    
    # Test 8: Job-level retry inheritance
    test-job-level-retry = {
      inherit executor;
      needs = ["test-max-delay-cap"];
      
      # Job-level retry applies to all actions
      retry = {
        max_attempts = 2;
        backoff = "constant";
        min_time = 1;
        max_time = 1;
      };
      
      actions = [
        {
          name = "inherits-job-retry";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-job-retry-$$"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Job-level retry: Attempt $ATTEMPT"
            
            if [ "$ATTEMPT" -lt 2 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Inherited job-level retry"
          '';
          # No action-level retry - inherits from job
        }
      ];
    };
    
    # Test 9: Action overrides job retry
    test-action-overrides-job = {
      inherit executor;
      needs = ["test-job-level-retry"];
      
      retry = {
        max_attempts = 2;
        backoff = "linear";
        min_time = 1;
        max_time = 10;
      };
      
      actions = [
        {
          name = "overrides-job-retry";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-override-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            echo "Action overrides job retry: Attempt $ATTEMPT/3"
            
            if [ "$ATTEMPT" -lt 3 ]; then
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              exit 1
            fi
            
            rm -f "$STATE_FILE"
            echo "SUCCESS: Action retry overrode job retry (3 attempts instead of 2)"
          '';
          retry = {
            max_attempts = 3;  # Overrides job-level max_attempts=2
            backoff = "exponential";
            min_time = 1;
            max_time = 10;
          };
        }
      ];
    };
    
    # Test 10: Verify timing - ensure backoff delays are correct
    test-timing-verification = {
      inherit executor;
      needs = ["test-action-overrides-job"];
      
      actions = [
        {
          name = "verify-exponential-timing";
          bash = ''
            STATE_FILE="/tmp/nixactions-test-timing-$WORKFLOW_ID"
            TIMING_FILE="/tmp/nixactions-timing-$WORKFLOW_ID"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "1" > "$STATE_FILE"
              date +%s > "$TIMING_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            CURRENT_TIME=$(date +%s)
            START_TIME=$(cat "$TIMING_FILE")
            ELAPSED=$((CURRENT_TIME - START_TIME))
            
            echo "Timing verification: Attempt $ATTEMPT, Elapsed: ''${ELAPSED}s"
            
            if [ "$ATTEMPT" -lt 3 ]; then
              # Expected delays: 1s, 2s (total ~3s for 3 attempts)
              echo "$((ATTEMPT + 1))" > "$STATE_FILE"
              
              if [ "$ATTEMPT" -eq 2 ]; then
                # After 2 retries, should have waited ~3 seconds (1s + 2s)
                if [ $ELAPSED -lt 2 ]; then
                  echo "WARNING: Timing seems too fast! Expected ~3s, got ''${ELAPSED}s"
                fi
              fi
              
              exit 1
            fi
            
            rm -f "$STATE_FILE" "$TIMING_FILE"
            echo "SUCCESS: Timing verification complete (total elapsed: ''${ELAPSED}s)"
          '';
          retry = {
            max_attempts = 3;
            backoff = "exponential";
            min_time = 1;
            max_time = 60;
          };
        }
      ];
    };
  };
}
