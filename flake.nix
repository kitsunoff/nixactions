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
          # Example: Simple CI workflow
          example-simple = import ./examples/simple.nix { inherit pkgs platform; };
          
          # Example: Parallel workflow
          example-parallel = import ./examples/parallel.nix { inherit pkgs platform; };
          
          # Example: Complete CI/CD pipeline
          example-complete = import ./examples/complete.nix { inherit pkgs platform; };
          
          # Example: Secrets management
          example-secrets = import ./examples/secrets.nix { inherit pkgs platform; };
          
          # Example: Test environment propagation
          example-test-env = import ./examples/test-env.nix { inherit pkgs platform; };
          
          # Example: Environment variable sharing between actions
          example-env-sharing = import ./examples/env-sharing.nix { inherit pkgs platform; };
          
          # Example: Test job isolation
          example-test-isolation = import ./examples/test-isolation.nix { inherit pkgs platform; };
          
          # Example: Python CI/CD pipeline
          example-python-ci = import ./examples/python-ci.nix { inherit pkgs platform; };
          
          # Example: Python CI (simplified, shows job isolation)
          example-python-ci-simple = import ./examples/python-ci-simple.nix { inherit pkgs platform; };
          
          # Example: Docker executor
          example-docker-ci = import ./examples/docker-ci.nix { inherit pkgs platform; };
          
          # Example: Dynamic package loading with nixShell
          example-nix-shell = import ./examples/nix-shell.nix { inherit pkgs platform; };
          
          # Example: Artifacts - declarative API
          example-artifacts = import ./examples/artifacts-simple.nix { inherit pkgs platform; };
          
          # Example: Artifacts with nested paths
          example-artifacts-paths = import ./examples/artifacts-paths.nix { inherit pkgs platform; };
          
          # Example: Artifacts with OCI executor (mount mode)
          example-artifacts-oci = import ./examples/artifacts-simple-oci.nix { inherit pkgs platform; };
          
          # Example: Artifacts with OCI executor (build mode)
          example-artifacts-oci-build = import ./examples/artifacts-oci-build.nix { inherit pkgs platform; };
          
          # Example: Artifacts with nested paths in OCI
          example-artifacts-paths-oci = import ./examples/artifacts-paths-oci.nix { inherit pkgs platform; };
          
          # Example: Multi-executor workflow (local + OCI)
          example-multi-executor = import ./examples/multi-executor.nix { inherit pkgs platform; };
          
          # Example: Test action conditions
          example-test-action-conditions = import ./examples/test-action-conditions.nix { inherit pkgs platform; };
          
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
          '';
        };
      });
    };
}
