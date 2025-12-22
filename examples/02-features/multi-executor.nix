# Multi-Executor Workflow Example
# Demonstrates running jobs across different execution environments
{ pkgs, platform }:

let
  local = platform.executors.local;
  oci = platform.executors.oci { image = "nixos/nix"; };
in

platform.mkWorkflow {
  name = "multi-executor-demo";
  
  jobs = {
    # Job 1: Run on local machine
    build-local = {
      executor = local;
      
      outputs = {
        local-dist = "dist/";
      };
      
      actions = [
        {
          name = "build-local";
          bash = ''
            echo "→ Building application locally"
            mkdir -p dist
            echo "Built on: $(uname -s)" > dist/BUILD_INFO.txt
            echo "Executor: local" >> dist/BUILD_INFO.txt
            echo "Timestamp: $(date)" >> dist/BUILD_INFO.txt
            
            cat dist/BUILD_INFO.txt
          '';
        }
      ];
    };
    
    # Job 2: Run in OCI container
    build-oci = {
      executor = oci;
      
      outputs = {
        oci-dist = "dist/";
      };
      
      actions = [
        {
          name = "build-oci";
          bash = ''
            echo "→ Building application in OCI container"
            mkdir -p dist
            echo "Built on: $(uname -s)" > dist/BUILD_INFO.txt
            echo "Executor: oci (container)" >> dist/BUILD_INFO.txt
            echo "Timestamp: $(date)" >> dist/BUILD_INFO.txt
            
            cat dist/BUILD_INFO.txt
          '';
        }
      ];
    };
    
    # Job 3: Compare builds (runs locally, depends on both)
    compare = {
      executor = local;
      needs = ["build-local" "build-oci"];
      
      inputs = ["local-dist" "oci-dist"];
      
      actions = [
        {
          name = "compare-builds";
          bash = ''
            echo "→ Artifacts restored from both executors"
            
            echo ""
            echo "╔═══════════════════════════════════════════╗"
            echo "║ Build Comparison                          ║"
            echo "╚═══════════════════════════════════════════╝"
            echo ""
            
            echo "Local Build (local-dist/dist/):"
            cat local-dist/dist/BUILD_INFO.txt
            
            echo ""
            echo "OCI Build (oci-dist/dist/):"
            cat oci-dist/dist/BUILD_INFO.txt
            
            echo ""
            echo "✓ Both builds completed successfully"
            echo "✓ Artifacts transferred between executors"
          '';
        }
      ];
    };
  };
}
