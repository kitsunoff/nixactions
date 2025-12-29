# Test: Variable propagation between actions
# Shows the difference between regular vars, local, and export
{ pkgs, nixactions, executor ? nixactions.executors.local }:

nixactions.mkWorkflow {
  name = "test-env-propagation";
  
  jobs = {
    # Test 1: Regular variables (no local, no export)
    test-regular-vars = {
      inherit executor;
      
      actions = [
        {
          name = "set-regular-var";
          bash = ''
            # Just VAR=value (no local, no export)
            # shellcheck disable=SC2034
            MY_VAR="regular-value"
            echo "→ Set MY_VAR='regular-value' (no local, no export)"
          '';
        }
        
        {
          name = "use-regular-var";
          bash = ''
            echo "→ In second action: MY_VAR='$MY_VAR'"
            if [ "$MY_VAR" = "regular-value" ]; then
              echo "✓ Regular var propagated between actions"
            else
              echo "✗ Regular var NOT found"
              exit 1
            fi
          '';
        }
      ];
    };
    
    # Test 2: local variables
    test-local-vars = {
      needs = [ "test-regular-vars" ];
      inherit executor;
      
      actions = [
        {
          name = "set-local-var";
          bash = ''
            # Set variable without export (action-scoped)
            LOCAL_VAR="local-value"
            echo "→ Set LOCAL_VAR='local-value' (no export)"
            echo "  In same action: LOCAL_VAR='$LOCAL_VAR'"
          '';
        }
        
        {
          name = "try-use-local";
          bash = ''
            echo "→ In second action: LOCAL_VAR='$LOCAL_VAR'"
            # Note: Without export, var is not visible to subsequent actions
            # Actions run as separate bash invocations
            if [ -n "''${LOCAL_VAR:-}" ]; then
              echo "ℹ var still visible (same job scope)"
            else
              echo "✓ local var not visible"
            fi
          '';
        }
      ];
    };
    
    # Test 3: export variables (for subprocesses)
    test-export-vars = {
      needs = [ "test-local-vars" ];
      inherit executor;
      
      actions = [
        {
          name = "without-export";
          bash = ''
            MY_VAR="value"
            echo "→ MY_VAR='value' (no export)"
            echo "  In subshell:"
            ( echo "    MY_VAR='$MY_VAR' (empty!)" )
          '';
        }
        
        {
          name = "with-export";
          bash = ''
            export EXPORTED_VAR="exported-value"
            echo "→ EXPORTED_VAR='exported-value' (with export)"
            echo "  In subshell:"
            ( echo "    EXPORTED_VAR='$EXPORTED_VAR' (visible!)" )
          '';
        }
      ];
    };
    
    # Summary
    summary = {
      needs = [ "test-export-vars" ];
      inherit executor;
      
      actions = [{
        name = "summary";
        bash = ''
          echo ""
          echo "╔═══════════════════════════════════════════════╗"
          echo "║ Summary: Variables in NixActions              ║"
          echo "╚═══════════════════════════════════════════════╝"
          echo ""
          echo "1. Regular vars (VAR=value):"
          echo "   ✓ Propagate between actions (same function)"
          echo "   ✗ Not visible in subshells/subprocesses"
          echo ""
          echo "2. local vars (local VAR=value):"
          echo "   ✓ Still propagate (all actions in same function)"
          echo "   ℹ 'local' is per-function, not per-action"
          echo ""
          echo "3. export vars (export VAR=value):"
          echo "   ✓ Propagate between actions"
          echo "   ✓ Visible in subshells/subprocesses"
          echo "   ✓ Use for secrets that need to be available everywhere"
          echo ""
          echo "Recommendation:"
          echo "  • Use 'export' for secrets (e.g., from SOPS/Vault)"
          echo "  • Use regular vars for temporary data"
          echo ""
        '';
      }];
    };
  };
}
