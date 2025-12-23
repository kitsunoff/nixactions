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
      
    in {
      # Main library API
      lib = forAllSystems ({ pkgs, system }: 
        import ./lib { inherit pkgs; }
      );
      
      # Example packages
      packages = forAllSystems ({ pkgs, system }:
        let
          platform = self.lib.${system};
        in {
          # ===== 01-basic: Core patterns =====
          
          # Example: Simple CI workflow
          example-simple = import ./examples/01-basic/simple.nix { inherit pkgs platform; };
          
          # Example: Parallel workflow
          example-parallel = import ./examples/01-basic/parallel.nix { inherit pkgs platform; };
          
          # Example: Environment variable sharing between actions
          example-env-sharing = import ./examples/01-basic/env-sharing.nix { inherit pkgs platform; };
          
          # ===== 02-features: Advanced capabilities =====
          
          # Example: Action-level conditions
          example-test-action-conditions = import ./examples/02-features/test-action-conditions.nix { inherit pkgs platform; };
          
          # Example: Artifacts - declarative API
          example-artifacts = import ./examples/02-features/artifacts-simple.nix { inherit pkgs platform; };
          
          # Example: Artifacts with nested paths
          example-artifacts-paths = import ./examples/02-features/artifacts-paths.nix { inherit pkgs platform; };
          
          # Example: Secrets management
          example-secrets = import ./examples/02-features/secrets.nix { inherit pkgs platform; };
          
          # Example: Dynamic package loading with nixShell
          example-nix-shell = import ./examples/02-features/nix-shell.nix { inherit pkgs platform; };
          
          # Example: Multi-executor workflow (local + OCI)
          example-multi-executor = import ./examples/02-features/multi-executor.nix { inherit pkgs platform; };
          
          # Example: Test environment propagation
          example-test-env = import ./examples/02-features/test-env.nix { inherit pkgs platform; };
          
          # Example: Test job isolation
          example-test-isolation = import ./examples/02-features/test-isolation.nix { inherit pkgs platform; };
          
          # Example: Structured logging
          example-structured-logging = import ./examples/02-features/structured-logging.nix { inherit pkgs platform; };
          
          # Example: Matrix builds (compile-time job generation)
          example-matrix-builds = import ./examples/02-features/matrix-builds.nix { inherit pkgs platform; };
          
          # ===== 03-real-world: Production pipelines =====
          
          # Example: Complete CI/CD pipeline
          example-complete = import ./examples/03-real-world/complete.nix { inherit pkgs platform; };
          
          # Example: Python CI/CD pipeline
          example-python-ci = import ./examples/03-real-world/python-ci.nix { inherit pkgs platform; };
          
          # Example: Python CI (simplified)
          example-python-ci-simple = import ./examples/03-real-world/python-ci-simple.nix { inherit pkgs platform; };
          
          # ===== 99-untested: Not validated yet =====
          
          # Example: Docker executor (NOT TESTED)
          example-docker-ci = import ./examples/99-untested/docker-ci.nix { inherit pkgs platform; };
          
          # Example: Artifacts with OCI executor (NOT TESTED)
          example-artifacts-oci = import ./examples/99-untested/artifacts-simple-oci.nix { inherit pkgs platform; };
          
          # Example: Artifacts with OCI build mode (NOT TESTED)
          example-artifacts-oci-build = import ./examples/99-untested/artifacts-oci-build.nix { inherit pkgs platform; };
          
          # Example: Artifacts paths with OCI (NOT TESTED)
          example-artifacts-paths-oci = import ./examples/99-untested/artifacts-paths-oci.nix { inherit pkgs platform; };
          
          # Set default to complete example
          default = self.packages.${system}.example-complete;
        }
      );
      
      # Development shell
      devShells = forAllSystems ({ pkgs, system }: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nix
            nixpkgs-fmt
          ];
          
          shellHook = ''
            echo "NixActions development environment"
            echo "Run: nix run .#example-simple"
            echo "     nix run .#example-parallel"
            echo "     nix run .#example-complete"
            echo "     nix run .#example-secrets"
            echo "     nix run .#example-test-env"
            echo "     nix run .#example-env-sharing"
            echo "     nix run .#example-test-isolation"
            echo "     nix run .#example-python-ci"
            echo "     nix run .#example-nix-shell"
            echo "     nix run .#example-artifacts"
            echo "     nix run .#example-multi-executor"
            echo "     nix run .#example-matrix-builds"
          '';
        };
      });
    };
}
