# Kubernetes Executor Matrix Test
# 
# This example demonstrates the K8s executor with 10 parallel matrix jobs.
# Tests dedicated mode where each job gets its own pod.
# 
# Prerequisites:
# 1. Kubernetes cluster accessible via kubectl
# 2. Container registry with push access
# 3. Environment variables set:
#    - REGISTRY_USER: Registry username
#    - REGISTRY_PASSWORD: Registry password/token
#
# Usage:
#   # With Kind cluster (recommended for testing)
#   ./scripts/test-k8s-kind.sh matrix
#
#   # With manual local registry
#   docker run -d -p 5001:5000 --name registry registry:2
#   REGISTRY_USER=unused REGISTRY_PASSWORD=unused nix run .#example-test-k8s-matrix-dedicated

{ pkgs
, nixactions
, executor  # K8s executor must be provided (requires registry config)
}:

let
  # Generate 10 matrix jobs for testing parallel pod execution
  matrixJobs = nixactions.mkMatrixJobs {
    name = "worker";
    
    # Matrix configuration - generates worker-id-1 through worker-id-10
    matrix = {
      id = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" ];
    };
    
    # Each matrix job definition
    jobTemplate = { id }: {
      inherit executor;
      env = {
        WORKER_ID = id;
        WORKER_NAME = "worker-${id}";
      };
      actions = [
        {
          name = "init";
          bash = ''
            echo "=== Worker ${id} starting ==="
            echo "Pod hostname: $(hostname)"
            echo "Worker ID: $WORKER_ID"
            echo "Worker Name: $WORKER_NAME"
          '';
        }
        {
          name = "simulate-work";
          bash = ''
            # Simulate some work with variable duration
            DURATION=$((2 + (RANDOM % 3)))
            echo "Worker ${id}: Processing for $DURATION seconds..."
            sleep $DURATION
            
            # Create output file
            echo "Worker ${id} result" > "result-${id}.txt"
            echo "Completed at: $(date)" >> "result-${id}.txt"
            echo "Hostname: $(hostname)" >> "result-${id}.txt"
          '';
        }
        {
          name = "report";
          bash = ''
            echo "=== Worker ${id} completed ==="
            cat "result-${id}.txt"
          '';
        }
      ];
      outputs = {
        "result-${id}" = "result-${id}.txt";
      };
    };
  };

  # Aggregator job that collects all results
  aggregatorJob = {
    aggregate = {
      inherit executor;
      needs = builtins.attrNames matrixJobs;  # Wait for all workers
      inputs = builtins.map (id: "result-${id}") [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" ];
      actions = [
        {
          name = "collect-results";
          bash = ''
            echo "=== Collecting results from all workers ==="
            echo ""
            
            for i in $(seq 1 10); do
              if [ -f "result-$i.txt" ]; then
                echo "--- Result from worker $i ---"
                cat "result-$i.txt"
                echo ""
              else
                echo "WARNING: result-$i.txt not found!"
              fi
            done
          '';
        }
        {
          name = "summary";
          bash = ''
            echo "=== Matrix Test Summary ==="
            TOTAL=$(find . -maxdepth 1 -name 'result-*.txt' -type f | wc -l | tr -d ' ')
            echo "Total workers completed: $TOTAL / 10"
            
            if [ "$TOTAL" -eq 10 ]; then
              echo "SUCCESS: All 10 workers completed!"
            else
              echo "FAILED: Expected 10 workers, got $TOTAL"
              exit 1
            fi
          '';
        }
      ];
    };
  };

in
nixactions.mkWorkflow {
  name = "k8s-matrix-test";
  
  # Combine matrix jobs with aggregator
  jobs = matrixJobs // aggregatorJob;
}
