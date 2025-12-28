# Shared OCI image building logic for OCI and K8s executors
# Builds Linux container images using dockerTools.streamLayeredImage

{ pkgs, lib, linuxPkgs }:

let
  # Linux pkgs alias
  lpkgs = linuxPkgs;
  
  # Import runtime helpers - use linuxPkgs for container content
  loggingLib = import ../logging.nix { pkgs = linuxPkgs; inherit lib; };
  retryLib = import ../retry.nix { pkgs = linuxPkgs; inherit lib; };
  runtimeHelpers = import ../runtime-helpers.nix { pkgs = linuxPkgs; inherit lib; };
  timeoutLib = import ../timeout.nix { pkgs = linuxPkgs; inherit lib; };
  
  # Helper to convert a package from host system to Linux
  # Uses pname lookup in lpkgs, with explicit error if not found
  toLinuxPkg = hostPkg:
    let
      pname = hostPkg.pname or (builtins.baseNameOf hostPkg);
    in
    if lpkgs ? ${pname} then lpkgs.${pname}
    else if hostPkg ? passthru.linuxEquivalent then hostPkg.passthru.linuxEquivalent
    else builtins.throw "Cannot find Linux equivalent for package '${pname}'. Use extraPackages with Linux packages from linuxPkgs.";
  
  # Helper to create unique action name based on content hash
  # This ensures multiple actions with same name but different code get unique derivations
  mkUniqueActionName = actionName: actionBash: actionDeps:
    let
      contentHash = builtins.substring 0 8 (builtins.hashString "sha256" 
        (actionBash + builtins.concatStringsSep "," (map toString actionDeps)));
    in "${actionName}-${contentHash}";
  
  # Rebuild actions for Linux
  # Returns list of Linux action derivations with passthru metadata
  buildLinuxActions = actionDerivations:
    map (action:
      let
        actionName = action.passthru.name or (builtins.baseNameOf action);
        actionBash = action.passthru.bash or null;
        actionDeps = action.passthru.deps or [];
        
        # Convert all deps to Linux versions
        linuxDeps = map toLinuxPkg actionDeps;
        
        # Use unique name to avoid conflicts in container image
        uniqueName = mkUniqueActionName actionName actionBash actionDeps;
      in
      if actionBash != null then
        lpkgs.writeShellApplication {
          name = uniqueName;
          runtimeInputs = linuxDeps;
          text = actionBash;
        } // {
          passthru = action.passthru // {
            deps = linuxDeps;
            originalName = actionName;
          };
        }
      else
        builtins.throw "Action '${actionName}' has no bash source (passthru.bash). Cannot rebuild for Linux container."
    ) actionDerivations;

in rec {
  # Export helpers for use by executors
  inherit toLinuxPkg mkUniqueActionName buildLinuxActions;
  inherit loggingLib retryLib runtimeHelpers timeoutLib;
  inherit lpkgs;
  
  # Build OCI image from action derivations
  # Returns: { imageName, imageTag, imageTarball }
  buildExecutorImage = { 
    actionDerivations,
    executorName,
    extraPackages ? [],
    containerEnv ? {},
  }: 
    let
      # Rebuild actions for Linux
      linuxActionDerivations = buildLinuxActions actionDerivations;
      
      # Convert extraPackages to Linux versions
      linuxExtraPackages = map toLinuxPkg extraPackages;
      
      # Collect Linux deps from all actions
      linuxAllDeps = lib.unique (lib.flatten (
        map (action: action.passthru.deps or []) linuxActionDerivations
      ));
      
      # Generate unique tag based on content hash
      contentForHash = builtins.concatStringsSep "\n" (
        map toString (linuxActionDerivations ++ linuxAllDeps ++ linuxExtraPackages)
      );
      imageTag = builtins.substring 0 12 (builtins.hashString "sha256" contentForHash);
      
      # Use streamLayeredImage to create a script that generates the image
      streamScript = pkgs.dockerTools.streamLayeredImage {
        name = "nixactions-${executorName}";
        tag = imageTag;
        
        # Architecture for the image
        architecture = if lpkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
        
        contents = [
          # Base utilities (Linux)
          lpkgs.bash
          lpkgs.coreutils
          lpkgs.findutils
          lpkgs.gnugrep
          lpkgs.gnused
          lpkgs.gawk
          lpkgs.gnutar  # Required for kubectl cp
          
          # For bc in timing calculations
          lpkgs.bc
          
          # Runtime helpers (derivations) - already built with linuxPkgs
          loggingLib.loggingHelpers
          retryLib.retryHelpers
          runtimeHelpers
          timeoutLib.timeoutHelpers
          
          # All action derivations (rebuilt for Linux)
        ] ++ linuxActionDerivations ++ linuxAllDeps ++ linuxExtraPackages;
        
        config = {
          Cmd = [ "${lpkgs.coreutils}/bin/sleep" "infinity" ];
          WorkingDir = "/workspace";
          Env = [
            "PATH=${lpkgs.bash}/bin:${lpkgs.coreutils}/bin:${lpkgs.findutils}/bin:${lpkgs.gnugrep}/bin:${lpkgs.gnused}/bin:${lpkgs.gawk}/bin:${lpkgs.gnutar}/bin:${lpkgs.bc}/bin:/bin"
            "NIXACTIONS_LOG_FORMAT=structured"
          ] ++ (lib.mapAttrsToList (k: v: "${k}=${toString v}") containerEnv);
        };
      };
      
      # Pre-build the image tarball at nix build time (not runtime)
      imageTarball = pkgs.runCommand "nixactions-${executorName}.tar.gz" {
        nativeBuildInputs = [ pkgs.gzip ];
      } ''
        ${streamScript} | gzip > $out
      '';
    in
    {
      imageName = "nixactions-${executorName}";
      inherit imageTag imageTarball linuxActionDerivations;
    };
}
