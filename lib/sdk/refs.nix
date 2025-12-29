# SDK References - markers for runtime values that can't be resolved at eval-time
#
# These create special markers that defineAction recognizes and converts to
# proper bash variable references in generated code.
{ lib }:

rec {
  # Reference output from a previous step
  # Usage: stepOutput "build-image" "imageRef"
  # Generates: ${STEP_OUTPUT_build_image_imageRef}
  stepOutput = stepName: outputName: {
    __ref = "stepOutput";
    step = stepName;
    output = outputName;
  };

  # Reference an environment variable (resolved at runtime)
  # Usage: fromEnv "REGISTRY_URL"
  # Generates: ${REGISTRY_URL}
  fromEnv = envName: {
    __ref = "fromEnv";
    env = envName;
  };



  # Check if a value is a reference
  isRef = v: v ? __ref;

  # Convert a reference to bash variable expansion
  # Used by defineAction during bash codegen
  refToBash = ref:
    if ref.__ref == "stepOutput" then
      let
        # Sanitize names for bash variable (replace - with _)
        sanitizedStep = builtins.replaceStrings ["-"] ["_"] ref.step;
        sanitizedOutput = builtins.replaceStrings ["-"] ["_"] ref.output;
      in
      "\${STEP_OUTPUT_${sanitizedStep}_${sanitizedOutput}}"
    else if ref.__ref == "fromEnv" then
      "\${${ref.env}}"
    else if ref.__ref == "matrix" then
      "\${MATRIX_${ref.key}}"
    else
      throw "Unknown reference type: ${ref.__ref}";

  # Convert a value (literal or ref) to bash
  # - If it's a ref, convert to bash variable expansion
  # - If it's a string, escape and quote it
  # - If it's a number/bool, convert to string
  valueToBash = v:
    if isRef v then
      refToBash v
    else if builtins.isString v then
      lib.escapeShellArg v
    else if builtins.isInt v then
      toString v
    else if builtins.isBool v then
      if v then "true" else "false"
    else if builtins.isList v then
      # Convert list to space-separated string
      lib.concatMapStringsSep " " valueToBash v
    else if builtins.isPath v then
      toString v
    else if v == null then
      ""
    else
      throw "Cannot convert value to bash: ${builtins.typeOf v}";

  # Convert a value to unquoted bash (for use in variable assignments)
  # References are not quoted, literals are escaped
  valueToUnquotedBash = v:
    if isRef v then
      refToBash v
    else if builtins.isString v then
      v
    else if builtins.isInt v then
      toString v
    else if builtins.isBool v then
      if v then "true" else "false"
    else if builtins.isList v then
      lib.concatMapStringsSep " " valueToUnquotedBash v
    else if builtins.isPath v then
      toString v
    else if v == null then
      ""
    else
      throw "Cannot convert value to bash: ${builtins.typeOf v}";
}
