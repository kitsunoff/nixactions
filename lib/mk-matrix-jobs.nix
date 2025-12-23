{ pkgs, lib }:

{
  # Template job configuration (without matrix)
  name,
  matrix,
  jobTemplate,
}:

assert lib.assertMsg (name != "") "Job name cannot be empty";
assert lib.assertMsg (builtins.isAttrs matrix) "matrix must be an attribute set";
assert lib.assertMsg (builtins.isFunction jobTemplate) "jobTemplate must be a function that receives matrix vars";

let
  # Get all matrix dimension names and their values
  matrixDimensions = lib.attrNames matrix;
  
  # Generate all combinations of matrix values
  # Example: { node = ["18" "20"]; os = ["ubuntu" "macos"]; }
  # → [{ node = "18"; os = "ubuntu"; } { node = "18"; os = "macos"; } { node = "20"; os = "ubuntu"; } { node = "20"; os = "macos"; }]
  cartesianProduct = dimensions:
    let
      # Recursive helper
      go = dims: 
        if dims == [] then [{}]
        else
          let
            dimName = lib.head dims;
            dimValues = matrix.${dimName};
            rest = go (lib.tail dims);
          in
            lib.flatten (map (value:
              map (combo: combo // { ${dimName} = value; }) rest
            ) dimValues);
    in
      go dimensions;
  
  # All combinations
  combinations = cartesianProduct matrixDimensions;
  
  # Generate job name from matrix values
  # Example: test + { node = "18"; os = "ubuntu"; } → "test-node18-os-ubuntu"
  generateJobName = matrixVars:
    let
      # Sort dimensions to ensure consistent ordering
      sortedDims = lib.sort (a: b: a < b) matrixDimensions;
      suffix = lib.concatStringsSep "-" (
        map (key: "${key}-${toString matrixVars.${key}}") sortedDims
      );
    in
      "${name}-${suffix}";
  
  # Generate jobs attribute set
  # For each combination, create a job with the matrix variables injected
  jobs = lib.listToAttrs (map (matrixVars:
    let
      jobName = generateJobName matrixVars;
      
      # Call jobTemplate with matrix variables
      # The template function handles interpolation via ${var}
      job = jobTemplate matrixVars;
      
    in {
      name = jobName;
      value = job // {
        # Add matrix metadata to job (useful for debugging)
        passthru = (job.passthru or {}) // {
          matrix = matrixVars;
        };
      };
    }
  ) combinations);
  
in

jobs
