{ pkgs, lib, actions }:

# Buildah Build and Push Pipeline
#
# Multi-stage pipeline for building and pushing container images using buildah.
# This job template provides a complete workflow for container image management
# without requiring Docker daemon.
#
# This job template provides:
#   - Rootless container builds with buildah
#   - Multi-architecture support
#   - Optional testing stage
#   - Configurable push stage
#   - Flexible image tagging
#   - Support for multiple images
#
# Parameters:
#   - executor (required): Executor to run all jobs
#   - jobPrefix (optional): Prefix for job names [default: "buildah-"]
#   - registry (required): Container registry URL (e.g., "docker.io", "ghcr.io")
#   - images (required): List of image configurations
#       Each image: { 
#         name: Image name (e.g., "myapp")
#         context?: Build context path [default: "."]
#         dockerfile?: Dockerfile path [default: "Dockerfile"]
#         tags?: List of tags [default: ["latest"]]
#         platforms?: List of platforms [default: ["linux/amd64"]]
#       }
#   - registryUsername (optional): Registry username env var name [default: "REGISTRY_USERNAME"]
#   - registryPassword (optional): Registry password env var name [default: "REGISTRY_PASSWORD"]
#   - runTests (optional): Run tests before pushing [default: false]
#   - testCommand (optional): Test command to run [default: null]
#   - pushOnSuccess (optional): Push images after successful build/tests [default: true]
#   - buildArgs (optional): Build arguments as attribute set [default: {}]
#   - buildahExtraArgs (optional): Extra buildah arguments [default: ""]
#   - saveArtifacts (optional): Save built images as artifacts [default: false]
#   - artifactName (optional): Name for saved image artifacts [default: "container-images"]
#   - envProviders (optional): List of env providers for secrets [default: []]
#
# Environment Variables (configurable names):
#   The job expects these environment variables (names can be customized):
#   - {registryUsername}: Registry username for authentication (optional)
#   - {registryPassword}: Registry password for authentication (optional)
#
# Returns:
#   Attribute set with scoped jobs: { {jobPrefix}build, {jobPrefix}test?, {jobPrefix}push? }
#
# Usage:
#   jobs = jobs.buildahBuildPush {
#     executor = executors.local;
#     jobPrefix = "container-";  # Creates: container-build, container-test, container-push
#     registry = "docker.io/myuser";
#     images = [
#       { 
#         name = "api";
#         context = "./api";
#         tags = ["latest" "v1.0.0"];
#       }
#       { 
#         name = "worker";
#         context = "./worker";
#         dockerfile = "Dockerfile.worker";
#       }
#     ];
#     runTests = true;
#     pushOnSuccess = true;
#   };
#
# Complete Example:
#   { nixactions }:
#   
#   nixactions.mkWorkflow {
#     name = "container-pipeline";
#     
#     jobs = nixactions.jobs.buildahBuildPush {
#       executor = nixactions.executors.local;
#       jobPrefix = "app-";
#       registry = "ghcr.io/myorg";
#       images = [
#         {
#           name = "backend";
#           context = "./backend";
#           tags = ["latest" "dev"];
#           platforms = ["linux/amd64" "linux/arm64"];
#         }
#       ];
#       buildArgs = {
#         NODE_VERSION = "20";
#         BUILD_ENV = "production";
#       };
#       runTests = true;
#       testCommand = "podman run --rm \${IMAGE_REF} npm test";
#       envProviders = [
#         (nixactions.platform.envProviders.required [
#           "REGISTRY_USERNAME"
#           "REGISTRY_PASSWORD"
#         ])
#       ];
#     };
#   }
#
# Notes:
#   - buildah must be available in the executor environment
#   - For registry authentication, provide credentials via envProviders
#   - Multi-platform builds require qemu-user-static for emulation
#   - Images are built in parallel when possible
#   - Use jobPrefix to avoid conflicts when combining multiple pipelines

{
  executor,
  jobPrefix ? "buildah-",  # Default prefix to avoid conflicts
  
  # Registry configuration
  registry,
  
  # Images configuration
  images,
  
  # Authentication (env var names)
  registryUsername ? "REGISTRY_USERNAME",
  registryPassword ? "REGISTRY_PASSWORD",
  
  # Pipeline stages
  runTests ? false,
  testCommand ? null,
  pushOnSuccess ? true,
  
  # Build configuration
  buildArgs ? {},
  buildahExtraArgs ? "",
  
  # Artifacts
  saveArtifacts ? false,
  artifactName ? "container-images",
  
  # Environment providers
  envProviders ? [],
}:

# Validate parameters
assert lib.assertMsg (images != []) "images list cannot be empty";
assert lib.assertMsg (registry != "") "registry cannot be empty";

