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
#   # With local registry (for testing)
#   docker run -d -p 5000:5000 --name registry registry:2
#   REGISTRY_USER=unused REGISTRY_PASSWORD=unused nix run .#example-test-k8s-shared
#
#   # With real registry
#   REGISTRY_USER=myuser REGISTRY_PASSWORD=mytoken nix run .#example-test-k8s-shared

{ pkgs
, platform
, executor ? platform.executors.k8s {
    namespace = "default";
    registry = {
      url = "localhost:5000";  # Local registry for testing
      usernameEnv = "REGISTRY_USER";
      passwordEnv = "REGISTRY_PASSWORD";
    };
    mode = "shared";
  }
}:

platform.mkWorkflow {
  name = "k8s-test";
  
  jobs = {
    hello = {
      inherit executor;
      steps = [
        { name = "greet"; run = "echo 'Hello from Kubernetes!'"; }
        { name = "hostname"; run = "hostname"; }
        { name = "env"; run = "env | grep -E '^(WORKFLOW|NIXACTIONS)' | sort"; }
        { name = "workspace"; run = "pwd && ls -la"; }
      ];
    };
    
    build = {
      inherit executor;
      needs = [ "hello" ];
      steps = [
        { name = "create-artifact"; run = ''
            echo "Build output from K8s pod" > build-output.txt
            echo "Timestamp: $(date)" >> build-output.txt
            cat build-output.txt
          '';
        }
      ];
      outputs = [
        { name = "build-result"; path = "build-output.txt"; }
      ];
    };
    
    verify = {
      inherit executor;
      needs = [ "build" ];
      inputs = [
        { name = "build-result"; from = "build"; }
      ];
      steps = [
        { name = "check-artifact"; run = ''
            echo "Checking artifact from previous job..."
            cat build-output.txt
            test -f build-output.txt && echo "✓ Artifact restored successfully"
          '';
        }
      ];
    };
  };
}
