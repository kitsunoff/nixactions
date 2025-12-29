# Kubernetes Executor Test
# 
# This example demonstrates the K8s executor running jobs in Kubernetes pods.
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
#   ./scripts/test-k8s-kind.sh shared
#
#   # With manual local registry
#   docker run -d -p 5001:5000 --name registry registry:2
#   REGISTRY_USER=unused REGISTRY_PASSWORD=unused nix run .#example-test-k8s-shared
#
#   # With real registry
#   REGISTRY_USER=myuser REGISTRY_PASSWORD=mytoken nix run .#example-test-k8s-shared

{ pkgs
, nixactions
, executor  # K8s executor must be provided (requires registry config)
}:

nixactions.mkWorkflow {
  name = "k8s-test";
  
  jobs = {
    hello = {
      inherit executor;
      steps = [
        {
          name = "greet";
          bash = "echo 'Hello from Kubernetes!'";
        }
        {
          name = "hostname";
          bash = "hostname";
        }
        {
          name = "env";
          bash = "env | grep -E '^(WORKFLOW|NIXACTIONS)' | sort || true";
        }
        {
          name = "workspace";
          bash = "pwd && ls -la";
        }
      ];
    };
    
    build = {
      inherit executor;
      needs = [ "hello" ];
      steps = [
        {
          name = "create-artifact";
          bash = ''
            echo "Build output from K8s pod" > build-output.txt
            echo "Timestamp: $(date)" >> build-output.txt
            cat build-output.txt
          '';
        }
      ];
      outputs = {
        build-result = "build-output.txt";
      };
    };
    
    verify = {
      inherit executor;
      needs = [ "build" ];
      inputs = [ "build-result" ];
      steps = [
        {
          name = "check-artifact";
          bash = ''
            echo "Checking artifact from previous job..."
            cat build-output.txt
            test -f build-output.txt && echo "✓ Artifact restored successfully"
          '';
        }
      ];
    };
  };
}
