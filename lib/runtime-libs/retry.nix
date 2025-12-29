{ lib, pkgs }:

rec {
  # Default retry configuration
  defaultRetryConfig = {
    max_attempts = 1;          # No retry by default (single attempt)
    backoff = "exponential";   # Exponential backoff if retry enabled
    min_time = 1;              # 1 second minimum delay
    max_time = 60;             # 60 seconds maximum delay
  };

  # Check if retry is enabled
  isRetryEnabled = retryConfig:
    retryConfig != null && (retryConfig.max_attempts or 1) > 1;

  # Merge retry configurations with priority: action > job > workflow
  # Returns null if retry should be disabled
  mergeRetryConfigs = { workflow ? null, job ? null, action ? null }:
    let
      # Priority: action > job > workflow
      merged = defaultRetryConfig
        // (if workflow != null then workflow else {})
        // (if job != null then job else {})
        // (if action != null then action else {});
    in
      # Disable retry if max_attempts <= 1 or explicitly set to null
      if (action == null && job == null && workflow == null) then null
      else if merged.max_attempts <= 1 then null
      else merged;

  # Calculate backoff delay for a given attempt
  # Returns delay in seconds
  calculateBackoff = { attempt, backoff, min_time, max_time }:
    let
      # Helper: calculate 2^n
      pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);
      
      # Calculate raw delay based on backoff strategy
      rawDelay =
        if backoff == "exponential" then
          # exponential: min_time * 2^(attempt-1)
          min_time * (pow2 (attempt - 1))
        else if backoff == "linear" then
          # linear: min_time * attempt
          min_time * attempt
        else if backoff == "constant" then
          # constant: always min_time
          min_time
        else
          # Unknown backoff strategy, fallback to exponential
          min_time * (pow2 (attempt - 1));
      
      # Cap at max_time
      cappedDelay = if rawDelay > max_time then max_time else rawDelay;
    in
      cappedDelay;

  # ============================================================
  # Retry Helpers Derivation
  # ============================================================
  
  # Derivation with retry functions
  retryHelpers = pkgs.writeScriptBin "nixactions-retry" ''
    #!${pkgs.bash}/bin/bash
    
    # Calculate backoff delay based on strategy
    # Args: attempt backoff_type min_time max_time
    calculate_backoff() {
      local attempt=$1
      local backoff_type=$2
      local min_time=$3
      local max_time=$4
      local delay=0
      
      case "$backoff_type" in
        exponential)
          # exponential: min_time * 2^(attempt-1)
          delay=$((min_time * (1 << (attempt - 1))))
          ;;
        linear)
          # linear: min_time * attempt
          delay=$((min_time * attempt))
          ;;
        constant)
          # constant: always min_time
          delay=$min_time
          ;;
        *)
          # Unknown strategy, fallback to exponential
          delay=$((min_time * (1 << (attempt - 1))))
          ;;
      esac
      
      # Cap at max_time
      if [ $delay -gt $max_time ]; then
        echo $max_time
      else
        echo $delay
      fi
    }
    
    # Retry wrapper function
    # Environment variables expected:
    #   RETRY_MAX_ATTEMPTS (default: 1)
    #   RETRY_BACKOFF (default: "exponential")
    #   RETRY_MIN_TIME (default: 1)
    #   RETRY_MAX_TIME (default: 60)
    # Args: command to execute
    retry_command() {
      local max_attempts=''${RETRY_MAX_ATTEMPTS:-1}
      local backoff_type=''${RETRY_BACKOFF:-exponential}
      local min_time=''${RETRY_MIN_TIME:-1}
      local max_time=''${RETRY_MAX_TIME:-60}
      local attempt=1
      
      # If max_attempts is 1, just run once (no retry)
      if [ "$max_attempts" -eq 1 ]; then
        "$@"
        return $?
      fi
      
      # Retry loop
      while [ $attempt -le $max_attempts ]; do
        # Run the command
        if "$@"; then
            # Success
            if [ $attempt -gt 1 ]; then
              _log retry "action.retry-success" "attempt=$attempt total_attempts=$attempt"
            fi
          return 0
        fi
        
        local exit_code=$?
        
        # Check if this was the last attempt
        if [ $attempt -eq $max_attempts ]; then
          _log retry "exhausted" "attempts=$max_attempts exit_code=$exit_code"
          return $exit_code
        fi
        
        # Calculate delay for next attempt
        local delay=$(calculate_backoff $attempt "$backoff_type" $min_time $max_time)
        local next_attempt=$((attempt + 1))
        
        _log retry "waiting" "attempt=$attempt/$max_attempts next_attempt=$next_attempt delay=''${delay}s backoff=$backoff_type exit_code=$exit_code"
        
        # Wait before retry
        sleep $delay
        
        attempt=$next_attempt
      done
      
      # Should never reach here, but just in case
      return 1
    }
    
    # ============================================================
    # Export functions
    # ============================================================
    
    export -f calculate_backoff
    export -f retry_command
  '';
  
  # ============================================================
  # Legacy: Bash Function String (for backward compatibility)
  # ============================================================
  
  # DEPRECATED: Use retryHelpers derivation instead
  retryBashFunction = ''
    # DEPRECATED: Import from derivation instead
    # source ${retryHelpers}/bin/nixactions-retry
  '';

  # Generate environment variables for retry configuration
  # Input: retry config attrset or null
  # Output: attrset of environment variables
  retryToEnv = retryConfig:
    if retryConfig == null then {}
    else {
      RETRY_MAX_ATTEMPTS = toString retryConfig.max_attempts;
      RETRY_BACKOFF = retryConfig.backoff;
      RETRY_MIN_TIME = toString retryConfig.min_time;
      RETRY_MAX_TIME = toString retryConfig.max_time;
    };
}
