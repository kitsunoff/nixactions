# loadOutputs - Load and validate JSON outputs from a file
#
# This action parses a JSON file and exports its fields as environment variables.
# Useful for passing structured data between jobs via artifacts.
#
# Usage:
#   loadBuildOutputs = nixactions.actions.loadOutputs {
#     file = ".build-outputs.json";
#     schema = {
#       buildId = types.string;
#       version = types.string;
#       exitCode = types.int;
#     };
#   };
#
#   # In job that produces outputs:
#   jobs.build = {
#     steps = [
#       { bash = ''echo '{"buildId":"abc123","version":"1.0.0","exitCode":0}' > .build-outputs.json''; }
#     ];
#     outputs = { buildOutputs = ".build-outputs.json"; };
#   };
#
#   # In job that consumes outputs:
#   jobs.test = {
#     needs = ["build"];
#     inputs = ["buildOutputs"];
#     steps = [
#       (loadBuildOutputs {})
#       # Now $buildId, $version, $exitCode are available
#       { bash = ''echo "Build ID: $buildId, Version: $version"''; }
#     ];
#   };
{ pkgs, lib, sdk }:

let
  types = sdk.types;
  jq = "${pkgs.jq}/bin/jq";
in

# Factory function: takes config, returns mkAction result
{ file, schema, name ? "load-outputs" }:

sdk.mkAction {
  inherit name;
  description = "Load and validate outputs from ${file}";
  
  inputs = {
    file = types.withDefault types.string file;
  };
  
  run = ''
    _file="$INPUT_file"
    
    if [ ! -f "$_file" ]; then
      echo "Error: Output file not found: $_file" >&2
      exit 1
    fi
    
    echo "Loading outputs from $_file"
    
    # Validate JSON
    if ! ${jq} empty "$_file" 2>/dev/null; then
      echo "Error: Invalid JSON in $_file" >&2
      exit 1
    fi
    
    # Extract and validate each field
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (fieldName: fieldType:
      let
        # Generate validation code based on type
        validation = 
          if fieldType.__type == "int" then ''
            if [ -n "$_value" ] && ! [[ "$_value" =~ ^-?[0-9]+$ ]]; then
              echo "Error: ${fieldName} must be an integer, got: $_value" >&2
              exit 1
            fi
          ''
          else if fieldType.__type == "bool" then ''
            if [ -n "$_value" ] && ! [[ "$_value" =~ ^(true|false)$ ]]; then
              echo "Error: ${fieldName} must be a boolean, got: $_value" >&2
              exit 1
            fi
          ''
          else "";
      in ''
        _value=$(${jq} -r '.${fieldName} // empty' "$_file")
        ${validation}
        export ${fieldName}="$_value"
        echo "  ${fieldName}=$_value"
        
        # Persist to JOB_ENV for subsequent steps
        if [ -n "''${JOB_ENV:-}" ]; then
          echo "export ${fieldName}=$(printf '%q' "$_value")" >> "$JOB_ENV"
        fi
      ''
    ) schema)}
    
    echo "Outputs loaded successfully"
  '';
  
  packages = [ pkgs.jq ];
}
