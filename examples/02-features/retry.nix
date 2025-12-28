{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "example-retry";
  
  # Workflow-level retry (applies to all jobs/actions unless overridden)
  retry = {
    max_attempts = 2;
    backoff = "exponential";
    min_time = 1;
    max_time = 30;
  };
  
  jobs = {
    # Test different retry scenarios
    test-exponential = {
      inherit executor;
      
      # Override job-level retry
      retry = {
        max_attempts = 3;
        backoff = "exponential";
        min_time = 1;
        max_time = 60;
      };
      
      actions = [
        {
          name = "fail-twice-then-succeed";
          bash = ''
            # Create state file to track attempts
            STATE_FILE="/tmp/nixactions-retry-test-$$"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "0" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            ATTEMPT=$((ATTEMPT + 1))
            echo "$ATTEMPT" > "$STATE_FILE"
            
            echo "Attempt $ATTEMPT"
            
            if [ $ATTEMPT -lt 3 ]; then
              echo "Failing on purpose (attempt $ATTEMPT)..." >&2
              rm -f "$STATE_FILE"  # Clean up
              exit 1
            fi
            
            echo "Success on attempt $ATTEMPT!"
            rm -f "$STATE_FILE"  # Clean up
          '';
          # This action inherits job-level retry (3 attempts, exponential)
        }
      ];
    };
    
    test-linear = {
      inherit executor;
      needs = ["test-exponential"];
      
      actions = [
        {
          name = "fail-once-with-linear-backoff";
          bash = ''
            STATE_FILE="/tmp/nixactions-retry-linear-$$"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "0" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            ATTEMPT=$((ATTEMPT + 1))
            echo "$ATTEMPT" > "$STATE_FILE"
            
            echo "Attempt $ATTEMPT (linear backoff)"
            
            if [ $ATTEMPT -lt 2 ]; then
              echo "Failing on purpose..." >&2
              rm -f "$STATE_FILE"
              exit 1
            fi
            
            echo "Success!"
            rm -f "$STATE_FILE"
          '';
          retry = {
            max_attempts = 3;
            backoff = "linear";
            min_time = 2;
            max_time = 10;
          };
        }
      ];
    };
    
    test-constant = {
      inherit executor;
      needs = ["test-linear"];
      
      actions = [
        {
          name = "constant-backoff";
          bash = ''
            STATE_FILE="/tmp/nixactions-retry-constant-$$"
            
            if [ ! -f "$STATE_FILE" ]; then
              echo "0" > "$STATE_FILE"
            fi
            
            ATTEMPT=$(cat "$STATE_FILE")
            ATTEMPT=$((ATTEMPT + 1))
            echo "$ATTEMPT" > "$STATE_FILE"
            
            echo "Attempt $ATTEMPT (constant backoff)"
            
            if [ $ATTEMPT -lt 2 ]; then
              echo "Failing..." >&2
              rm -f "$STATE_FILE"
              exit 1
            fi
            
            echo "Success!"
            rm -f "$STATE_FILE"
          '';
          retry = {
            max_attempts = 3;
            backoff = "constant";
            min_time = 3;
            max_time = 3;
          };
        }
      ];
    };
    
    test-no-retry = {
      inherit executor;
      needs = ["test-constant"];
      
      # Disable retry for this job
      retry = null;
      
      actions = [
        {
          name = "no-retry-success";
          bash = ''
            echo "This action has no retry - it succeeds on first attempt"
            echo "Success!"
          '';
        }
      ];
    };
    
    test-max-attempts-one = {
      inherit executor;
      needs = ["test-no-retry"];
      
      actions = [
        {
          name = "single-attempt";
          bash = ''
            echo "This action has max_attempts=1, so no retry"
            echo "Success!"
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
  };
}
