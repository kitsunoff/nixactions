# SDK Validation Extension - eval-time type checking for SDK actions
#
# This is a workflow extension that validates all SDK actions at Nix evaluation time.
# Use with mkWorkflow's extensions parameter:
#
#   mkWorkflow {
#     extensions = [ nixactions.sdk.validation ];
#     jobs = { ... };
#   }
#
# Validation checks:
# - All required inputs are provided
# - Input values match their declared types (when not refs)
# - Referenced step outputs exist (basic check)
{ lib }:

let
  types = import ./types.nix { inherit lib; };
  refs = import ./refs.nix { inherit lib; };
in
rec {
  # The validation extension function
  # Takes a workflow and returns validated workflow (or throws on error)
  validation = workflow:
  let
    # Validate a single step
    validateStep = jobName: stepIndex: step:
      if step ? __sdkAction then
        validateSdkAction jobName stepIndex step
      else
        # Non-SDK steps pass through unchanged
        step;

    # Validate an SDK action's inputs
    validateSdkAction = jobName: stepIndex: step:
    let
      action = step.__sdkAction;
      errors = validateInputs action.name action.inputs action.inputValues;
    in
    if errors == [] then
      step
    else
      throw ''
        SDK Validation Error in job '${jobName}', step ${toString stepIndex} (${action.name}):
        ${lib.concatStringsSep "\n" (map (e: "  - ${e}") errors)}
      '';

    # Validate all inputs for an action
    validateInputs = actionName: inputDefs: inputValues:
      lib.concatLists (lib.mapAttrsToList (inputName: inputType:
        let
          value = inputValues.${inputName} or null;
        in
        validateInput actionName inputName inputType value
      ) inputDefs);

    # Validate a single input
    validateInput = actionName: inputName: inputType: value:
      # Skip validation for refs (can't validate at eval-time)
      if value == null then
        if types.hasDefault inputType then
          [] # Has default (can be null for optional types), OK
        else
          ["Missing required input '${inputName}'"]
      else if refs.isRef value then
        # Refs are validated at runtime
        []
      else if inputType.evalValidate value then
        []
      else
        ["Input '${inputName}' failed type validation (expected ${inputType.__type})"];

    # Validate all steps in a job
    validateJob = jobName: job:
      let
        steps = job.steps or job.actions or [];
        validatedSteps = lib.imap0 (i: step: validateStep jobName i step) steps;
      in
      job // { steps = validatedSteps; };

    # Validate all jobs
    validatedJobs = lib.mapAttrs validateJob (workflow.jobs or {});

  in
    workflow // { jobs = validatedJobs; };

  # Additional validation utilities

  # Check if step references are valid within a job
  # (This is a more advanced check that ensures stepOutput refs point to real steps)
  validateStepRefs = workflow:
  let
    checkJob = jobName: job:
    let
      steps = job.steps or job.actions or [];
      stepNames = map (s: s.name or null) steps;
      
      checkStep = stepIndex: step:
        if step ? __sdkAction then
          let
            inputValues = step.__sdkAction.inputValues;
            refErrors = lib.concatLists (lib.mapAttrsToList (inputName: value:
              if refs.isRef value && value.__ref == "stepOutput" then
                if builtins.elem value.step stepNames then []
                else ["Step '${step.__sdkAction.name}' references unknown step '${value.step}'"]
              else []
            ) inputValues);
          in
          if refErrors == [] then step
          else throw ''
            SDK Reference Error in job '${jobName}':
            ${lib.concatStringsSep "\n" (map (e: "  - ${e}") refErrors)}
          ''
        else step;
    in
    job // {
      steps = lib.imap0 checkStep steps;
    };
  in
  workflow // {
    jobs = lib.mapAttrs checkJob (workflow.jobs or {});
  };

  # Combined validation: types + references
  fullValidation = workflow:
    validateStepRefs (validation workflow);
}
