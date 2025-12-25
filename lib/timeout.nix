{ pkgs, lib }:

rec {
  # Convert timeout config to environment variables
  timeoutToEnv = timeoutStr:
    if timeoutStr == null then {}
    else { NIXACTIONS_TIMEOUT = timeoutStr; };
  
  # Parse timeout string to seconds
  # Examples: "30s" → 30, "5m" → 300, "2h" → 7200
  parseTimeout = timeoutStr:
    if timeoutStr == null then null
    else if lib.hasSuffix "s" timeoutStr then
      lib.toInt (lib.removeSuffix "s" timeoutStr)
    else if lib.hasSuffix "m" timeoutStr then
      (lib.toInt (lib.removeSuffix "m" timeoutStr)) * 60
    else if lib.hasSuffix "h" timeoutStr then
      (lib.toInt (lib.removeSuffix "h" timeoutStr)) * 3600
    else
      # Assume seconds if no suffix
      lib.toInt timeoutStr;
  
  # Format seconds back to human-readable string
  formatTimeout = seconds:
    if seconds == null then "none"
    else if seconds >= 3600 then "${toString (seconds / 3600)}h"
    else if seconds >= 60 then "${toString (seconds / 60)}m"
    else "${toString seconds}s";
  
  # Merge timeout configs with priority: action > job > workflow
  mergeTimeoutConfigs = { workflow, job, action }:
    if action != null then action
    else if job != null then job
    else workflow;
  
  # Generate bash code to wrap command with timeout
  wrapWithTimeout = { timeoutStr, command, name ? "command" }: 
    let
      timeoutSeconds = parseTimeout timeoutStr;
    in
      if timeoutSeconds == null then command
      else ''
        # Timeout wrapper for ${name}
        _timeout_start=$SECONDS
        _timeout_limit=${toString timeoutSeconds}
        _timeout_pid=""
        
        # Run command in background
        (
          ${command}
        ) &
        _timeout_pid=$!
        
        # Wait for completion or timeout
        while kill -0 $_timeout_pid 2>/dev/null; do
          _timeout_elapsed=$((SECONDS - _timeout_start))
          
          if [ $_timeout_elapsed -ge $_timeout_limit ]; then
            # Timeout reached - kill process tree
            echo "⏱ Timeout reached (${formatTimeout timeoutSeconds}) for ${name}" >&2
            
            # Kill entire process group
            pkill -P $_timeout_pid 2>/dev/null || true
            kill $_timeout_pid 2>/dev/null || true
            sleep 1
            kill -9 $_timeout_pid 2>/dev/null || true
            
            exit 124  # Standard timeout exit code
          fi
          
          sleep 1
        done
        
        # Get exit code
        wait $_timeout_pid
      '';
  
  # Timeout helpers derivation (for runtime use)
  timeoutHelpers = pkgs.writeScriptBin "nixactions-timeout" ''
    #!/usr/bin/env bash
    
    # Parse timeout string to seconds
    parse_timeout() {
      local timeout_str="$1"
      
      if [[ -z "$timeout_str" ]]; then
        echo "0"
        return
      fi
      
      if [[ "$timeout_str" =~ ^([0-9]+)s$ ]]; then
        echo "''${BASH_REMATCH[1]}"
      elif [[ "$timeout_str" =~ ^([0-9]+)m$ ]]; then
        echo "$((''${BASH_REMATCH[1]} * 60))"
      elif [[ "$timeout_str" =~ ^([0-9]+)h$ ]]; then
        echo "$((''${BASH_REMATCH[1]} * 3600))"
      else
        # Assume seconds
        echo "$timeout_str"
      fi
    }
    
    # Format seconds to human readable
    format_timeout() {
      local seconds="$1"
      
      if [ "$seconds" -ge 3600 ]; then
        echo "$((seconds / 3600))h"
      elif [ "$seconds" -ge 60 ]; then
        echo "$((seconds / 60))m"
      else
        echo "''${seconds}s"
      fi
    }
    
    # Run command with timeout
    run_with_timeout() {
      local timeout_str="$1"
      shift
      local command=("$@")
      
      local timeout_seconds
      timeout_seconds=$(parse_timeout "$timeout_str")
      
      if [ "$timeout_seconds" -eq 0 ]; then
        # No timeout - run directly
        "''${command[@]}"
        return $?
      fi
      
      local timeout_start=$SECONDS
      local timeout_pid=""
      
      # Run command in background
      "''${command[@]}" &
      timeout_pid=$!
      
      # Wait for completion or timeout
      while kill -0 $timeout_pid 2>/dev/null; do
        local elapsed=$((SECONDS - timeout_start))
        
        if [ $elapsed -ge $timeout_seconds ]; then
          # Timeout reached
          echo "⏱ Timeout reached ($(format_timeout "$timeout_seconds"))" >&2
          
          # Kill process tree
          pkill -P $timeout_pid 2>/dev/null || true
          kill $timeout_pid 2>/dev/null || true
          sleep 1
          kill -9 $timeout_pid 2>/dev/null || true
          
          return 124  # Standard timeout exit code
        fi
        
        sleep 1
      done
      
      # Get exit code
      wait $timeout_pid
      return $?
    }
    
    # Export functions
    export -f parse_timeout
    export -f format_timeout
    export -f run_with_timeout
  '';
}
