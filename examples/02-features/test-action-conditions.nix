# Test: Action conditions
# Demonstrates success(), failure(), always(), and bash script conditions

{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "test-action-conditions";
  
  jobs = {
    # Test 1: success() condition (default)
    test-success = {
      inherit executor;
      actions = [
        {
          name = "action1-succeeds";
          bash = "echo 'Action 1: SUCCESS'";
        }
        {
          name = "action2-with-success-condition";
          bash = "echo 'Action 2: Should run (condition: success())'; echo 'Previous action succeeded'";
          condition = "success()";
        }
      ];
    };
    
    # Test 2: failure() condition
    test-failure = {
      needs = ["test-success"];
      inherit executor;
      continue-on-error = true;  # This job is expected to fail
      actions = [
        {
          name = "action1-fails";
          bash = "echo 'Action 1: FAILING'; exit 1";
        }
        {
          name = "action2-success-should-skip";
          bash = "echo 'Action 2: Should NOT run (previous failed)'; exit 1";
          condition = "success()";
        }
        {
          name = "action3-failure-should-run";
          bash = "echo 'Action 3: Should run (condition: failure())'; echo 'Cleanup after failure'";
          condition = "failure()";
        }
      ];
    };
    
    # Test 3: always() condition
    test-always = {
      needs = ["test-failure"];
      inherit executor;
      continue-on-error = true;  # This job is expected to fail
      actions = [
        {
          name = "action1-fails";
          bash = "echo 'Action 1: FAILING'; exit 1";
        }
        {
          name = "action2-always-runs";
          bash = "echo 'Action 2: ALWAYS runs (condition: always())'; echo 'Cleanup or notification'";
          condition = "always()";
        }
      ];
    };
    
    # Test 4: bash script conditions
    test-bash-conditions = {
      needs = ["test-always"];
      inherit executor;
      env = {
        ENVIRONMENT = "production";
        DEPLOY_ENABLED = "true";
      };
      actions = [
        {
          name = "setup";
          bash = "echo 'Setup completed'";
        }
        {
          name = "deploy-to-production";
          bash = "echo 'Deploying to production...'; echo 'Deploy complete!'";
          condition = ''[ "$ENVIRONMENT" = "production" ]'';
        }
        {
          name = "deploy-to-staging";
          bash = "echo 'Deploying to staging...'; exit 1";
          condition = ''[ "$ENVIRONMENT" = "staging" ]'';
        }
        {
          name = "notify-if-deploy-enabled";
          bash = "echo 'Sending notification (DEPLOY_ENABLED=true)'";
          condition = ''[ "$DEPLOY_ENABLED" = "true" ]'';
        }
      ];
    };
    
    # Test 5: complex scenario
    test-complex = {
      needs = ["test-bash-conditions"];
      inherit executor;
      continue-on-error = true;  # This job is expected to fail
      actions = [
        {
          name = "build";
          bash = "echo 'Building...'; echo 'Build complete'";
        }
        {
          name = "test";
          bash = "echo 'Running tests...'; echo 'Tests FAILED'; exit 1";
        }
        {
          name = "deploy-on-success";
          bash = "echo 'This should NOT run'; exit 1";
          condition = "success()";
        }
        {
          name = "notify-on-failure";
          bash = "echo 'Sending failure notification'; echo 'Notification sent'";
          condition = "failure()";
        }
        {
          name = "cleanup";
          bash = "echo 'Cleaning up workspace'; echo 'Cleanup complete'";
          condition = "always()";
        }
      ];
    };
  };
}
