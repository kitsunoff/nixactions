{ pkgs, nixactions, executor ? nixactions.executors.local }:

# Real-world Node.js CI/CD Pipeline
#
# Demonstrates complete workflow with:
# - Environment providers (file, static, required)
# - Multi-stage pipeline (lint → test → build → deploy)
# - Artifacts (dist files passed between jobs)
# - Conditions (deploy only on main branch)
# - Retry on flaky steps
#
# Usage:
#   # Run full pipeline locally
#   nix run .#example-nodejs-full-pipeline-local
#
#   # Deploy to production (requires BRANCH=main)
#   BRANCH=main DEPLOY_KEY=xxx nix run .#example-nodejs-full-pipeline-local

nixactions.mkWorkflow {
  name = "nodejs-ci-cd";
  
  # Workflow-level environment
  env = {
    CI = "true";
    NODE_ENV = "production";
    BRANCH = "develop";  # Default branch
  };
  
  # TODO: Enable when envFrom is implemented in mk-workflow.nix
  # envFrom = [
  #   (nixactions.envProviders.file { path = ".env.common"; required = false; })
  #   (nixactions.envProviders.static { BRANCH = "develop"; })
  # ];
  
  jobs = {
    # ============================================
    # Stage 1: Fast checks (parallel)
    # ============================================
    
    lint = {
      inherit executor;
      
      steps = [
        {
          name = "install-deps";
          bash = ''
            echo "📦 Installing dependencies..."
            npm install
          '';
          deps = [ pkgs.nodejs ];
        }
        
        {
          name = "install-deps";
          bash = ''
            echo "📦 Installing dependencies..."
            npm install
          '';
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    typecheck = {
      inherit executor;
      
      steps = [
        {
          name = "install-deps";
          bash = ''
            echo "📦 Installing dependencies..."
            npm install
          '';
          deps = [ pkgs.nodejs ];
        }
        
        {
          name = "typescript";
          bash = ''
            echo "📝 Type checking..."
            npm run typecheck
          '';
          deps = [ pkgs.nodejs ];
        }
      ];
    };
    
    # ============================================
    # Stage 2: Tests (after checks pass)
    # ============================================
    
    test = {
      needs = ["lint" "typecheck"];
      inherit executor;
      
      # Test output for coverage
      outputs = {
        coverage = "coverage/";
      };
      
      steps = [
        {
          name = "install-deps";
          bash = ''
            echo "📦 Installing dependencies..."
            npm install
          '';
          deps = [ pkgs.nodejs ];
        }
        
        {
          name = "unit-tests";
          bash = ''
            echo "🧪 Running unit tests..."
            npm test -- --coverage
          '';
          deps = [ pkgs.nodejs ];
          
          # Retry flaky tests
          retry = {
            max_attempts = 3;
            backoff = "exponential";
            min_time = 1;
            max_time = 10;
          };
        }
      ];
    };
    
    # ============================================
    # Stage 3: Build (after tests pass)
    # ============================================
    
    build = {
      needs = ["test"];
      inherit executor;
      
      # Restore coverage for analysis
      inputs = [
        { name = "coverage"; path = "coverage/"; }
      ];
      
      # Build output
      outputs = {
        dist = "dist/";
      };
      
      steps = [
        {
          name = "install-deps";
          bash = ''
            echo "📦 Installing dependencies..."
            npm install
          '';
          deps = [ pkgs.nodejs ];
        }
        
        {
          name = "build";
          bash = ''
            echo "🏗️  Building application..."
            npm run build
            
            echo ""
            echo "📊 Build artifacts:"
            ls -lh dist/
            
            echo ""
            echo "📈 Coverage report available at:"
            ls coverage/ || echo "  (no coverage)"
          '';
          deps = [ pkgs.nodejs pkgs.coreutils ];
        }
      ];
    };
    
    # ============================================
    # Stage 4: Deploy (conditional)
    # ============================================
    
    deploy-staging = {
      needs = ["build"];
      inherit executor;
      
      # Only deploy if NOT main branch
      condition = ''[ "$BRANCH" != "main" ]'';
      
      inputs = [
        { name = "dist"; path = "dist/"; }
      ];
      
      steps = [
        {
          name = "deploy-staging";
          bash = ''
            echo "🚀 Deploying to STAGING..."
            echo "   Branch: $BRANCH"
            echo "   Environment: $NODE_ENV"
            echo ""
            echo "📦 Artifacts to deploy:"
            ls -lh dist/
            echo ""
            echo "✅ Staging deployment complete!"
          '';
          deps = [ pkgs.coreutils ];
        }
      ];
    };
    
    deploy-production = {
      needs = ["build"];
      inherit executor;
      
      # Only deploy on main branch
      condition = ''[ "$BRANCH" = "main" ]'';
      
      # TODO: Enable when envFrom is implemented
      # envFrom = [
      #   (nixactions.envProviders.required ["DEPLOY_KEY"])
      # ];
      
      inputs = [
        { name = "dist"; path = "dist/"; }
      ];
      
      steps = [
        {
          name = "deploy-production";
          bash = ''
            echo "🚀 Deploying to PRODUCTION..."
            echo "   Branch: $BRANCH"
            echo "   Environment: $NODE_ENV"
            echo "   Deploy key: ***"
            echo ""
            echo "📦 Artifacts to deploy:"
            ls -lh dist/
            echo ""
            echo "⚠️  This would deploy to production!"
            echo "   (Actual deployment disabled for safety)"
            echo ""
            echo "✅ Production deployment complete!"
          '';
          deps = [ pkgs.coreutils ];
        }
      ];
    };
    
    # ============================================
    # Stage 5: Notifications (always run)
    # ============================================
    
    notify-success = {
      needs = ["deploy-staging" "deploy-production"];
      condition = "success()";
      inherit executor;
      
      steps = [
        {
          name = "notify";
          condition = "always()";
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Pipeline Success! 🎉                   ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "All stages completed successfully:"
            echo "  ✅ Lint"
            echo "  ✅ Type check"
            echo "  ✅ Tests"
            echo "  ✅ Build"
            if [ "$BRANCH" = "main" ]; then
              echo "  ✅ Production deployment"
            else
              echo "  ✅ Staging deployment"
            fi
            echo ""
          '';
        }
      ];
    };
    
    notify-failure = {
      needs = ["deploy-staging" "deploy-production"];
      condition = "failure()";
      inherit executor;
      
      steps = [
        {
          name = "notify";
          condition = "always()";
          bash = ''
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║ Pipeline Failed! ❌                    ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            echo "One or more stages failed."
            echo "Check logs above for details."
            echo ""
          '';
        }
      ];
    };
  };
}
