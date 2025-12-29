# SDK envOutputsExtension - transforms envOutputs to artifacts
#
# This extension transforms jobs with envOutputs into:
# 1. Adds a hidden artifact for env outputs file
# 2. Adds export step at end of job to write OUTPUT_* to file
# 3. Adds hidden artifact inputs for jobs with needs
# 4. Adds import step at start of dependent jobs to source the file
#
# Usage:
#   mkWorkflow {
#     extensions = [ sdk.envOutputsExtension ];
#     jobs = { ... };
#   }
{ lib }:

let
  refs = import ./refs.nix { inherit lib; };
in
rec {
  # Main extension function
  envOutputsExtension = workflow:
    let
      jobs = workflow.jobs or {};
      
      # Find all jobs with envOutputs
      jobsWithEnvOutputs = lib.filterAttrs (name: job:
        job ? __sdkJob && (job.__sdkJob.envOutputs or []) != []
      ) jobs;
      
      # Get env output file name for a job
      envOutputFile = jobName: ".env-outputs-${jobName}";
      
      # Transform job that HAS envOutputs - add export step and artifact
      transformProducer = jobName: job:
        let
          sdkJob = job.__sdkJob;
          envOutputs = sdkJob.envOutputs;
          fileName = envOutputFile jobName;
          sanitizedJobName = builtins.replaceStrings ["-"] ["_"] jobName;
        in job // {
          # Add hidden artifact for env outputs
          outputs = (job.outputs or {}) // {
            "__envOutputs_${jobName}" = fileName;
          };
          
          # Add export step at end
          steps = (job.steps or []) ++ [{
            name = "__export-env-outputs";
            condition = "always()";
            bash = ''
              echo "Exporting env outputs for job ${jobName}..."
              
              # Source JOB_ENV to get STEP_OUTPUT_* from previous steps
              if [ -n "''${JOB_ENV:-}" ] && [ -f "$JOB_ENV" ]; then
                # shellcheck disable=SC1090
                source "$JOB_ENV"
              fi
              
              : > "${fileName}"
              ${lib.concatMapStringsSep "\n" (outputName:
                let
                  sanitizedOutput = builtins.replaceStrings ["-"] ["_"] outputName;
                  jobVarName = "JOB_OUTPUT_${sanitizedJobName}_${sanitizedOutput}";
                in ''
                  # Check STEP_OUTPUT_*_${outputName} variables
                  # shellcheck disable=SC2154
                  _value=""
                  # Try common action name patterns
                  for _prefix in build_app run_tests deploy_app build test deploy; do
                    _varname="STEP_OUTPUT_''${_prefix}_${outputName}"
                    eval "_val=\"\''${$_varname:-}\""
                    if [ -n "$_val" ]; then
                      _value="$_val"
                      echo "  ${outputName}=$_value (from $_varname)"
                      break
                    fi
                  done
                  
                  # Fallback: check OUTPUT_${outputName} directly
                  if [ -z "$_value" ] && [ -n "''${OUTPUT_${outputName}:-}" ]; then
                    _value="$OUTPUT_${outputName}"
                    echo "  ${outputName}=$_value (from OUTPUT_${outputName})"
                  fi
                  
                  if [ -n "$_value" ]; then
                    echo "export ${jobVarName}=$(printf '%q' "$_value")" >> "${fileName}"
                  fi
                ''
              ) envOutputs}
              echo "Env outputs exported to ${fileName}"
            '';
          }];
        };
      
      # Transform job that HAS needs - add import step and artifact inputs
      transformConsumer = jobName: job:
        let
          jobNeeds = job.needs or [];
          # Find which of the needs have envOutputs
          needsWithEnvOutputs = builtins.filter (needName:
            jobsWithEnvOutputs ? ${needName}
          ) jobNeeds;
        in
        if needsWithEnvOutputs == [] then job
        else job // {
          # Add hidden artifact inputs
          inputs = (job.inputs or []) ++ 
            map (needName: "__envOutputs_${needName}") needsWithEnvOutputs;
          
          # Add import step at start
          steps = [{
            name = "__import-env-outputs";
            bash = ''
              echo "Importing env outputs from dependencies..."
              # shellcheck disable=SC1091
              ${lib.concatMapStringsSep "\n" (needName:
                let fileName = envOutputFile needName;
                in ''
                  if [ -f "${fileName}" ]; then
                    echo "  Sourcing ${fileName}"
                    source "${fileName}"
                    # Append to JOB_ENV so subsequent steps can see these vars
                    if [ -n "''${JOB_ENV:-}" ]; then
                      cat "${fileName}" >> "$JOB_ENV"
                    fi
                  fi
                ''
              ) needsWithEnvOutputs}
              echo "Env outputs imported"
            '';
          }] ++ (job.steps or []);
        };
      
      # Apply transformations
      transformedJobs = lib.mapAttrs (jobName: job:
        let
          # First transform if it's a producer
          afterProducer = 
            if jobsWithEnvOutputs ? ${jobName} 
            then transformProducer jobName job
            else job;
          # Then transform if it's a consumer
          afterConsumer = transformConsumer jobName afterProducer;
        in afterConsumer
      ) jobs;
      
    in workflow // { jobs = transformedJobs; };
}
