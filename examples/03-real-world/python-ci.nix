# Real-world example: Python CI/CD pipeline
# - Run unit tests with pytest
# - Build Docker image
# - Push to registry (simulated)
{ pkgs, platform }:

platform.mkWorkflow {
  name = "python-ci-cd";
  
  # Workflow-level environment
  env = {
    PYTHON_VERSION = "3.11";
    DOCKER_REGISTRY = "registry.example.com";
    IMAGE_NAME = "math-app";
    IMAGE_TAG = "v1.0.0";
  };
  
  jobs = {
    # === Level 0: Parallel checks ===
    
    lint = {
      executor = platform.executors.local;
      
      actions = [
        {
          name = "checkout-code";
          bash = ''
            echo "→ Checking out code (simulated)"
            echo "  Working directory: $PWD"
            
            # In real scenario, this would be: git clone ...
            # For demo, we create the Python application
            cat > app.py << 'EOF'
def add(a, b):
    """Add two numbers."""
    return a + b

def multiply(a, b):
    """Multiply two numbers."""
    return a * b

if __name__ == "__main__":
    print("Math App v1.0")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"4 * 5 = {multiply(4, 5)}")
EOF
            
            # Create unit tests
            cat > test_app.py << 'EOF'
import sys
sys.path.insert(0, '.')
from app import add, multiply

def test_add():
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
    assert add(0, 0) == 0

def test_multiply():
    assert multiply(2, 3) == 6
    assert multiply(-1, 5) == -5
    assert multiply(0, 10) == 0

if __name__ == "__main__":
    test_add()
    test_multiply()
    print("All tests passed!")
EOF
            
            # Create requirements.txt
            cat > requirements.txt << 'EOF'
pytest==7.4.0
pytest-cov==4.1.0
EOF
            
            echo "✓ Code checked out"
            echo ""
            ls -la
          '';
        }
        
        {
          name = "lint-python";
          deps = [ pkgs.python311 pkgs.python311Packages.flake8 ];
          bash = ''
            echo "→ Linting Python code with flake8"
            
            # Lint with relaxed rules for example
            flake8 app.py test_app.py --max-line-length=100 || true
            
            echo "✓ Linting complete"
          '';
        }
      ];
    };
    
    type-check = {
      executor = platform.executors.local;
      
      actions = [
        {
          name = "setup-code-for-typecheck";
          bash = ''
            echo "→ Setting up code for type checking"
            
            # Note: Each job runs in isolation (subshell)
            # So we recreate the Python app here
            cat > app.py << 'EOF'
def add(a, b):
    """Add two numbers."""
    return a + b

def multiply(a, b):
    """Multiply two numbers."""
    return a * b

if __name__ == "__main__":
    print("Math App v1.0")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"4 * 5 = {multiply(4, 5)}")
EOF
          '';
        }
        
        {
          name = "run-mypy";
          deps = [ pkgs.python311 pkgs.python311Packages.mypy ];
          bash = ''
            echo "→ Type checking with mypy"
            
            # Basic type check (app.py has no type hints, so this is lenient)
            mypy app.py --ignore-missing-imports || true
            
            echo "✓ Type checking complete"
          '';
        }
      ];
    };
    
    # === Level 1: Tests (after checks) ===
    
    test = {
      needs = [ "lint" "type-check" ];
      executor = platform.executors.local;
      
      actions = [
        {
          name = "checkout-code";
          bash = ''
            echo "→ Checking out code"
            
            # Each job needs to checkout code (isolated workspace)
            cat > app.py << 'EOF'
def add(a, b):
    """Add two numbers."""
    return a + b

def multiply(a, b):
    """Multiply two numbers."""
    return a * b

if __name__ == "__main__":
    print("Math App v1.0")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"4 * 5 = {multiply(4, 5)}")
EOF
            
            cat > test_app.py << 'EOF'
import sys
sys.path.insert(0, '.')
from app import add, multiply

def test_add():
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
    assert add(0, 0) == 0

def test_multiply():
    assert multiply(2, 3) == 6
    assert multiply(-1, 5) == -5
    assert multiply(0, 10) == 0

if __name__ == "__main__":
    test_add()
    test_multiply()
    print("All tests passed!")
EOF
            
            cat > requirements.txt << 'EOF'
pytest==7.4.0
pytest-cov==4.1.0
EOF
            
            echo "✓ Code checked out"
          '';
        }
        
        {
          name = "install-dependencies";
          deps = [ pkgs.python311 pkgs.python311Packages.pip ];
          bash = ''
            echo "→ Installing test dependencies"
            
            # Create virtual environment
            python -m venv venv
            # shellcheck disable=SC1091
            source venv/bin/activate
            
            # Install dependencies
            pip install --quiet -r requirements.txt
            
            echo "✓ Dependencies installed"
          '';
        }
        
        {
          name = "run-unit-tests";
          deps = [ pkgs.python311 ];
          bash = ''
            echo "→ Running unit tests with pytest"
            # shellcheck disable=SC1091
            source venv/bin/activate
            
            # Run tests with coverage
            pytest test_app.py -v --cov=app --cov-report=term-missing
            
            echo ""
            echo "✓ All tests passed!"
          '';
        }
        
        {
          name = "test-app-execution";
          deps = [ pkgs.python311 ];
          bash = ''
            echo "→ Testing application execution"
            
            python app.py
            
            echo "✓ Application runs successfully"
          '';
        }
      ];
    };
    
    # === Level 2: Build Docker image (after tests) ===
    
    build-image = {
      needs = [ "test" ];
      executor = platform.executors.local;
      
      actions = [
        {
          name = "checkout-code";
          bash = ''
            echo "→ Checking out code"
            
            cat > app.py << 'EOF'
def add(a, b):
    """Add two numbers."""
    return a + b

def multiply(a, b):
    """Multiply two numbers."""
    return a * b

if __name__ == "__main__":
    print("Math App v1.0")
    print(f"2 + 3 = {add(2, 3)}")
    print(f"4 * 5 = {multiply(4, 5)}")
EOF
            
            echo "✓ Code checked out"
          '';
        }
        
        {
          name = "prepare-build-context";
          bash = ''
            echo "→ Preparing Docker build context"
            mkdir -p docker-build
            cp app.py docker-build/
            
            # Create Dockerfile
            cat > docker-build/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY app.py /app/

CMD ["python", "app.py"]
EOF
            
            echo "✓ Build context ready"
            ls -la docker-build/
          '';
        }
        
        {
          name = "build-docker-image";
          deps = [ pkgs.docker ];
          bash = ''
            echo "→ Building Docker image"
            cd docker-build
            
            IMAGE_FULL_NAME="$DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
            echo "  Image: $IMAGE_FULL_NAME"
            
            # Build image (requires Docker daemon running)
            # For demo, we'll simulate the build
            echo ""
            echo "╔═══════════════════════════════════════════════╗"
            echo "║ Docker Build Simulation                       ║"
            echo "╚═══════════════════════════════════════════════╝"
            echo ""
            echo "Would execute:"
            echo "  docker build -t $IMAGE_FULL_NAME ."
            echo ""
            echo "Build context:"
            cat Dockerfile
            echo ""
            echo "Application:"
            head -5 app.py
            echo "  ..."
            echo ""
            
            # Simulate successful build
            echo "✓ Docker image built successfully"
            echo "  Image: $IMAGE_FULL_NAME"
            echo "  Size: 150MB (simulated)"
          '';
        }
        
        {
          name = "scan-image";
          bash = ''
            echo "→ Scanning image for vulnerabilities"
            
            IMAGE_FULL_NAME="$DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
            
            echo "Would execute:"
            echo "  trivy image $IMAGE_FULL_NAME"
            echo ""
            echo "✓ No critical vulnerabilities found (simulated)"
          '';
        }
      ];
    };
    
    # === Level 3: Push (only on success) ===
    
    push-image = {
      needs = [ "build-image" ];
      "if" = "success()";
      executor = platform.executors.local;
      
      actions = [{
        name = "push-to-registry";
        bash = ''
          echo "→ Pushing image to registry"
          
          IMAGE_FULL_NAME="$DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
          
          echo "Would execute:"
          echo "  docker push $IMAGE_FULL_NAME"
          echo ""
          echo "✓ Image pushed successfully"
          echo "  Registry: $DOCKER_REGISTRY"
          echo "  Image: $IMAGE_NAME:$IMAGE_TAG"
        '';
      }];
    };
    
    # === Level 3: Notifications (parallel with push) ===
    
    notify-success = {
      needs = [ "build-image" ];
      "if" = "success()";
      executor = platform.executors.local;
      
      actions = [{
        name = "send-success-notification";
        deps = [ pkgs.curl ];
        bash = ''
          echo "→ Sending success notification"
          
          IMAGE_FULL_NAME="$DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
          
          echo "Would send to Slack/Discord:"
          echo "  ✅ Python CI/CD completed successfully!"
          echo "  • All tests passed"
          echo "  • Image built: $IMAGE_FULL_NAME"
          echo "  • Ready for deployment"
        '';
      }];
    };
    
    notify-failure = {
      needs = [ "build-image" ];
      "if" = "failure()";
      executor = platform.executors.local;
      
      actions = [{
        name = "send-failure-notification";
        bash = ''
          echo "→ Sending failure notification"
          
          echo "Would send to Slack/Discord:"
          echo "  ❌ Python CI/CD failed!"
          echo "  • Check logs for details"
          echo "  • Pipeline stopped"
        '';
      }];
    };
    
    # === Level 4: Cleanup (always runs) ===
    
    cleanup = {
      needs = [ "push-image" "notify-success" "notify-failure" ];
      "if" = "always()";
      executor = platform.executors.local;
      
      actions = [{
        name = "cleanup-temp-files";
        bash = ''
          echo "→ Cleaning up temporary files"
          
          # Remove build artifacts
          rm -rf docker-build venv __pycache__ .pytest_cache .coverage 2>/dev/null || true
          
          echo "✓ Cleanup complete"
          echo ""
          echo "Note: Workflow workspace will be cleaned automatically"
        '';
      }];
    };
  };
}
