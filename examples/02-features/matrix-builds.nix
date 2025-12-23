# Matrix Builds Example
# Demonstrates compile-time matrix job generation
{ pkgs, platform }:

let
  # Generate matrix jobs for testing across multiple Node.js versions and OSes
  matrixJobs = platform.mkMatrixJobs {
    name = "test";
    
    # Define matrix dimensions
    matrix = {
      node = ["18" "20" "22"];
      os = ["ubuntu" "alpine"];
    };
    
    # Job template - receives matrix variables
    # This function will be called for each combination
    jobTemplate = { node, os }: {
      # Executor can use matrix variables directly
      executor = platform.executors.oci { 
        image = "node:${node}-${os}"; 
      };
      
      actions = [
        {
          name = "test-node-${node}-on-${os}";
          bash = ''
            echo "╔═══════════════════════════════════════╗"
            echo "║ Testing Node.js ${node} on ${os}"
            echo "╚═══════════════════════════════════════╝"
            
            echo ""
            echo "→ Node version:"
            node --version
            
            echo ""
            echo "→ NPM version:"
            npm --version
            
            echo ""
            echo "→ OS Info:"
            cat /etc/os-release | grep PRETTY_NAME || uname -a
            
            echo ""
            echo "→ Running tests..."
            echo "✓ Test suite passed for Node ${node} on ${os}"
          '';
        }
      ];
    };
  };
  
  # You can also create multiple matrix job sets
  buildMatrixJobs = platform.mkMatrixJobs {
    name = "build";
    
    matrix = {
      arch = ["amd64" "arm64"];
      distro = ["debian" "alpine"];
    };
    
    jobTemplate = { arch, distro }: {
      executor = platform.executors.local;
      
      # Jobs can depend on specific matrix jobs
      # Matrix job names follow pattern: <name>-<dim1>-<value1>-<dim2>-<value2>...
      needs = ["test-node-18-os-ubuntu"];  # Waits for one specific matrix test job
      
      outputs = {
        "build-${ arch }-${ distro }" = "build-${arch}-${distro}/";
      };
      
      actions = [
        {
          name = "build-${arch}-${distro}";
          bash = ''
            echo "→ Building for ${arch} on ${distro}"
            
            mkdir -p build-${arch}-${distro}
            echo "Architecture: ${arch}" > build-${arch}-${distro}/BUILD_INFO.txt
            echo "Distro: ${distro}" >> build-${arch}-${distro}/BUILD_INFO.txt
            echo "Built at: $(date)" >> build-${arch}-${distro}/BUILD_INFO.txt
            
            cat build-${arch}-${distro}/BUILD_INFO.txt
          '';
        }
      ];
    };
  };
  
in

platform.mkWorkflow {
  name = "matrix-demo";
  
  # Merge matrix jobs with regular jobs
  jobs = matrixJobs // buildMatrixJobs // {
    # Regular (non-matrix) job that depends on all builds
    deploy = {
      executor = platform.executors.local;
      
      # Depends on all build matrix jobs
      needs = [
        "build-arch-amd64-distro-debian"
        "build-arch-amd64-distro-alpine"
        "build-arch-arm64-distro-debian"
        "build-arch-arm64-distro-alpine"
      ];
      
      # Restore all build artifacts (use processed artifact names, not job names)
      inputs = [
        "build-amd64-debian"
        "build-amd64-alpine"
        "build-arm64-debian"
        "build-arm64-alpine"
      ];
      
      actions = [
        {
          name = "deploy-all-builds";
          bash = ''
            echo "╔═══════════════════════════════════════╗"
            echo "║ Deploying All Matrix Builds           ║"
            echo "╚═══════════════════════════════════════╝"
            
            echo ""
            echo "→ Available artifacts:"
            ls -la
            
            echo ""
            echo "→ Build summaries:"
            for build_dir in build-*; do
              if [ -f "$build_dir/BUILD_INFO.txt" ]; then
                echo ""
                echo "=== $build_dir ==="
                cat "$build_dir/BUILD_INFO.txt"
              fi
            done
            
            echo ""
            echo "✓ All matrix builds deployed successfully"
          '';
        }
      ];
    };
    
    # Summary job that runs after everything
    summary = {
      executor = platform.executors.local;
      
      needs = ["deploy"];
      
      "if" = "always()";  # Run even if previous jobs failed
      
      actions = [
        {
          name = "workflow-summary";
          bash = ''
            echo "╔═══════════════════════════════════════╗"
            echo "║ Matrix Workflow Summary               ║"
            echo "╚═══════════════════════════════════════╝"
            
            echo ""
            echo "Matrix Test Jobs (6 combinations):"
            echo "  • test-node-18-os-ubuntu"
            echo "  • test-node-18-os-alpine"
            echo "  • test-node-20-os-ubuntu"
            echo "  • test-node-20-os-alpine"
            echo "  • test-node-22-os-ubuntu"
            echo "  • test-node-22-os-alpine"
            
            echo ""
            echo "Matrix Build Jobs (4 combinations):"
            echo "  • build-arch-amd64-distro-debian"
            echo "  • build-arch-amd64-distro-alpine"
            echo "  • build-arch-arm64-distro-debian"
            echo "  • build-arch-arm64-distro-alpine"
            
            echo ""
            echo "Regular Jobs:"
            echo "  • deploy"
            echo "  • summary (this job)"
            
            echo ""
            echo "✓ Total: 12 jobs generated from 2 matrix definitions + 2 regular jobs"
          '';
        }
      ];
    };
  };
}
