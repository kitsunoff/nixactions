{ pkgs, lib }:

{ file
, format ? "yaml"
, required ? true
}:

assert lib.assertMsg (builtins.elem format ["yaml" "json" "dotenv"])
  "SOPS format must be one of: yaml, json, dotenv (got: ${format})";

pkgs.writeScriptBin "env-provider-sops" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  FILE="${file}"
  FORMAT="${format}"
  
  # Check if file exists
  if [ ! -f "$FILE" ]; then
    ${if required then ''
      echo "Error: Required SOPS file not found: $FILE" >&2
      exit 1
    '' else ''
      exit 0
    ''}
  fi
  
  # Check if sops is available
  if ! command -v ${pkgs.sops}/bin/sops >/dev/null 2>&1; then
    echo "Error: SOPS CLI not available" >&2
    exit 1
  fi
  
  # Decrypt and convert to exports based on format
  case "$FORMAT" in
    yaml)
      # Decrypt YAML and convert to exports
      if ! command -v ${pkgs.yq}/bin/yq >/dev/null 2>&1; then
        echo "Error: yq not available (required for YAML format)" >&2
        exit 1
      fi
      
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | \
        ${pkgs.yq}/bin/yq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
      ;;
      
    json)
      # Decrypt JSON and convert to exports
      if ! command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
        echo "Error: jq not available (required for JSON format)" >&2
        exit 1
      fi
      
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | \
        ${pkgs.jq}/bin/jq -r 'to_entries | .[] | "export \(.key)=\(.value | @sh)"'
      ;;
      
    dotenv)
      # Decrypt dotenv format and output exports
      ${pkgs.sops}/bin/sops -d "$FILE" 2>/dev/null | while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse KEY=VALUE
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
          key="''${BASH_REMATCH[1]}"
          value="''${BASH_REMATCH[2]}"
          
          # Remove quotes if present
          if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
            value="''${BASH_REMATCH[1]}"
          fi
          
          # Output export with proper escaping
          printf 'export %s=%s\n' "$key" "$(printf '%q' "$value")"
        fi
      done
      ;;
      
    *)
      echo "Error: Unknown SOPS format: $FORMAT" >&2
      exit 1
      ;;
  esac
'' // {
  # Metadata: All variables from SOPS are secrets
  passthru.allSecrets = true;
}
