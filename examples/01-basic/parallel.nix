# Parallel workflow example - demonstrates GitHub Actions-style parallel execution
{ pkgs, platform }:

platform.mkWorkflow {
  name = "parallel-workflow";
  
  jobs = {
    # === Level 0: These run in parallel ===
    
    lint-shell = {
      executor = platform.executors.local;
      actions = [{
        name = "lint-shell-scripts";
        deps = [ pkgs.shellcheck ];
        bash = ''
          echo "→ Linting shell scripts..."
          # Find shell scripts (if any exist)
          if find . -name "*.sh" -type f 2>/dev/null | grep -q .; then
            find . -name "*.sh" -type f -exec shellcheck {} +
            echo "✓ Shell scripts OK"
          else
            echo "ℹ No shell scripts found to lint"
          fi
        '';
      }];
    };
    
    check-nix = {
      executor = platform.executors.local;
      actions = [{
        name = "check-nix-formatting";
        deps = [ pkgs.nixpkgs-fmt ];
        bash = ''
          echo "→ Checking Nix formatting..."
          nixpkgs-fmt --check lib/ examples/ flake.nix || true
          echo "✓ Nix format check complete"
        '';
      }];
    };
    
    analyze = {
      executor = platform.executors.local;
      actions = [{
        name = "analyze-structure";
        bash = ''
          echo "→ Analyzing project structure..."
          echo "Files in lib/:"
          find lib -type f | sort
          echo ""
          echo "Total Nix files:"
          find . -name "*.nix" -type f | wc -l
        '';
      }];
    };
    
    # === Level 1: Runs after level 0 ===
    
    report = {
      needs = [ "lint-shell" "check-nix" "analyze" ];
      executor = platform.executors.local;
      
      actions = [{
        name = "final-report";
        bash = ''
          echo "╔═══════════════════════════════════════╗"
          echo "║ All checks completed successfully!    ║"
          echo "╚═══════════════════════════════════════╝"
          echo ""
          echo "✓ Shell linting passed"
          echo "✓ Nix formatting checked"
          echo "✓ Project analysis complete"
        '';
      }];
    };
  };
}
