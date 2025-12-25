{ pkgs, platform }:

# Multi-Image Buildah Pipeline Example
#
# This example demonstrates building multiple container images
# in a single pipeline with different configurations.

platform.mkWorkflow {
  name = "multi-image-pipeline";
  
  jobs = platform.jobs.buildahBuildPush {
    executor = platform.executors.local;
    
    # Job naming
    jobPrefix = "multi-";
    
    # Registry configuration
    registry = "ghcr.io/myorg";
    
    # Multiple images with different configs
    images = [
      # Frontend image
      {
        name = "frontend";
        context = "./examples/03-real-world/demo-app";
        dockerfile = "Dockerfile";
        tags = ["latest" "frontend-v1"];
        platforms = ["linux/amd64"];
      }
      
      # Backend image (same source, different config)
      {
        name = "backend";
        context = "./examples/03-real-world/demo-app";
        dockerfile = "Dockerfile";
        tags = ["latest" "backend-v1"];
        platforms = ["linux/amd64"];
      }
    ];
    
    # Build arguments (applied to all images)
    buildArgs = {
      NODE_VERSION = "20";
      BUILD_ENV = "staging";
      APP_VERSION = "2.0.0";
    };
    
    # Additional buildah arguments
    buildahExtraArgs = "--layers --force-rm";
    
    # Enable testing
    runTests = true;
    testCommand = ''
      echo "Testing image: $IMAGE_REF"
      buildah inspect $IMAGE_REF | grep -q "alpine"
      echo "✓ Image verified"
    '';
    
    # Don't push (for local testing)
    pushOnSuccess = false;
    
    # Save artifacts
    saveArtifacts = true;
    artifactName = "container-images";
    
    # Custom env var names for credentials
    registryUsername = "GH_USERNAME";
    registryPassword = "GH_TOKEN";
    
    # Environment providers
    envProviders = [
      # For GitHub Container Registry, you might use:
      # (platform.envProviders.sops {
      #   file = ./github-secrets.sops.yaml;
      # })
    ];
  };
}
