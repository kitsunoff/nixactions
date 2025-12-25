{ pkgs, lib }:

{ path
, required ? false
, secrets ? false  # Are values in this file secrets?
}:

pkgs.writeScriptBin "env-provider-file" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${path}"
  
  # Check if file exists
  if [ ! -f "$FILE" ]; then
    ${if required then ''
      echo "Error: Required env file not found: $FILE" >&2
      exit 1
    '' else ''
      # File not found but not required - silent success
      exit 0
    ''}
  fi
  
  # Read file and output exports
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    [[ -z "$line" ]] && continue
    
    # Skip comments (lines starting with # after optional whitespace)
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Parse KEY=VALUE format
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="''${BASH_REMATCH[1]}"
      value="''${BASH_REMATCH[2]}"
      
      # Remove surrounding quotes if present (both single and double)
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        # Double quotes
        value="''${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        # Single quotes
        value="''${BASH_REMATCH[1]}"
      fi
      
      # Output export statement with proper escaping
      printf 'export %s=%s\n' "$key" "$(printf '%q' "$value")"
    fi
  done < "$FILE"
''
