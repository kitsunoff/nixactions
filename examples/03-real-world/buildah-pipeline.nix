{ pkgs, platform, executor ? platform.executors.local }:

# Buildah Container Build Pipeline Example
#
# This example demonstrates how to use the buildahBuildPush job template
# to build and push container images using buildah.
#
# Features demonstrated:
#   - Multi-image builds
#   - Custom tags and platforms
#   - Build arguments
#   - Optional testing stage
#   - Registry authentication
#   - Artifact saving

platform.mkWorkflow {
  name = "buildah-pipeline";
  
  jobs = platform.jobs.buildahBuildPush {
    inherit executor;
    
    # Job naming
    jobPrefix = "container-";  # Creates: container-build, container-test, container-push
    
    # Registry configuration
    registry = "docker.io/myusername";  # Change to your registry
    
    # Images to build
    images = [
      {
        name = "demo-app";
        context = "./examples/03-real-world/demo-app";
        dockerfile = "Dockerfile";
        tags = ["latest" "v1.0.0" "dev"];
        platforms = ["linux/amd64"];  # Add "linux/arm64" for multi-arch
      }
    ];
    
    # Build configuration
    buildArgs = {
      NODE_VERSION = "20";
      BUILD_ENV = "production";
      APP_VERSION = "1.0.0";
    };
    
    # Pipeline stages
    runTests = true;
    testCommand = ''
      # Basic smoke test - check if container starts
      echo "Testing $IMAGE_REF"
      
      # Test with podman/docker
      if command -v podman &> /dev/null; then
        podman run --rm "$IMAGE_REF" echo "Container test passed"
      elif command -v docker &> /dev/null; then
        docker run --rm "$IMAGE_REF" echo "Container test passed"
      else
        echo "Warning: Neither podman nor docker found, skipping runtime test"
        buildah inspect "$IMAGE_REF"
      fi
    '';
    
    pushOnSuccess = true;
    
    # Save images as artifacts (optional)
    saveArtifacts = true;
    artifactName = "built-images";
    
    # Environment providers for secrets
    envProviders = [
      # Option 1: Use sops for secrets
      # (platform.envProviders.sops {
      #   file = ./secrets.sops.yaml;
      # })
      
      # Option 2: Require env vars to be set
      (platform.envProviders.required [
        "REGISTRY_USERNAME"
        "REGISTRY_PASSWORD"
      ])
      
      # Option 3: Static values (for testing only!)
      # (platform.envProviders.static {
      #   REGISTRY_USERNAME = "testuser";
      #   REGISTRY_PASSWORD = "testpass";
      # })
    ];
  };
}
