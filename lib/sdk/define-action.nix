# SDK defineAction - creates typed actions with automatic bash codegen
#
# Usage:
#   buildImage = defineAction {
#     name = "build-image";
#     inputs = {
#       registry = types.string;
#       tag = types.string // { default = "latest"; };
#     };
#     outputs = {
#       imageRef = types.string;
#     };
#     run = ''
#       IMAGE="$INPUT_registry:$INPUT_tag"
#       buildah build -t "$IMAGE" .
#       OUTPUT_imageRef="$IMAGE"
#     '';
#   };
#
#   # Then use in workflow:
#   steps = [
#     (buildImage { registry = "ghcr.io"; tag = "v1.0"; })
#   ];
#
#   # Multiple calls with unique names via `as`:
#   steps = [
#     (greet { name = "Alice"; as = "greet-alice"; })
#     (greet { name = "Bob"; as = "greet-bob"; })
#     (announce { message = sdk.stepOutput "greet-bob" "message"; })
#   ];
{ lib }:

let
  types = import ./types.nix { inherit lib; };
  refs = import ./refs.nix { inherit lib; };
in
rec {
  # Main action definition function
  defineAction = {
    name,
    inputs ? {},
    outputs ? {},
    run,
    # Optional: packages needed at runtime
    packages ? [],
    # Optional: description for documentation
    description ? "",
  }:
  # Returns a function that takes input values and returns a step attrset
  inputValues:
  let
    # Support `as` parameter to override step name
    stepName = inputValues.as or name;
    
    # Merge provided values with defaults from type definitions
    # Filter out `as` since it's not a real input
    providedInputs = builtins.removeAttrs inputValues [ "as" ];
    
    resolvedInputs = lib.mapAttrs (inputName: inputType:
      if providedInputs ? ${inputName} then
        providedInputs.${inputName}
      else if types.hasDefault inputType then
        # Use default value (can be null for optional types)
        inputType.default
      else
        throw "Action '${name}': missing required input '${inputName}'"
    ) inputs;

    # Generate bash code to set INPUT_ variables
    inputSetupCode = lib.concatStringsSep "\n" (lib.mapAttrsToList (inputName: value:
      let
        bashValue = refs.valueToUnquotedBash value;
      in
      if refs.isRef value then
        # For refs, expand the variable without quotes
        # Disable shellcheck warning for runtime vars
        ''
          # shellcheck disable=SC2154
          INPUT_${inputName}=${bashValue}''
      else
        # For literals, quote the value
        "INPUT_${inputName}=${lib.escapeShellArg bashValue}"
    ) resolvedInputs);

    # Generate runtime validation code for inputs
    inputValidationCode = lib.concatStringsSep "\n" (lib.mapAttrsToList (inputName: inputType:
      if inputType.runtimeValidate != "" then
        ''
          VALUE="$INPUT_${inputName}"
          NAME="INPUT_${inputName}"
          ${inputType.runtimeValidate}
        ''
      else ""
    ) inputs);

    # Generate bash code to export outputs
    # After run script, OUTPUT_* vars become STEP_OUTPUT_<stepName>_<output>
    # Outputs are both exported (for within-action use) and written to JOB_ENV (for cross-action use)
    # JOB_ENV is already sourced by the runtime before each action
    outputExportCode = lib.concatStringsSep "\n" (lib.mapAttrsToList (outputName: _:
      let
        sanitizedName = builtins.replaceStrings ["-"] ["_"] stepName;
        sanitizedOutput = builtins.replaceStrings ["-"] ["_"] outputName;
        varName = "STEP_OUTPUT_${sanitizedName}_${sanitizedOutput}";
      in
      ''
        if [ -n "''${OUTPUT_${outputName}:-}" ]; then
          export ${varName}="$OUTPUT_${outputName}"
          # Write to JOB_ENV for persistence between actions
          if [ -n "''${JOB_ENV:-}" ]; then
            echo "export ${varName}=$(printf '%q' "$OUTPUT_${outputName}")" >> "$JOB_ENV"
          fi
        fi
      ''
    ) outputs);

    # Combine into final bash script
    bashScript = ''
      # === Action: ${stepName} ===
      ${lib.optionalString (description != "") "# ${description}"}

      # Setup inputs
      ${inputSetupCode}

      # Validate inputs
      ${inputValidationCode}

      # Run action
      ${run}

      # Export outputs
      ${outputExportCode}
    '';

  in {
    # Step name for identification (uses `as` if provided)
    name = stepName;
    
    # The bash script to execute
    bash = bashScript;
    
    # Metadata for validation extension
    __sdkAction = {
      name = stepName;
      actionName = name;  # Original action name for reference
      inherit inputs outputs description;
      inputValues = resolvedInputs;
    };
    
    # Optional packages (can be used by executors)
    inherit packages;
  };

  # Helper to create a simple action (no inputs/outputs)
  simpleAction = name: run: defineAction {
    inherit name run;
  } {};

  # Helper to create an action from a Nix derivation (script)
  # This wraps a derivation in the SDK format
  fromScript = { name, script, outputs ? {} }:
  inputValues:
  {
    inherit name;
    bash = "${lib.getExe script}";
    __sdkAction = {
      inherit name outputs;
      inputs = {};
      inputValues = {};
      description = "Wrapped script: ${script.name or name}";
    };
    packages = [];
  };
}
