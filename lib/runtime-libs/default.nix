# Runtime libraries for NixActions
# These are bash helpers compiled into derivations for use at workflow runtime
{ pkgs, lib }:

{
  # Logging utilities (structured logging functions)
  logging = import ./logging.nix { inherit pkgs lib; };
  
  # Retry utilities (retry wrapper with backoff)
  retry = import ./retry.nix { inherit lib pkgs; };
  
  # Timeout utilities (timeout wrapper)
  timeout = import ./timeout.nix { inherit pkgs lib; };
  
  # Runtime helpers (job execution, conditions, parallel execution)
  runtimeHelpers = import ./runtime-helpers.nix { inherit pkgs lib; };
}
