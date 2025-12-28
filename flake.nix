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
              in
              {
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
      mkExecutorVariants = platform: {
        local = platform.executors.local;
        oci-shared = platform.executors.oci { mode = "shared"; };
        oci-isolated = platform.executors.oci { mode = "isolated"; };
      };
      
    in {
      # Main library API
      lib = forAllSystems ({ pkgs, system }: 
        import ./lib { inherit pkgs; }
      );
      
      # Example packages (auto-discovered with executor variants)
      packages = forAllSystems ({ pkgs, system }:
        let
          platform = self.lib.${system};
          lib = pkgs.lib;
          
          # Get executor variants
          executorVariants = mkExecutorVariants platform;
          
          # Discover all examples
          examples = discoverAllExamples pkgs;
          
          # Generate packages for each example with each executor variant
          # example-simple-local, example-simple-oci-shared, example-simple-oci-isolated
          generateVariants = ex:
            lib.mapAttrsToList (variantName: executor: {
              name = "example-${ex.baseName}-${variantName}";
              value = import (./examples + "/${ex.category}/${ex.baseName}.nix") { 
                inherit pkgs platform executor; 
              };
            }) executorVariants;
          
          # Flatten all variants into a single list
          allVariants = lib.flatten (map generateVariants examples);
          
          # Convert to attribute set
          examplePackages = builtins.listToAttrs allVariants;
          
        in
        examplePackages // {
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
