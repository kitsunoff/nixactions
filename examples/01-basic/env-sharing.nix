# Example: Environment variable sharing between actions
# Demonstrates practical patterns for sharing data between actions in a job

{ pkgs, platform, executor ? platform.executors.local }:

platform.mkWorkflow {
  name = "env-sharing-demo";
  
  jobs = {
    # Job 1: Build with version and metadata
    build = {
      inherit executor;
      
      actions = [
        {
          name = "generate-version";
          bash = ''
            echo "→ Generating version information..."
            
            # Generate version from git or timestamp
            VERSION="1.2.3-$(date +%Y%m%d)"
            BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            COMMIT_HASH="abc123def456"
            
            echo "  VERSION=$VERSION"
            echo "  BUILD_TIME=$BUILD_TIME"
            echo "  COMMIT_HASH=$COMMIT_HASH"
            
            # Save variables to JOB_ENV for next actions (actions run as separate processes)
            cat >> "$JOB_ENV" <<EOF
VERSION=$VERSION
BUILD_TIME=$BUILD_TIME
COMMIT_HASH=$COMMIT_HASH
EOF
          '';
        }
        
        {
          name = "build-app";
          bash = ''
            echo "→ Building application with metadata..."
            
            # Variables from previous action are available (executor sourced JOB_ENV)!
            echo "  Using VERSION: $VERSION"
            echo "  Using BUILD_TIME: $BUILD_TIME"
            echo "  Using COMMIT_HASH: $COMMIT_HASH"
            
            # Create build artifact
            mkdir -p dist
            cat > dist/build-info.json <<EOF
            {
              "version": "$VERSION",
              "buildTime": "$BUILD_TIME",
              "commitHash": "$COMMIT_HASH"
            }
            EOF
            
            echo "✓ Build completed: dist/build-info.json"
            cat dist/build-info.json
          '';
        }
        
        {
          name = "verify-build";
          bash = ''
            echo "→ Verifying build metadata..."
            
            # All variables still available in this action too!
            echo "  VERSION from env: $VERSION"
            
            # Read from build artifact
            if grep -q "$VERSION" dist/build-info.json; then
              echo "✓ Version matches in build artifact"
            else
              echo "✗ Version mismatch!"
              exit 1
            fi
            
            if grep -q "$COMMIT_HASH" dist/build-info.json; then
              echo "✓ Commit hash matches in build artifact"
            else
              echo "✗ Commit hash mismatch!"
              exit 1
            fi
          '';
        }
      ];
      
      outputs = {
        build-info = "dist/";
      };
    };
    
    # Job 2: Advanced pattern - Using JOB_ENV file explicitly
    test-advanced = {
      needs = [ "build" ];
      inherit executor;
      
      inputs = [ "build-info" ];
      
      actions = [
        {
          name = "parse-build-info";
          bash = ''
            echo "→ Parsing build information from artifact..."
            
            # Extract version from artifact (new job, variables are not inherited)
            # Use sed for portability (works on both GNU and BSD)
            ARTIFACT_VERSION=$(grep '"version"' dist/build-info.json | sed 's/.*"version": "\([^"]*\)".*/\1/')
            
            echo "  Found version in artifact: $ARTIFACT_VERSION"
            
            # Save to JOB_ENV for next actions (actions run as separate processes!)
            cat >> "$JOB_ENV" <<EOF
PARSED_VERSION=$ARTIFACT_VERSION
SAVED_VERSION=$ARTIFACT_VERSION
EOF
            
            echo "✓ Version parsed and saved"
          '';
        }
        
        {
          name = "use-parsed-version";
          bash = ''
            echo "→ Using parsed version..."
            
            # Both variables sourced from JOB_ENV (executor auto-sourced it)
            echo "  PARSED_VERSION (from JOB_ENV): $PARSED_VERSION"
            echo "  SAVED_VERSION (from JOB_ENV): $SAVED_VERSION"
            
            if [ "$PARSED_VERSION" = "$SAVED_VERSION" ]; then
              echo "✓ Both variables loaded correctly from JOB_ENV"
            else
              echo "✗ Variables don't match!"
              exit 1
            fi
          '';
        }
      ];
    };
    
    # Job 3: Pattern for complex calculations
    calculate = {
      needs = [ "build" ];
      inherit executor;
      
      inputs = [ "build-info" ];
      
      actions = [
        {
          name = "multi-step-calculation";
          bash = ''
            echo "→ Multi-step calculation example..."
            
            # Step 1: Extract base values (using sed for portability)
            BASE_VERSION=$(grep '"version"' dist/build-info.json | sed 's/.*"version": "\([^"]*\)".*/\1/')
            echo "  BASE_VERSION=$BASE_VERSION"
            
            # Step 2: Process version
            MAJOR=$(echo "$BASE_VERSION" | cut -d. -f1)
            MINOR=$(echo "$BASE_VERSION" | cut -d. -f2)
            PATCH=$(echo "$BASE_VERSION" | cut -d. -f3 | cut -d- -f1)
            
            echo "  MAJOR=$MAJOR"
            echo "  MINOR=$MINOR"
            echo "  PATCH=$PATCH"
            
            # Step 3: Calculate derived values
            NEXT_PATCH=$((PATCH + 1))
            NEXT_VERSION="$MAJOR.$MINOR.$NEXT_PATCH"
            
            echo "  NEXT_VERSION=$NEXT_VERSION"
            
            # Save for next action
            cat >> "$JOB_ENV" <<EOF
BASE_VERSION=$BASE_VERSION
MAJOR=$MAJOR
MINOR=$MINOR
PATCH=$PATCH
NEXT_VERSION=$NEXT_VERSION
EOF
          '';
        }
        
        {
          name = "use-calculations";
          bash = ''
            echo "→ Using calculated values..."
            
            # All variables from previous action available
            echo "  Current version: $BASE_VERSION"
            echo "  Parsed as: $MAJOR.$MINOR.$PATCH"
            echo "  Next version would be: $NEXT_VERSION"
            
            # Example: Create version bump suggestion
            cat > version-bump.txt <<EOF
            Current: $BASE_VERSION
            Suggested next patch: $NEXT_VERSION
            EOF
            
            echo "✓ Version calculations complete"
            cat version-bump.txt
          '';
        }
      ];
    };
    
    # Summary
    summary = {
      needs = [ "test-advanced" "calculate" ];
      inherit executor;
      
      actions = [{
        name = "summary";
        bash = ''
          echo ""
          echo "╔═══════════════════════════════════════════════════╗"
          echo "║  Environment Variable Sharing - Summary          ║"
          echo "╚═══════════════════════════════════════════════════╝"
          echo ""
          echo "✅ Pattern 1: Write to JOB_ENV file"
          echo "   • Actions run as SEPARATE PROCESSES"
          echo "   • Save vars: echo \"VAR=value\" >> \$JOB_ENV"
          echo "   • Executor auto-sources JOB_ENV before each action"
          echo "   • Variables then available: \$VAR"
          echo ""
          echo "✅ Pattern 2: Heredoc for multiple vars"
          echo "   • cat >> \$JOB_ENV <<EOF"
          echo "   • VAR1=value1"
          echo "   • VAR2=value2"
          echo "   • EOF"
          echo ""
          echo "✅ Pattern 3: Artifacts for cross-job data"
          echo "   • Save data to files (JSON, txt, etc.)"
          echo "   • Use outputs/inputs for sharing"
          echo "   • Parse in dependent jobs"
          echo ""
          echo "💡 Best practices:"
          echo "   • Always write to \$JOB_ENV to share vars"
          echo "   • Executor sources JOB_ENV automatically"
          echo "   • Actions are isolated processes (clean)"
          echo "   • Use artifacts for cross-job sharing"
          echo ""
        '';
      }];
    };
  };
}
