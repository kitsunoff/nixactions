{ pkgs, lib }:

requiredVars:

assert lib.assertMsg (builtins.isList requiredVars)
  "required must be a list of variable names";
assert lib.assertMsg (builtins.all builtins.isString requiredVars)
  "All required variable names must be strings";

pkgs.writeScriptBin "env-provider-required" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # List of required variables
  REQUIRED_VARS=(${lib.concatMapStringsSep " " lib.escapeShellArg requiredVars})
  MISSING=()
  
  # Check each required variable
  for var in "''${REQUIRED_VARS[@]}"; do
    if [ -z "''${!var+x}" ]; then
      MISSING+=("$var")
    fi
  done
  
  # Report missing variables
  if [ ''${#MISSING[@]} -gt 0 ]; then
    echo "Error: Required environment variables not set:" >&2
    printf '  - %s\n' "''${MISSING[@]}" >&2
    exit 1
  fi
  
  # All required variables present - output nothing (success)
  # This provider only validates, doesn't set variables
  exit 0
''
