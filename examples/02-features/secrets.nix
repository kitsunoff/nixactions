# Secrets management example - demonstrates environment variables and validation
{ pkgs, platform }:

platform.mkWorkflow {
  name = "secrets-workflow";
  
  # Workflow-level secrets (can be overridden at runtime)
  env = {
    APP_NAME = "nixactions-demo";
    ENVIRONMENT = "staging";
  };
  
  jobs = {
    # Demonstrate environment variable usage
    validate-env = {
      executor = platform.executors.local;
      
      # Job-level environment
      env = {
        DATABASE_HOST = "localhost";
        DATABASE_PORT = "5432";
      };
      
      # Use env-providers to validate required variables
      envProviders = [
        (platform.envProviders.required [ 
          "APP_NAME" 
          "ENVIRONMENT"
          "DATABASE_HOST"
          "DATABASE_PORT"
        ])
      ];
      
      actions = [
        {
          name = "show-config";
          bash = ''
            echo "→ Application Configuration:"
            echo "  App Name: $APP_NAME"
            echo "  Environment: $ENVIRONMENT"
            echo "  Database: $DATABASE_HOST:$DATABASE_PORT"
          '';
        }
      ];
    };
    
    # Demonstrate runtime environment override
    use-runtime-env = {
      needs = [ "validate-env" ];
      executor = platform.executors.local;
      
      actions = [
        {
          name = "check-optional-secrets";
          bash = ''
            echo "→ Checking for optional secrets..."
            
            # API_KEY is optional - can be set at runtime
            if [ -n "''${API_KEY:-}" ]; then
              echo "✓ API_KEY is set (value hidden)"
            else
              echo "ℹ API_KEY not set (optional)"
            fi
            
            # DB_PASSWORD is optional - can be set at runtime
            if [ -n "''${DB_PASSWORD:-}" ]; then
              echo "✓ DB_PASSWORD is set (value hidden)"
            else
              echo "ℹ DB_PASSWORD not set (optional)"
            fi
          '';
        }
      ];
    };
    
    # Demonstrate action-level environment override
    override-env = {
      needs = [ "use-runtime-env" ];
      executor = platform.executors.local;
      
      # Job environment
      env = {
        LOG_LEVEL = "info";
      };
      
      actions = [
        {
          name = "default-log-level";
          bash = ''
            echo "→ Using default log level: $LOG_LEVEL"
          '';
        }
        
        {
          name = "override-log-level";
          # Action environment overrides job environment
          env = {
            LOG_LEVEL = "debug";
          };
          bash = ''
            echo "→ Using overridden log level: $LOG_LEVEL"
          '';
        }
        
        {
          name = "back-to-default";
          bash = ''
            echo "→ Back to job default: $LOG_LEVEL"
          '';
        }
      ];
    };
    
    # Example: How secrets would be used in deployment
    deploy-with-secrets = {
      needs = [ "override-env" ];
      executor = platform.executors.local;
      
      # Job-level environment for this deployment
      env = {
        DEPLOY_TARGET = "staging-cluster";
      };
      
      actions = [
        {
          name = "simulate-deployment";
          bash = ''
            echo "→ Simulating deployment with secrets..."
            echo ""
            echo "Configuration:"
            echo "  App: $APP_NAME"
            echo "  Env: $ENVIRONMENT"
            echo "  Target: $DEPLOY_TARGET"
            echo ""
            
            # In real scenario, secrets would be loaded from:
            # - SOPS: envProviders = [ (platform.envProviders.sops { file = ./secrets.sops.yaml; }) ];
            # - File: envProviders = [ (platform.envProviders.file { path = ./.env.secrets; }) ];
            # - Static: envProviders = [ (platform.envProviders.static { API_KEY = "xxx"; }) ];
            # - Runtime: API_KEY=xxx nix run .#deploy
            
            echo "In production, this would:"
            echo "  1. Load secrets from secrets manager"
            echo "  2. Validate all required secrets are present"
            echo "  3. Deploy application with secrets"
            echo "  4. Never log secret values"
            echo ""
            echo "✓ Deployment simulation complete"
          '';
        }
      ];
    };
    
    # Final report
    report = {
      needs = [ "deploy-with-secrets" ];
      "if" = "always()";
      executor = platform.executors.local;
      
      actions = [{
        name = "secrets-demo-report";
        bash = ''
          echo ""
          echo "╔═══════════════════════════════════════════════════════════╗"
          echo "║ Secrets Management Demo Complete                          ║"
          echo "╚═══════════════════════════════════════════════════════════╝"
          echo ""
          echo "Key features demonstrated:"
          echo "  ✓ Workflow-level environment variables"
          echo "  ✓ Job-level environment variables"
          echo "  ✓ Action-level environment overrides"
          echo "  ✓ Environment variable validation (envProviders.required)"
          echo "  ✓ Runtime environment override support"
          echo ""
          echo "To test runtime override:"
          echo "  $ API_KEY=secret123 DB_PASSWORD=pass456 nix run .#example-secrets"
          echo ""
          echo "For production secrets, use envProviders:"
          echo "  • SOPS (encrypted files): platform.envProviders.sops"
          echo "  • File (.env files): platform.envProviders.file"
          echo "  • Static (hardcoded): platform.envProviders.static"
          echo "  • Required (validation): platform.envProviders.required"
          echo ""
        '';
      }];
    };
  };
}