let
  # Scoped job names
  buildJob = "${jobPrefix}build";
  testJob = "${jobPrefix}test";
  pushJob = "${jobPrefix}push";
  
  # Normalize image configurations
  normalizeImage = image: {
    name = image.name;
    context = image.context or ".";
    dockerfile = image.dockerfile or "Dockerfile";
    tags = image.tags or ["latest"];
    platforms = image.platforms or ["linux/amd64"];
  };
  
  normalizedImages = map normalizeImage images;
  
  # Build buildah build-args string
  buildArgsString = lib.concatStringsSep " " (
    lib.mapAttrsToList (key: value: "--build-arg ${key}=${value}") buildArgs
  );
  
  # Generate build script for a single image
  buildImageScript = image: ''
    echo "Building image: ${registry}/${image.name}"
    
    ${lib.concatMapStringsSep "\n" (platform: ''
      echo "Building for platform: ${platform}"
      ${lib.concatMapStringsSep "\n" (tag: ''
        echo "  Tag: ${tag}"
        if ! buildah build \
          --platform ${platform} \
          --tag ${registry}/${image.name}:${tag} \
          --file ${image.context}/${image.dockerfile} \
          ${buildArgsString} \
          ${buildahExtraArgs} \
          ${image.context}; then
          echo "Error: Failed to build ${registry}/${image.name}:${tag} for ${platform}"
          exit 1
        fi
      '') image.tags}
    '') image.platforms}
    
    echo "Successfully built ${registry}/${image.name}"
  '';
  
  # Generate push script for a single image
  pushImageScript = image: ''
    echo "Pushing image: ${registry}/${image.name}"
    
    ${lib.concatMapStringsSep "\n" (tag: ''
      echo "  Pushing tag: ${tag}"
      if ! buildah push ${registry}/${image.name}:${tag}; then
        echo "Error: Failed to push ${registry}/${image.name}:${tag}"
        exit 1
      fi
    '') image.tags}
    
    echo "Successfully pushed ${registry}/${image.name}"
  '';
  
  # Generate save script for artifacts
  saveImagesScript = ''
    echo "Saving container images as artifacts..."
    mkdir -p container-images
    
    ${lib.concatMapStringsSep "\n" (image:
      lib.concatMapStringsSep "\n" (tag: ''
        IMAGE_FILE="container-images/${image.name}-${tag}.tar"
        echo "Saving ${registry}/${image.name}:${tag} to $IMAGE_FILE"
        buildah push ${registry}/${image.name}:${tag} docker-archive:$IMAGE_FILE
      '') image.tags
    ) normalizedImages}
    
    echo "All images saved to container-images/"
  '';
  
in

{
  # Build stage
  ${buildJob} = {
    inherit executor;
    inherit envProviders;
    
    actions = [
      actions.checkout
      
      {
        name = "setup-buildah";
        deps = [ pkgs.buildah ];
        bash = ''
          echo "Setting up buildah..."
          buildah version
          
          # Ensure storage is initialized
          buildah images || true
        '';
      }
    ]
    ++ (map (image: {
      name = "build-${image.name}";
      deps = [ pkgs.buildah ];
      bash = buildImageScript image;
    }) normalizedImages)
    ++ (lib.optional saveArtifacts {
      name = "save-images";
      deps = [ pkgs.buildah ];
      bash = saveImagesScript;
    });
    
    # Save built images as artifacts if requested
    outputs = lib.optionalAttrs saveArtifacts {
      ${artifactName} = "container-images/";
    };
  };
  
  # Test stage (optional)
  ${testJob} = lib.optionalAttrs runTests {
    inherit executor;
    inherit envProviders;
    needs = [ buildJob ];  # Reference scoped name
    
    actions = if testCommand != null then
      # Use provided test command
      (map (image:
        let firstTag = builtins.head image.tags;
        in {
          name = "test-${image.name}";
          deps = [ pkgs.buildah ];
          bash = ''
            IMAGE_REF="${registry}/${image.name}:${firstTag}"
            echo "Testing image: $IMAGE_REF"
            ${testCommand}
          '';
        }
      ) normalizedImages)
    else
      # Default: basic smoke test
      (map (image:
        let firstTag = builtins.head image.tags;
        in {
          name = "test-${image.name}";
          deps = [ pkgs.buildah ];
          bash = ''
            echo "Running smoke test for ${registry}/${image.name}:${firstTag}"
            buildah inspect ${registry}/${image.name}:${firstTag}
            echo "Image inspection successful"
          '';
        }
      ) normalizedImages);
  };
  
  # Push stage (optional)
  ${pushJob} = lib.optionalAttrs pushOnSuccess {
    inherit executor;
    inherit envProviders;
    needs = if runTests then [ testJob ] else [ buildJob ];  # Reference scoped names
    
    actions = [
      {
        name = "registry-login";
        deps = [ pkgs.buildah ];
        bash = ''
          if [ -n "''${${registryUsername}:-}" ] && [ -n "''${${registryPassword}:-}" ]; then
            echo "Logging in to ${registry}..."
            if echo "''${${registryPassword}}" | buildah login \
              --username "''${${registryUsername}}" \
              --password-stdin \
              ${registry}; then
              echo "Successfully logged in to ${registry}"
            else
              echo "Error: Failed to login to ${registry}"
              exit 1
            fi
          else
            echo "Warning: Registry credentials not provided"
            echo "Skipping authentication (registry might be public or already authenticated)"
          fi
        '';
      }
    ]
    ++ (map (image: {
      name = "push-${image.name}";
      deps = [ pkgs.buildah ];
      bash = pushImageScript image;
    }) normalizedImages)
    ++ [
      {
        name = "registry-logout";
        "if" = "always()";  # Always logout
        deps = [ pkgs.buildah ];
        bash = ''
          if [ -n "''${${registryUsername}:-}" ]; then
            echo "Logging out from ${registry}..."
            buildah logout ${registry} || true
          fi
        '';
      }
    ];
  };
}
