# SDK Types - type definitions for action inputs/outputs
{ lib }:

rec {
  # Marker for "no default value" (distinguishes from default = null)
  __noDefault = { __noDefault = true; };

  # Create a custom type
  # evalValidate: value -> bool (eval-time check)
  # runtimeValidate: bash snippet that checks $VALUE and $NAME
  # default: use __noDefault for required types, or actual value for optional
  mkType = {
    name,
    evalValidate ? (_: true),
    runtimeValidate ? "",
    default ? __noDefault,
  }: {
    __type = name;
    inherit evalValidate runtimeValidate default;
  };
  
  # Check if type has a default value
  hasDefault = type: !(type.default ? __noDefault);

  # Built-in types
  
  string = mkType {
    name = "string";
    evalValidate = v: builtins.isString v || (v ? __ref);
    # No runtime validation needed for strings (everything is string in bash)
    runtimeValidate = "";
  };
  
  int = mkType {
    name = "int";
    evalValidate = v: builtins.isInt v || (v ? __ref);
    runtimeValidate = ''
      if [ -n "$VALUE" ] && ! [[ "$VALUE" =~ ^-?[0-9]+$ ]]; then
        echo "Error: $NAME must be an integer, got: $VALUE" >&2
        exit 1
      fi
    '';
  };
  
  bool = mkType {
    name = "bool";
    evalValidate = v: builtins.isBool v || (v ? __ref);
    runtimeValidate = ''
      if [ -n "$VALUE" ] && ! [[ "$VALUE" =~ ^(true|false|0|1)$ ]]; then
        echo "Error: $NAME must be a boolean (true/false), got: $VALUE" >&2
        exit 1
      fi
    '';
  };
  
  path = mkType {
    name = "path";
    evalValidate = v: builtins.isString v || builtins.isPath v || (v ? __ref);
    runtimeValidate = ''
      if [ -n "$VALUE" ] && [ ! -e "$VALUE" ]; then
        echo "Error: $NAME path does not exist: $VALUE" >&2
        exit 1
      fi
    '';
  };
  
  # enum ["dev" "prod" "staging"]
  enum = values: mkType {
    name = "enum";
    evalValidate = v: builtins.elem v values || (v ? __ref);
    runtimeValidate = ''
      if [ -n "$VALUE" ]; then
        case "$VALUE" in
          ${lib.concatMapStringsSep "|" lib.escapeShellArg values}) ;;
          *)
            echo "Error: $NAME must be one of: ${lib.concatStringsSep ", " values}. Got: $VALUE" >&2
            exit 1
            ;;
        esac
      fi
    '';
  };
  
  # optional string - allows null/empty
  optional = innerType: mkType {
    name = "optional<${innerType.__type}>";
    evalValidate = v: v == null || v == "" || innerType.evalValidate v;
    # Only wrap inner validation if it exists
    runtimeValidate = 
      if innerType.runtimeValidate == "" then ""
      else ''
        if [ -n "$VALUE" ]; then
          ${innerType.runtimeValidate}
        fi
      '';
    default = null;
  };
  
  # array string - bash arrays
  array = innerType: mkType {
    name = "array<${innerType.__type}>";
    evalValidate = v: builtins.isList v || (v ? __ref);
    runtimeValidate = ''
      # Array validation - each element should match inner type
      # Note: arrays are passed as space-separated in bash
    '';
  };

  # Type with default value
  withDefault = type: defaultValue: type // { default = defaultValue; };
}
