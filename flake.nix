{
  description = "NixActions - Agentless CI/CD platform powered by Nix with GitHub Actions execution model";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit system;
      });
      
      # Discover all example .nix files in a directory
      discoverInDir = pkgs: baseDir: subDir:
        let
          lib = pkgs.lib;
          fullPath = baseDir + "/${subDir}";
          # Check if directory exists
          dirExists = builtins.pathExists fullPath;
          entries = if dirExists then builtins.readDir fullPath else {};
          
          processFile = name: type:
            if type == "regular" && lib.hasSuffix ".nix" name then
              let
                baseName = lib.removeSuffix ".nix" name;
                isTest = lib.hasPrefix "test-" baseName;
                # Skip k8s-specific examples (they don't work with local/oci executors)
                isK8sOnly = lib.hasInfix "k8s" baseName;
              in
              if isK8sOnly then null
              else {
                inherit baseName isTest;
                category = subDir;
                path = fullPath + "/${name}";
              }
            else
              null;
          
          results = lib.filter (x: x != null) (lib.mapAttrsToList processFile entries);
        in
        results;
      
      # Discover all examples across all categories
      discoverAllExamples = pkgs:
        let
          lib = pkgs.lib;
          categories = [ "01-basic" "02-features" "03-real-world" ];
          allExamples = lib.flatten (
            map (cat: discoverInDir pkgs ./examples cat) categories
          );
        in
        allExamples;
      
      # Executor variants for generating packages
      # Note: K8s executors are not included here as they require registry configuration
      # K8s examples are generated separately with a default local registry config
      mkExecutorVariants = nixactions: {
        local = nixactions.executors.local;
        oci-shared = nixactions.executors.oci { mode = "shared"; };
        oci-isolated = nixactions.executors.oci { mode = "isolated"; };
      };
      
      # K8s executor variants (with default local registry for testing)
      mkK8sExecutorVariants = nixactions: {
        k8s-shared = nixactions.executors.k8s {
          namespace = "default";
          registry = {
            url = "localhost:5001";  # Kind local registry port
            usernameEnv = "REGISTRY_USER";
            passwordEnv = "REGISTRY_PASSWORD";
          };
          mode = "shared";
        };
        k8s-dedicated = nixactions.executors.k8s {
          namespace = "default";
          registry = {
            url = "localhost:5001";  # Kind local registry port
            usernameEnv = "REGISTRY_USER";
            passwordEnv = "REGISTRY_PASSWORD";
          };
          mode = "dedicated";
        };
      };
      
    in {
      # Main library API
      lib = forAllSystems ({ pkgs, system }: 
        import ./lib { inherit pkgs; }
      );
      
      # Example packages (auto-discovered with executor variants)
      packages = forAllSystems ({ pkgs, system }:
        let
          nixactions = self.lib.${system};
          lib = pkgs.lib;
          
          # Get executor variants
          executorVariants = mkExecutorVariants nixactions;
          
          # Discover all examples
          examples = discoverAllExamples pkgs;
          
          # Generate packages for each example with each executor variant
          # example-simple-local, example-simple-oci-shared, example-simple-oci-isolated
          generateVariants = ex:
            lib.mapAttrsToList (variantName: executor: {
              name = "example-${ex.baseName}-${variantName}";
              value = import (./examples + "/${ex.category}/${ex.baseName}.nix") { 
                inherit pkgs nixactions executor; 
              };
            }) executorVariants;
          
          # Flatten all variants into a single list
          allVariants = lib.flatten (map generateVariants examples);
          
          # Convert to attribute set
          examplePackages = builtins.listToAttrs allVariants;
          
          # K8s variants - for test-k8s examples (requires special setup)
          k8sExecutorVariants = mkK8sExecutorVariants nixactions;
          
          # Basic K8s test
          k8sExamples = lib.mapAttrs' (variantName: executor: {
            name = "example-test-k8s-${lib.removePrefix "k8s-" variantName}";
            value = import ./examples/02-features/test-k8s.nix {
              inherit pkgs nixactions executor;
            };
          }) k8sExecutorVariants;
          
          # K8s matrix test (10 parallel jobs) - only dedicated mode makes sense
          k8sMatrixExamples = {
            "example-test-k8s-matrix-dedicated" = import ./examples/02-features/test-k8s-matrix.nix {
              inherit pkgs nixactions;
              executor = k8sExecutorVariants.k8s-dedicated;
            };
          };
          
          # K8s env providers test
          k8sEnvProviderExamples = lib.mapAttrs' (variantName: executor: {
            name = "example-test-k8s-env-providers-${lib.removePrefix "k8s-" variantName}";
            value = import ./examples/02-features/test-k8s-env-providers.nix {
              inherit pkgs nixactions executor;
            };
          }) k8sExecutorVariants;
          
        in
        examplePackages // k8sExamples // k8sMatrixExamples // k8sEnvProviderExamples // {
          # Set default to complete-local example
          default = examplePackages."example-complete-local" or examplePackages."example-simple-local" or (builtins.head (builtins.attrValues examplePackages));
        }
      );
      
      # Development shell
      devShells = forAllSystems ({ pkgs, system }: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nix
            nixpkgs-fmt
          ];
          
          shellHook = 
            let
              lib = pkgs.lib;
              
              # Discover examples
              examples = discoverAllExamples pkgs;
              
              # Count total packages (examples * 3 executor variants)
              totalPackages = (builtins.length examples) * 3;
              
              # Format example list (show only local variants for brevity)
              formatExample = ex: "echo \"  nix run .#example-${ex.baseName}-local\"";
              
              allExamplesList = lib.concatStringsSep "\n" (
                map formatExample examples
              );
              
            in ''
              echo "╔═══════════════════════════════════════════════════════╗"
              echo "║ NixActions - Development Environment                  ║"
              echo "╚═══════════════════════════════════════════════════════╝"
              echo ""
              echo "📦 Available examples (${toString (builtins.length examples)} examples × 3 executors = ${toString totalPackages} packages):"
              echo ""
              echo "Each example has 3 variants:"
              echo "  -local        (local executor)"
              echo "  -oci-shared   (OCI executor, shared mode)"
              echo "  -oci-isolated (OCI executor, isolated mode)"
              echo ""
              echo "Examples (showing -local variants):"
              ${allExamplesList}
              echo ""
              echo "💡 More info: nix flake show"
              echo "📚 Documentation: cat README.md"
            '';
        };
      });
    };
}
