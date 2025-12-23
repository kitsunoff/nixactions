{ pkgs, lib }:

{
  # ============================================================
  # Bash Logging Functions (to be injected into workflow script)
  # ============================================================
  
  # Generate bash code for logging functions
  # These will be available in the workflow execution environment
  bashFunctions = ''
    # ============================================================
    # Structured Logging Functions
    # ============================================================
    
    _log_timestamp() {
      date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
    }
    
    # Universal log function: _log key1 value1 key2 value2 ... message
    # Last argument is always the message
    # Example: _log job test action checkout duration 1.5 exit_code 0 "Completed"
    _log() {
      local -A fields=()
      local message=""
      
      # Parse arguments: key-value pairs, last one is message
      while [ $# -gt 0 ]; do
        if [ $# -eq 1 ]; then
          # Last argument is the message
          message="$1"
          shift
        else
          # Key-value pair
          fields["$1"]="$2"
          shift 2
        fi
      done
      
      # Build log entry based on format
      if [ "$NIXACTIONS_LOG_FORMAT" = "simple" ]; then
        # Simple format: just the message (or with action name)
        if [ -n "''${fields[action]:-}" ]; then
          echo "''${fields[event]:-→} ''${fields[action]} $message" >&2
        else
          echo "$message" >&2
        fi
      elif [ "$NIXACTIONS_LOG_FORMAT" = "json" ]; then
        # JSON format
        local json="{\"timestamp\":\"$(_log_timestamp)\",\"workflow\":\"$WORKFLOW_NAME\""
        
        # Add all fields
        for key in "''${!fields[@]}"; do
          local value="''${fields[$key]}"
          # Check if value is a number
          if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            json="$json,\"$key\":$value"
          else
            # Escape quotes for JSON
            value=$(echo "$value" | sed 's/"/\\"/g')
            json="$json,\"$key\":\"$value\""
          fi
        done
        
        json="$json,\"message\":\"$message\"}"
        echo "$json" >&2
      else
        # Structured format (default)
        local prefix="[$(_log_timestamp)] [workflow:$WORKFLOW_NAME]"
        
        # Add job and action if present
        if [ -n "''${fields[job]:-}" ]; then
          prefix="$prefix [job:''${fields[job]}]"
        fi
        if [ -n "''${fields[action]:-}" ]; then
          prefix="$prefix [action:''${fields[action]}]"
        fi
        
        # Build details from remaining fields
        local details=""
        for key in "''${!fields[@]}"; do
          if [ "$key" != "job" ] && [ "$key" != "action" ] && [ "$key" != "event" ]; then
            if [ -z "$details" ]; then
              details="($key: ''${fields[$key]}"
            else
              details="$details, $key: ''${fields[$key]}"
            fi
          fi
        done
        if [ -n "$details" ]; then
          details="$details)"
        fi
        
        echo "$prefix $message ''${details}" >&2
      fi
    }
    
    # Wrap command output with structured logging
    _log_line() {
      local job="$1"
      local action="$2"
      while IFS= read -r line; do
        _log job "$job" action "$action" event "output" "$line"
      done
    }
    
    # Log job-level events (convenience wrapper)
    _log_job() {
      _log job "$@"
    }
    
    # Log workflow-level events (convenience wrapper)
    _log_workflow() {
      _log "$@"
    }
    
    # Export functions so they're available in subshells and executors
    export -f _log_timestamp
    export -f _log
    export -f _log_line
    export -f _log_job
    export -f _log_workflow
  '';
}
