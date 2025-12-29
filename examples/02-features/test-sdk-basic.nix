# Test SDK: Typed Actions with Validation
#
# This example demonstrates:
# - defineAction for creating typed actions
# - Type definitions for inputs/outputs
# - stepOutput references between actions
# - Validation extension for eval-time checks
#
# Run: nix build .#example-test-sdk-basic-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  sdk = nixactions.sdk;
  types = sdk.types;

  # Define a typed action: greet
  greet = sdk.mkAction {
    name = "greet";
    description = "Generate a greeting message";
    inputs = {
      name = types.string;
      style = types.withDefault (types.enum [ "formal" "casual" ]) "casual";
    };
    outputs = {
      message = types.string;
    };
    run = ''
      if [ "$INPUT_style" = "formal" ]; then
        OUTPUT_message="Good day, $INPUT_name. How do you do?"
      else
        OUTPUT_message="Hey $INPUT_name! What's up?"
      fi
      echo "Generated greeting: $OUTPUT_message"
    '';
  };

  # Define a typed action: announce
  announce = sdk.mkAction {
    name = "announce";
    description = "Announce a message loudly";
    inputs = {
      message = types.string;
      times = types.withDefault types.int 1;
    };
    run = ''
      echo "=== ANNOUNCEMENT ==="
      # shellcheck disable=SC2034
      for _i in $(seq 1 $INPUT_times); do
        echo ">>> $INPUT_message <<<"
      done
      echo "===================="
    '';
  };

  # Define an action with optional input
  optionalDemo = sdk.mkAction {
    name = "optional-demo";
    inputs = {
      required = types.string;
      optional = types.optional types.string;
    };
    run = ''
      echo "Required: $INPUT_required"
      if [ -n "$INPUT_optional" ]; then
        echo "Optional: $INPUT_optional"
      else
        echo "Optional: (not provided)"
      fi
    '';
  };

  # Define action using fromEnv - input from environment variable
  envDemo = sdk.mkAction {
    name = "env-demo";
    inputs = {
      prefix = types.string;
      customValue = types.string;  # Will be passed via fromEnv
    };
    run = ''
      echo "$INPUT_prefix: customValue=$INPUT_customValue"
    '';
  };

in nixactions.mkWorkflow {
  name = "test-sdk-basic";
  
  # Enable SDK validation
  extensions = [ sdk.validation ];
  
  jobs = {
    # Test basic typed actions
    basic = {
      inherit executor;
      steps = [
        # Greet casually (default style)
        (greet { name = "World"; as = "greet-casual"; })
        
        # Greet formally (using `as` to give unique step name)
        (greet { name = "Professor"; style = "formal"; as = "greet-formal"; })
        
        # Use output from the formal greeting step
        (announce { 
          message = sdk.stepOutput "greet-formal" "message";
          times = 3;
        })
      ];
    };
    
    # Test optional inputs
    optional = {
      inherit executor;
      steps = [
        (optionalDemo { required = "This is required"; })
        (optionalDemo { required = "With optional"; optional = "This is optional"; })
      ];
    };
    
    # Test environment references with fromEnv
    environment = {
      inherit executor;
      env = {
        CUSTOM_VAR = "Hello from env";
        ANOTHER_VAR = "Second value";
      };
      steps = [
        # Use fromEnv to pass environment variable to typed action
        (envDemo { 
          prefix = "Test fromEnv"; 
          customValue = sdk.fromEnv "CUSTOM_VAR";
        })
        # Another test with different env var
        (envDemo { 
          prefix = "Another test"; 
          customValue = sdk.fromEnv "ANOTHER_VAR";
        })
      ];
    };
  };
}
