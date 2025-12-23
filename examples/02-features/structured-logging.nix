{ pkgs, platform }:

platform.mkWorkflow {
  name = "structured-logging-demo";
  
  # Configure structured logging
  logging = {
    format = "structured";  # "structured", "simple", or "json"
    level = "info";         # "info" or "debug"
  };
  
  jobs = {
    test = {
      executor = platform.executors.local;
      
      actions = [
        {
          name = "checkout";
          bash = ''
            echo "Cloning repository..."
            sleep 1
            echo "Repository cloned successfully"
          '';
        }
        
        {
          name = "install-deps";
          bash = ''
            echo "Installing dependencies..."
            echo "  - package-a v1.2.3"
            echo "  - package-b v4.5.6"
            sleep 1
            echo "Dependencies installed"
          '';
        }
        
        {
          name = "run-tests";
          bash = ''
            echo "Running test suite..."
            echo "  ✓ test_feature_a passed"
            echo "  ✓ test_feature_b passed"
            echo "  ✓ test_feature_c passed"
            sleep 1
            echo "All tests passed!"
          '';
        }
      ];
    };
  };
}
