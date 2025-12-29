{ lib, pkgs }:

rec {
  # Generate bash code for executing a single action
  # This is shared logic between all executors (local, OCI, etc.)
  #
  # Parameters:
  #   action: action derivation with passthru metadata
  #   jobName: name of the parent job
  #   actionBinary: path to action binary (e.g., "${action}/bin/${actionName}")
  #                 (executor-specific: local runs directly, OCI same path but inside container)
  #   timingCommand: optional custom timing command (defaults to 'date +%s%N')
  generateActionExecution = { 
    action,
    jobName,
    actionBinary,
    timingCommand ? "date +%s%N 2>/dev/null || echo \"0\"",
  }:
    let
      runtimeLibs = import ../runtime-libs { inherit lib pkgs; };
      retryLib = runtimeLibs.retry;
      timeoutLib = runtimeLibs.timeout;
      # For display: prefer passthru.name, then derivation name, then baseNameOf outPath
      actionName = action.passthru.name or action.name or (builtins.baseNameOf action);
      rawCondition = action.passthru.condition or null;
      actionCondition = if rawCondition != null then rawCondition else "success()";
      actionRetry = action.passthru.retry or null;
      actionTimeout = action.passthru.timeout or null;
      retryEnv = retryLib.retryToEnv actionRetry;
      timeoutEnv = timeoutLib.timeoutToEnv actionTimeout;
      actionEnv = action.passthru.env or {};
    in ''
      # Set action-level environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") actionEnv
      )}
      # Set retry environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") retryEnv
      )}
      # Set timeout environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") timeoutEnv
      )}
      run_action "${jobName}" "${actionName}" "${actionBinary}" '${actionCondition}' '${timingCommand}'
    '';
}
