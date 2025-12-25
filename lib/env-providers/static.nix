{ pkgs, lib }:

env:

assert lib.assertMsg (builtins.isAttrs env)
  "static env must be an attribute set";

pkgs.writeScriptBin "env-provider-static" ''
  #!/usr/bin/env bash
  set -euo pipefail
  
  # Output all static environment variables as exports
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (key: value:
      # Validate key name (must be valid bash variable name)
      assert lib.assertMsg 
        (builtins.match "[A-Za-z_][A-Za-z0-9_]*" key != null)
        "Invalid environment variable name: ${key} (must match [A-Za-z_][A-Za-z0-9_]*)";
      
      "printf 'export %s=%s\\n' ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.escapeShellArg (toString value))}"
    ) env
  )}
'' // {
  # Metadata: Static values are NOT secrets by default
  passthru.allSecrets = false;
}
