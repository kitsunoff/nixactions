# NixActions SDK - typed actions with eval-time validation
#
# The SDK provides:
# - Type definitions for action inputs/outputs
# - Reference markers for runtime values (step outputs, env vars)
# - defineAction for creating typed actions
# - Validation extension for mkWorkflow
#
# Usage:
#   let
#     sdk = nixactions.sdk;
#     types = sdk.types;
#
#     buildImage = sdk.defineAction {
#       name = "build-image";
#       inputs = {
#         registry = types.string;
#         tag = types.withDefault types.string "latest";
#       };
#       outputs = {
#         imageRef = types.string;
#       };
#       run = ''
#         IMAGE="$INPUT_registry:$INPUT_tag"
#         buildah build -t "$IMAGE" .
#         OUTPUT_imageRef="$IMAGE"
#       '';
#     };
#
#     pushImage = sdk.defineAction {
#       name = "push-image";
#       inputs = {
#         imageRef = types.string;
#       };
#       run = ''
#         buildah push "$INPUT_imageRef"
#       '';
#     };
#   in
#   nixactions.mkWorkflow {
#     extensions = [ sdk.validation ];
#     jobs.build = {
#       executor = executors.local;
#       steps = [
#         (buildImage { registry = "ghcr.io/myorg"; tag = "v1.0"; })
#         (pushImage { imageRef = sdk.stepOutput "build-image" "imageRef"; })
#       ];
#     };
#   }
{ lib }:

let
  typesMod = import ./types.nix { inherit lib; };
  refsMod = import ./refs.nix { inherit lib; };
  defineActionMod = import ./define-action.nix { inherit lib; };
  validationMod = import ./validation.nix { inherit lib; };
in
{
  # Type definitions
  types = typesMod;

  # Reference constructors
  stepOutput = refsMod.stepOutput;
  fromEnv = refsMod.fromEnv;
  matrix = refsMod.matrix;

  # Reference utilities (for advanced use)
  refs = refsMod;

  # Action definition
  mkAction = defineActionMod.defineAction;
  simpleAction = defineActionMod.simpleAction;
  fromScript = defineActionMod.fromScript;

  # Validation extensions
  validation = validationMod.validation;
  fullValidation = validationMod.fullValidation;
  validateStepRefs = validationMod.validateStepRefs;
}
