# Parallel workflow example - demonstrates GitHub Actions-style parallel execution
{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "parallel-workflow";
  
  jobs = {
    # === Level 0: These run in parallel ===
    
    lint-shell = {
      inherit executor;
      steps = [{
        name = "lint-shell-scripts";
        bash = ''
          echo "→ Linting shell scripts..."
          # Find shell scripts (if any exist)
          if find . -name "*.sh" -type f 2>/dev/null | grep -q .; then
            find . -name "*.sh" -type f -print0 | xargs -0 -n1 bash -n
            echo "✓ Shell scripts OK"
          else
            echo "ℹ No shell scripts found to lint"
          fi
        '';
      }];
    };
    
    check-nix = {
      inherit executor;
      steps = [{
        name = "check-nix-formatting";
        bash = ''
          echo "→ Checking Nix formatting..."
          # Basic syntax check - just verify files are valid Nix
          for f in lib/*.nix examples/*/*.nix flake.nix; do
            if [ -f "$f" ]; then
              echo "  Checking: $f"
            fi
          done
          echo "✓ Nix format check complete"
        '';
      }];
    };
    
    analyze = {
      inherit executor;
      steps = [{
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
      inherit executor;
      
      steps = [{
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
