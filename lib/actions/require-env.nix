{ pkgs, lib }:

vars:

{
  name = "require-env";
  bash = lib.concatMapStringsSep "\n" (var: ''
    if [ -z "''${${var}:-}" ]; then
      echo "ERROR: Required env var not set: ${var}"
      exit 1
    fi
    echo "✓ ${var} is set"
  '') vars;
}
