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
          entries = builtins.readDir fullPath;
          
          processFile = name: type:
            if type == "regular" && lib.hasSuffix ".nix" name then
              let
                baseName = lib.removeSuffix ".nix" name;
                packageName = "example-${baseName}";
                isTest = lib.hasPrefix "test-" baseName;
              in
              {
                inherit packageName baseName isTest;
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
          categories = [ "01-basic" "02-features" "03-real-world" "99-untested" ];
          allExamples = lib.flatten (
            map (cat: discoverInDir pkgs ./examples cat) categories
          );
        in
        allExamples;
      
    in {
      # Main library API
      lib = forAllSystems ({ pkgs, system }: 
        import ./lib { inherit pkgs; }
      );
      
      # Example packages (auto-discovered)
      packages = forAllSystems ({ pkgs, system }:
        let
          platform = self.lib.${system};
          lib = pkgs.lib;
          
          # Discover all examples
          examples = discoverAllExamples pkgs;
          
          # Convert to packages
          examplePackages = builtins.listToAttrs (
            map (ex: {
              name = ex.packageName;
              value = import (./examples + "/${ex.category}/${ex.baseName}.nix") { inherit pkgs platform; };
            }) examples
          );
          
        in
        examplePackages // {
          # Set default to complete example
          default = examplePackages.example-complete or examplePackages.example-simple or (builtins.head (builtins.attrValues examplePackages));
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
              
              # Separate regular examples and tests
              regularExamples = lib.filter (ex: !ex.isTest) examples;
              testExamples = lib.filter (ex: ex.isTest) examples;
              
              # Get featured examples (first 6 non-test examples)
              featuredExamples = lib.take 6 regularExamples;
              
              # Format example list
              formatExample = ex: "  nix run .#${ex.packageName}";
              
              featuredList = lib.concatStringsSep "\n" (
                map formatExample featuredExamples
              );
              
              testsList = lib.concatStringsSep "\n" (
                map formatExample testExamples
              );
              
            in ''
              echo "╔═══════════════════════════════════════════════════════╗"
              echo "║ NixActions - Development Environment                  ║"
              echo "╚═══════════════════════════════════════════════════════╝"
              echo ""
              echo "📦 Discovered ${toString (builtins.length examples)} examples (${toString (builtins.length regularExamples)} examples, ${toString (builtins.length testExamples)} tests)"
              echo ""
              echo "Featured Examples:"
              ${featuredList}
              echo ""
              echo "Tests:"
              ${testsList}
              echo ""
              echo "💡 List all: nix flake show"
              echo "📚 Docs: cat README.md"
            '';
        };
      });
    };
}
