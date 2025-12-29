# Test SDK References: stepOutput, fromEnv, matrix
#
# This example tests all reference types in the SDK:
# - stepOutput: pass data between steps in same job
# - fromEnv: use environment variables as inputs
# - matrix: use matrix values (tested separately)
#
# Note: jobOutput requires job output mechanism which uses artifacts,
#       not environment variables. See test-sdk-jobs.nix for cross-job tests.
#
# Run: nix build .#example-test-sdk-refs-local && ./result/bin/workflow
{ pkgs, nixactions, executor ? nixactions.executors.local {} }:

let
  sdk = nixactions.sdk;
  types = sdk.types;

  # === Actions for testing ===

  # Action that produces multiple outputs
  produce = sdk.mkAction {
    name = "produce";
    inputs = {
      prefix = types.string;
    };
    outputs = {
      valueA = types.string;
      valueB = types.string;
      combined = types.string;
    };
    run = ''
      OUTPUT_valueA="$INPUT_prefix-AAA"
      OUTPUT_valueB="$INPUT_prefix-BBB"
      OUTPUT_combined="$INPUT_prefix-AAA+BBB"
      echo "Produced: valueA=$OUTPUT_valueA, valueB=$OUTPUT_valueB, combined=$OUTPUT_combined"
    '';
  };

  # Action that consumes outputs
  consume = sdk.mkAction {
    name = "consume";
    inputs = {
      a = types.string;
      b = types.string;
    };
    run = ''
      echo "Consumed: a=$INPUT_a, b=$INPUT_b"
      if [ "$INPUT_a" = "TEST-AAA" ] && [ "$INPUT_b" = "TEST-BBB" ]; then
        echo "SUCCESS: Values match expected!"
      else
        echo "FAILURE: Values don't match expected"
        exit 1
      fi
    '';
  };

  # Action that uses combined value
  useCombined = sdk.mkAction {
    name = "use-combined";
    inputs = {
      value = types.string;
    };
    run = ''
      echo "Using combined: $INPUT_value"
      if [ "$INPUT_value" = "TEST-AAA+BBB" ]; then
        echo "SUCCESS: Combined value matches!"
      else
        echo "FAILURE: Combined value doesn't match"
        exit 1
      fi
    '';
  };

  # Action that uses environment variables
  useEnv = sdk.mkAction {
    name = "use-env";
    inputs = {
      fromStatic = types.string;
      fromProvider = types.string;
    };
    run = ''
      echo "Static env: $INPUT_fromStatic"
      echo "Provider env: $INPUT_fromProvider"
    '';
  };

  # Chain action - takes input, transforms, outputs
  transform = sdk.mkAction {
    name = "transform";
    inputs = {
      input = types.string;
      suffix = types.withDefault types.string "-transformed";
    };
    outputs = {
      result = types.string;
    };
    run = ''
      OUTPUT_result="$INPUT_input$INPUT_suffix"
      echo "Transformed: $INPUT_input -> $OUTPUT_result"
    '';
  };

in nixactions.mkWorkflow {
  name = "test-sdk-refs";
  
  extensions = [ sdk.validation ];
  
  jobs = {
    # Test 1: stepOutput - passing data between steps
    test-step-output = {
      inherit executor;
      steps = [
        # Step 1: Produce values
        (produce { prefix = "TEST"; })
        
        # Step 2: Consume individual outputs
        (consume { 
          a = sdk.stepOutput "produce" "valueA";
          b = sdk.stepOutput "produce" "valueB";
        })
        
        # Step 3: Use combined output
        (useCombined {
          value = sdk.stepOutput "produce" "combined";
        })
      ];
    };
    
    # Test 2: fromEnv - using environment variables
    test-from-env = {
      inherit executor;
      env = {
        STATIC_VAR = "static-value";
        DYNAMIC_VAR = "dynamic-value";
      };
      steps = [
        (useEnv {
          fromStatic = sdk.fromEnv "STATIC_VAR";
          fromProvider = sdk.fromEnv "DYNAMIC_VAR";
        })
      ];
    };
    
    # Test 3: Chaining - multiple transforms
    test-chaining = {
      inherit executor;
      steps = [
        # Start chain
        (transform { input = "START"; suffix = "-step1"; })
        
        # Continue chain
        (transform { 
          input = sdk.stepOutput "transform" "result";
          suffix = "-step2";
        })
        
        # Final step - verify chain
        {
          name = "verify-chain";
          bash = ''
            # shellcheck disable=SC2154
            if [ "$STEP_OUTPUT_transform_result" = "START-step1-step2" ]; then
              echo "SUCCESS: Chain result is correct: $STEP_OUTPUT_transform_result"
            else
              echo "FAILURE: Expected 'START-step1-step2', got '$STEP_OUTPUT_transform_result'"
              exit 1
            fi
          '';
        }
      ];
    };
    
    # Test 4: Mixed refs and literals
    test-mixed = {
      inherit executor;
      env = {
        PREFIX = "ENV";
      };
      steps = [
        (produce { prefix = "MIXED"; })
        
        # Mix literal, stepOutput, and fromEnv
        (sdk.mkAction {
          name = "mix-all";
          inputs = {
            literal = types.string;
            fromStep = types.string;
            fromEnv = types.string;
          };
          run = ''
            echo "Literal: $INPUT_literal"
            echo "From step: $INPUT_fromStep"
            echo "From env: $INPUT_fromEnv"
            
            # Verify all are present
            if [ -n "$INPUT_literal" ] && [ -n "$INPUT_fromStep" ] && [ -n "$INPUT_fromEnv" ]; then
              echo "SUCCESS: All inputs received"
            else
              echo "FAILURE: Some inputs missing"
              exit 1
            fi
          '';
        } {
          literal = "direct-value";
          fromStep = sdk.stepOutput "produce" "valueA";
          fromEnv = sdk.fromEnv "PREFIX";
        })
      ];
    };
  };
}
